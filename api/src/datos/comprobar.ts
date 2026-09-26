#!/usr/bin/env node
// Ejercita el contrato de la capa de datos contra la base de datos de verdad.
//
//     npm run datos
//
// Imprime una línea JSON por caso, {caso, ok, detalle}, y sale con 1 si alguno
// falló. Lo consume scripts/verificar-datos.py, que es quien decide.
//
// Lo que se comprueba aquí es el MECANISMO: que el contexto llegue, que se
// deshaga al cerrar, que anidar falle, que un Tx guardado no sirva después, y
// que una fecha civil vuelva como cadena. Las trece comprobaciones de
// aislamiento de db/pruebas/rls.sql se portan en la tarea 5.

import { cargarConfiguracionServidor } from "../configuracion/servidor.js";
import {
  cerrarAcceso,
  comprobarConexion,
  conUsuario,
  iniciarAcceso,
  sinContextoDeUsuario,
  type Tx,
} from "./contexto.js";

const resultados: { caso: string; ok: boolean; detalle: string }[] = [];

function anotar(caso: string, ok: boolean, detalle: string): void {
  resultados.push({ caso, ok, detalle });
}

async function comprobar(caso: string, trabajo: () => Promise<string>): Promise<void> {
  try {
    anotar(caso, true, await trabajo());
  } catch (error) {
    anotar(caso, false, error instanceof Error ? error.message : String(error));
  }
}

/** Debe lanzar. Si no lanza, el caso falla. */
async function debeLanzar(
  caso: string,
  trabajo: () => Promise<unknown>,
  aguja: string,
): Promise<void> {
  try {
    await trabajo();
    anotar(caso, false, "no lanzó, y tenía que lanzar");
  } catch (error) {
    const mensaje = error instanceof Error ? error.message : String(error);
    anotar(caso, mensaje.includes(aguja), `lanzó: ${mensaje}`);
  }
}

async function unaFila<F extends Record<string, unknown>>(tx: Tx, sql: string, p?: unknown[]) {
  const filas = await tx.consultar<F>(sql, p);
  const fila = filas[0];
  if (fila === undefined) throw new Error(`la consulta no devolvió filas: ${sql}`);
  return fila;
}

const configuracion = cargarConfiguracionServidor();
iniciarAcceso({
  url: configuracion.urlBaseDeDatos,
  fechaReferencia: configuracion.fechaReferencia,
});

const ANA = process.env["ID_ANA"] ?? "";
const BETO = process.env["ID_BETO"] ?? "";

await comprobar("la conexión responde y app.hoy() existe", async () => {
  const { version, hoy } = await comprobarConexion();
  return `postgres ${version}, hoy ${hoy}`;
});

await comprobar("dentro de conUsuario, app.usuario_actual() es ese usuario", async () =>
  conUsuario(ANA, async (tx) => {
    const { actual } = await unaFila<{ actual: string | null }>(
      tx,
      "SELECT app.usuario_actual()::text AS actual",
    );
    if (actual !== ANA) throw new Error(`usuario_actual() devolvió ${actual}, no ${ANA}`);
    return `usuario_actual() = ${actual}`;
  }),
);

await comprobar("sin contexto, app.usuario_actual() es NULL", async () =>
  sinContextoDeUsuario(async (tx) => {
    const { actual } = await unaFila<{ actual: string | null }>(
      tx,
      "SELECT app.usuario_actual()::text AS actual",
    );
    if (actual !== null) throw new Error(`usuario_actual() devolvió ${actual}, y debía ser NULL`);
    return "NULL, como debe ser";
  }),
);

await comprobar("con contexto de Ana no se ven las obligaciones de Beto", async () =>
  conUsuario(ANA, async (tx) => {
    const { propias } = await unaFila<{ propias: string }>(
      tx,
      "SELECT count(*)::text AS propias FROM obligacion_usuario",
    );
    const { ajenas } = await unaFila<{ ajenas: string }>(
      tx,
      "SELECT count(*)::text AS ajenas FROM obligacion_usuario WHERE usuario_id = $1",
      [BETO],
    );
    if (Number(propias) === 0) throw new Error("Ana no ve ni sus propias obligaciones");
    if (Number(ajenas) !== 0) throw new Error(`Ana ve ${ajenas} obligaciones de Beto`);
    return `${propias} propias, 0 de Beto`;
  }),
);

await comprobar("el contexto se deshace al cerrar la transacción", async () => {
  await conUsuario(ANA, async (tx) => {
    await tx.consultar("SELECT 1");
  });
  // La conexión vuelve al pool. Si set_config no hubiera sido local a la
  // transacción, la siguiente la heredaría y esto devolvería el id de Ana.
  return sinContextoDeUsuario(async (tx) => {
    const { actual } = await unaFila<{ actual: string | null }>(
      tx,
      "SELECT app.usuario_actual()::text AS actual",
    );
    if (actual !== null) throw new Error(`la conexión volvió al pool con el contexto de ${actual}`);
    return "la conexión vuelve limpia al pool";
  });
});

await comprobar("una fecha civil vuelve como cadena AAAA-MM-DD, no como Date", async () =>
  conUsuario(ANA, async (tx) => {
    const fila = await unaFila<{ f: unknown }>(
      tx,
      "SELECT fecha_base AS f FROM obligacion_usuario LIMIT 1",
    );
    const valor = fila.f;
    if (typeof valor !== "string") {
      throw new Error(`fecha_base volvió como ${typeof valor} (${String(valor)}), no como cadena`);
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(valor)) throw new Error(`«${valor}» no es AAAA-MM-DD`);
    return valor;
  }),
);

await comprobar("un error dentro deshace la transacción", async () => {
  const nombre = `PRUEBA ROLLBACK ${Date.now()}`;
  try {
    await conUsuario(ANA, async (tx) => {
      await tx.consultar(
        `INSERT INTO obligacion_usuario
           (usuario_id, modulo_codigo, origen, nombre, tipo_exigibilidad, fecha_base)
         VALUES ($1, 'vehiculo', 'libre', $2, 'recomendada', DATE '2026-06-01')`,
        [ANA, nombre],
      );
      throw new Error("fallo a propósito");
    });
  } catch {
    // Esperado.
  }
  return conUsuario(ANA, async (tx) => {
    const { cuantas } = await unaFila<{ cuantas: string }>(
      tx,
      "SELECT count(*)::text AS cuantas FROM obligacion_usuario WHERE nombre = $1",
      [nombre],
    );
    if (cuantas !== "0") throw new Error(`quedaron ${cuantas} filas: no hubo ROLLBACK`);
    return "la fila insertada no quedó";
  });
});

await debeLanzar(
  "anidar conUsuario falla",
  () => conUsuario(ANA, async () => conUsuario(ANA, async () => 1)),
  "ya hay una transacción abierta",
);

await debeLanzar(
  "un Tx guardado no sirve después",
  async () => {
    let guardado: Tx | undefined;
    await conUsuario(ANA, async (tx) => {
      guardado = tx;
    });
    return guardado?.consultar("SELECT 1");
  },
  "ya se cerró",
);

await debeLanzar(
  "un identificador que no es uuid falla antes de consultar",
  () => conUsuario("' OR true --", async () => 1),
  "no es un identificador de usuario",
);

await cerrarAcceso();

for (const r of resultados) console.log(JSON.stringify(r));
process.exit(resultados.some((r) => !r.ok) ? 1 : 0);
