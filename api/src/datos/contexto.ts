// EL ÚNICO FICHERO DEL PROYECTO QUE CONOCE EL POOL DE CONEXIONES.
//
// Decisión 1 de docs/arquitectura.md y regla 1 de CLAUDE.md. El aislamiento
// entre usuarios lo hacen las políticas RLS, que filtran por
// `app.usuario_actual()`, y esa función lee una variable de sesión que hay que
// fijar DENTRO de la transacción. Si se fija fuera, se pierde entre sentencia y
// sentencia y las consultas devuelven CERO FILAS sin dar ningún error. No es
// hipotético: la primera versión de db/pruebas/rls.sql fallaba exactamente así.
//
// De ahí la forma de este módulo:
//
//   - El pool NO se exporta. Nadie más puede pedir una conexión.
//   - `Tx` lleva una marca con un símbolo que no sale de aquí, así que no se
//     puede construir uno desde fuera.
//   - Un repositorio se declara `f(tx: Tx, ...)`, y la única forma de obtener un
//     `Tx` es estar dentro de `conUsuario()`. Consultar sin contexto no compila.
//   - El contexto se pasa como PARÁMETRO, no por almacenamiento asociado al
//     flujo. Un contexto implícito se pierde con un `await` mal colocado, en
//     silencio, y vuelve a devolver cero filas: sería reconstruir en TypeScript
//     el problema que ya se resolvió en SQL.
//
// El almacenamiento asociado al flujo sí se usa, pero SOLO para detectar
// anidamiento y fallar fuerte. Nunca para propagar.

import { AsyncLocalStorage } from "node:async_hooks";
import { Pool, type PoolClient, types } from "pg";

// Decisión 3: una fecha civil cruza el cable como cadena AAAA-MM-DD. Sin esto,
// node-postgres convierte `date` en un Date de JavaScript a medianoche local, y
// a partir de ahí toda aritmética y toda serialización es una ocasión de
// desfasar el día. 1082 es el OID de `date`.
types.setTypeParser(1082, (valor) => valor);

const OID_FECHA = 1082;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** La marca no se exporta: por eso un `Tx` no se puede fabricar desde fuera. */
declare const marcaDeTransaccion: unique symbol;

export type Tx = {
  readonly [marcaDeTransaccion]: true;
  /** Ejecuta dentro de la transacción con contexto. Devuelve las filas. */
  consultar<Fila extends Record<string, unknown>>(
    sql: string,
    parametros?: readonly unknown[],
  ): Promise<Fila[]>;
};

export type OpcionesDeAcceso = {
  readonly url: string;
  /** Fecha civil AAAA-MM-DD que ve `app.hoy()`. Sin ella, la fecha real. */
  readonly fechaReferencia?: string | undefined;
  readonly maximoDeConexiones?: number;
};

let pool: Pool | undefined;
let fechaReferencia: string | undefined;

/** Solo para detectar anidamiento. NUNCA para propagar el contexto. */
const dentroDeTransaccion = new AsyncLocalStorage<true>();

export function iniciarAcceso(opciones: OpcionesDeAcceso): void {
  if (pool !== undefined) throw new Error("el acceso a datos ya estaba iniciado");
  fechaReferencia = opciones.fechaReferencia;
  pool = new Pool({
    connectionString: opciones.url,
    max: opciones.maximoDeConexiones ?? 10,
    // Se ve en pg_stat_activity: sirve para saber quién tiene una consulta
    // colgada cuando hay tres procesos hablando con la misma base.
    application_name: "alivia-api",
  });
}

export async function cerrarAcceso(): Promise<void> {
  const actual = pool;
  pool = undefined;
  fechaReferencia = undefined;
  if (actual !== undefined) await actual.end();
}

function obtenerPool(): Pool {
  if (pool === undefined) {
    throw new Error(
      "el acceso a datos no está iniciado: hay que llamar a iniciarAcceso() al arrancar",
    );
  }
  return pool;
}

function construirTx(cliente: PoolClient, sigueViva: () => boolean): Tx {
  const tx = {
    async consultar<Fila extends Record<string, unknown>>(
      sql: string,
      parametros: readonly unknown[] = [],
    ): Promise<Fila[]> {
      // Una referencia a `tx` que sobreviva a la transacción es un error, y sin
      // esto sería un error silencioso: la consulta correría en la siguiente
      // transacción que tomara ese mismo cliente del pool, con OTRO contexto.
      if (!sigueViva()) {
        throw new Error(
          "esta transacción ya se cerró: el Tx no se puede guardar ni usar después " +
            "de que conUsuario() haya devuelto",
        );
      }
      const resultado = await cliente.query(sql, [...parametros]);
      return resultado.rows as Fila[];
    },
  };
  return tx as unknown as Tx;
}

async function enTransaccion<T>(
  usuarioId: string | null,
  trabajo: (tx: Tx) => Promise<T>,
): Promise<T> {
  // Anidar abriría una SEGUNDA transacción, en otra conexión, y lo que pasara
  // en una no sería atómico con la otra. La tarea 11 exige justo lo contrario:
  // la cuenta y la constancia de autorización en la misma transacción.
  if (dentroDeTransaccion.getStore() === true) {
    throw new Error(
      "ya hay una transacción abierta en este flujo. Pasar el `tx` que se tiene " +
        "en lugar de abrir otra: dos transacciones no son atómicas entre sí",
    );
  }

  const cliente = await obtenerPool().connect();
  let viva = true;
  const tx = construirTx(cliente, () => viva);

  try {
    await cliente.query("BEGIN");

    // `set_config(..., true)` es LOCAL a la transacción: se deshace al cerrar,
    // así que la conexión vuelve limpia al pool. Las dos variables, no solo el
    // usuario: `app.hoy()` lee la segunda, y sin ella no se puede demostrar una
    // ventana de 30 días sin mover el reloj de la máquina.
    const filas = await cliente.query<{ usuario: string; fecha: string }>(
      "SELECT set_config($1, $2, true) AS usuario, set_config($3, $4, true) AS fecha",
      ["alivia.usuario_id", usuarioId ?? "", "alivia.fecha_referencia", fechaReferencia ?? ""],
    );

    const fijado = filas.rows[0]?.usuario;
    if (fijado !== (usuarioId ?? "")) {
      throw new Error(
        `el contexto no quedó fijado: se pidió «${usuarioId ?? ""}» y la base devolvió ` +
          `«${fijado ?? "nada"}». Sin contexto, las políticas no devuelven filas`,
      );
    }

    const resultado = await dentroDeTransaccion.run(true, () => trabajo(tx));
    await cliente.query("COMMIT");
    return resultado;
  } catch (error) {
    // Si el ROLLBACK falla --conexión caída-- lo que importa es el error
    // original, no el del rollback.
    await cliente.query("ROLLBACK").catch(() => undefined);
    throw error;
  } finally {
    viva = false;
    cliente.release();
  }
}

/**
 * Abre una transacción, fija el contexto del usuario y la cierra. Es la única
 * puerta a los datos de usuario.
 *
 * Al salir hace COMMIT; si `trabajo` lanza, ROLLBACK y se propaga el error.
 */
export function conUsuario<T>(usuarioId: string, trabajo: (tx: Tx) => Promise<T>): Promise<T> {
  if (!UUID.test(usuarioId)) {
    // Sin esto, un identificador mal formado revienta dentro de las políticas
    // con «invalid input syntax for type uuid», que es un 500 y no dice nada.
    return Promise.reject(
      new Error(`«${usuarioId}» no es un identificador de usuario: se esperaba un uuid`),
    );
  }
  return enTransaccion(usuarioId, trabajo);
}

/**
 * Transacción SIN contexto de usuario. Existe para exactamente dos cosas, y las
 * dos son funciones `SECURITY DEFINER` del esquema que por definición corren
 * antes de que haya un usuario en sesión:
 *
 *   - `app.registrar_usuario()`  — la cuenta todavía no existe
 *   - `app.credenciales_por_correo()` — todavía no se sabe quién es
 *
 * Para cualquier otra cosa es un error: sin contexto, las políticas comparan
 * contra NULL y la consulta devuelve cero filas sin avisar. Se llama así para
 * que dé reparo escribirlo.
 */
export function sinContextoDeUsuario<T>(trabajo: (tx: Tx) => Promise<T>): Promise<T> {
  return enTransaccion(null, trabajo);
}

/** Para el arranque y para `GET /salud` (tarea 7). No abre transacción. */
export async function comprobarConexion(): Promise<{ version: string; hoy: string }> {
  const cliente = await obtenerPool().connect();
  try {
    const filas = await cliente.query<{ version: string; hoy: string }>(
      "SELECT current_setting($1) AS version, app.hoy()::text AS hoy",
      ["server_version"],
    );
    const fila = filas.rows[0];
    if (fila === undefined) throw new Error("la base de datos no devolvió nada");
    return fila;
  } finally {
    cliente.release();
  }
}

export { OID_FECHA };
