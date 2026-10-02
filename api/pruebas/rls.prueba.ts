// Las trece comprobaciones de db/pruebas/rls.sql, portadas a la capa de datos.
//
// No son una copia por gusto. Las de SQL demuestran que las POLÍTICAS aíslan;
// estas demuestran que `conUsuario()` las respeta, que es otra cosa. Entre una
// y otra está todo lo que puede ir mal en la aplicación: conectar con el rol
// equivocado, perder el contexto, o abrir la transacción donde no toca.
//
// Criterio de la tarea 5: `npm test` falla si alguien conecta con el rol
// equivocado o pierde el contexto de transacción. Las dos últimas pruebas de
// este fichero son exactamente eso.
//
// Los nombres siguen los de rls.sql para poder cruzarlas.

import { strict as assert } from "node:assert";
import { after, before, describe, test } from "node:test";
import {
  conUsuario,
  conUsuarioEnFecha,
  sinContextoDeUsuario,
  type Tx,
} from "../src/datos/contexto.js";
import { abrirBaseEfimera, type BaseEfimera } from "./arnes/base.js";

/** Código de PostgreSQL para «insufficient_privilege»: lo que lanza RLS. */
const SIN_PRIVILEGIO = "42501";

const INSERTAR_OBLIGACION = `
  INSERT INTO obligacion_usuario
    (usuario_id, modulo_codigo, origen, nombre, tipo_exigibilidad, fecha_base)
  VALUES ($1, $2, 'libre', $3, 'recomendada', DATE '2026-01-01')`;

async function unaFila<F extends Record<string, unknown>>(tx: Tx, sql: string, p?: unknown[]) {
  const filas = await tx.consultar<F>(sql, p);
  const fila = filas[0];
  if (fila === undefined) throw new Error(`sin filas: ${sql}`);
  return fila;
}

/**
 * El identificador por correo, por `app.credenciales_por_correo()`, que es
 * SECURITY DEFINER y es el camino que usará el ingreso de la tarea 12. A
 * propósito en lugar de leerlo como propietario: así la prueba usa la misma
 * puerta que usará la aplicación.
 */
async function idDe(correo: string): Promise<string> {
  const { id } = await sinContextoDeUsuario(async (tx) =>
    unaFila<{ id: string }>(tx, "SELECT id::text AS id FROM app.credenciales_por_correo($1)", [
      correo,
    ]),
  );
  return id;
}

async function cuantas(usuarioId: string, sql: string, p: unknown[] = [], reloj?: string) {
  const leer = async (tx: Tx) => unaFila<{ n: string }>(tx, sql, p);
  const { n } =
    reloj === undefined
      ? await conUsuario(usuarioId, leer)
      : await conUsuarioEnFecha(usuarioId, reloj, leer);
  return Number(n);
}

describe("aislamiento entre usuarios a través de conUsuario()", () => {
  let base: BaseEfimera;
  let ana: string;
  let beto: string;

  before(async () => {
    base = await abrirBaseEfimera();
    ana = await idDe("ana@prueba.local");
    beto = await idDe("beto@prueba.local");
  });
  after(async () => {
    await base.cerrar();
  });

  // --- 1. Sin contexto de usuario no se ve nada -----------------------------

  test("sin contexto no hay usuarios visibles", async () => {
    const { n } = await sinContextoDeUsuario(async (tx) =>
      unaFila<{ n: string }>(tx, "SELECT count(*)::text AS n FROM usuario"),
    );
    assert.equal(n, "0", "sin contexto se ven usuarios: las políticas no están filtrando");
  });

  test("sin contexto no hay obligaciones visibles", async () => {
    const { n } = await sinContextoDeUsuario(async (tx) =>
      unaFila<{ n: string }>(tx, "SELECT count(*)::text AS n FROM obligacion_usuario"),
    );
    assert.equal(n, "0");
  });

  // --- 2. Con contexto se ve solo lo propio ---------------------------------

  test("ana ve exactamente una cuenta: la suya", async () => {
    assert.equal(await cuantas(ana, "SELECT count(*)::text AS n FROM usuario"), 1);
  });

  test("ana ve obligaciones, y todas son suyas", async () => {
    const filas = await conUsuario(ana, async (tx) =>
      tx.consultar<{ nombre: string }>("SELECT nombre FROM obligacion_usuario"),
    );
    assert.ok(filas.length > 0, "ana no ve ni sus propias obligaciones");
    assert.ok(
      filas.every((f) => f.nombre.startsWith("ANA")),
      `ana ve obligaciones ajenas: ${filas.map((f) => f.nombre).join(", ")}`,
    );
  });

  // --- 3. Cambiar de usuario cambia lo que se ve ----------------------------

  test("beto ve obligaciones, y todas son suyas", async () => {
    const filas = await conUsuario(beto, async (tx) =>
      tx.consultar<{ nombre: string }>("SELECT nombre FROM obligacion_usuario"),
    );
    assert.ok(filas.length > 0);
    assert.ok(filas.every((f) => f.nombre.startsWith("BETO")));
  });

  // --- 4. No se puede escribir en nombre de otro ----------------------------

  test("beto no puede escribir a nombre de ana", async () => {
    await assert.rejects(
      conUsuario(beto, async (tx) => {
        await tx.consultar(INSERTAR_OBLIGACION, [ana, "hogar", "ROBADA"]);
      }),
      (error: unknown) => (error as { code?: string }).code === SIN_PRIVILEGIO,
      "beto consiguió escribir una obligación a nombre de ana",
    );
    // Y la transacción se deshizo: nada quedó.
    assert.equal(
      await cuantas(
        ana,
        "SELECT count(*)::text AS n FROM obligacion_usuario WHERE nombre = 'ROBADA'",
      ),
      0,
    );
  });

  // --- 5. Módulo de pago sin suscripción vigente ----------------------------

  test("módulo de pago bloqueado sin suscripción vigente", async () => {
    await assert.rejects(
      conUsuario(beto, async (tx) => {
        await tx.consultar(INSERTAR_OBLIGACION, [beto, "salud", "SIN PAGAR"]);
      }),
      (error: unknown) => (error as { code?: string }).code === SIN_PRIVILEGIO,
      "beto creó una obligación de un módulo de pago sin suscripción. Regla 5",
    );
  });

  // --- 6 y 7. El reloj inyectable mueve la vigencia -------------------------
  // Ana tiene suscripción a salud del 2026-01-01 al 2027-01-01. Las tres
  // transacciones de esta prueba son la propiedad entera: dentro de vigencia se
  // ve, fuera no, y al volver dentro reaparece. Lo que expira es el ACCESO, no
  // el dato: eso es la regla 6.

  test("dentro de vigencia hay acceso a salud y se ven sus obligaciones", async () => {
    const { acceso } = await conUsuarioEnFecha(ana, "2026-06-15", async (tx) =>
      unaFila<{ acceso: boolean }>(
        tx,
        "SELECT app.tiene_acceso(app.usuario_actual(), 'salud') AS acceso",
      ),
    );
    assert.equal(acceso, true);

    const vistas = await cuantas(
      ana,
      "SELECT count(*)::text AS n FROM obligacion_usuario WHERE modulo_codigo = 'salud'",
      [],
      "2026-06-15",
    );
    assert.ok(vistas > 0, "dentro de vigencia no ve sus obligaciones de salud");
  });

  test("fuera de vigencia no hay acceso y ana deja de ver salud", async () => {
    const { acceso } = await conUsuarioEnFecha(ana, "2027-06-15", async (tx) =>
      unaFila<{ acceso: boolean }>(
        tx,
        "SELECT app.tiene_acceso(app.usuario_actual(), 'salud') AS acceso",
      ),
    );
    assert.equal(acceso, false, "una suscripción expirada sigue dando acceso");

    assert.equal(
      await cuantas(
        ana,
        "SELECT count(*)::text AS n FROM obligacion_usuario WHERE modulo_codigo = 'salud'",
        [],
        "2027-06-15",
      ),
      0,
    );
  });

  test("renovada, las obligaciones de salud reaparecen intactas", async () => {
    // El alcance exige que expirar SUSPENDA el acceso, no que borre el dato.
    // Que vuelvan a verse con el reloj dentro de vigencia es la prueba de que
    // nunca se fueron.
    assert.ok(
      (await cuantas(
        ana,
        "SELECT count(*)::text AS n FROM obligacion_usuario WHERE modulo_codigo = 'salud'",
        [],
        "2026-06-15",
      )) > 0,
      "los datos se perdieron al expirar",
    );
  });

  // --- 8. El rol de la aplicación no puede saltarse las políticas -----------

  test("el rol con el que corre no tiene BYPASSRLS ni es superusuario", async () => {
    const fila = await sinContextoDeUsuario(async (tx) =>
      unaFila<{ rol: string; salta: boolean; super: boolean }>(
        tx,
        `SELECT current_user AS rol, rolbypassrls AS salta, rolsuper AS "super"
         FROM pg_roles WHERE rolname = current_user`,
      ),
    );
    // Esta es la mitad del criterio de la tarea 5: si alguien cambia la URL de
    // la aplicación al rol propietario, TODAS las pruebas de arriba pasarían
    // --el propietario ignora las políticas-- y esta es la única que lo delata.
    assert.equal(fila.rol, "alivia_app", `la aplicación está conectada como «${fila.rol}»`);
    assert.equal(fila.salta, false);
    assert.equal(fila.super, false);
  });

  // --- Y la otra mitad: perder el contexto de transacción -------------------

  test("un Tx usado fuera de su transacción no consulta: lanza", async () => {
    // Es la forma que toma en la aplicación el defecto que originó la regla 1.
    // En SQL se manifestaba como cero filas sin error; aquí es imposible,
    // porque el Tx se invalida al cerrar.
    let guardado: Tx | undefined;
    await conUsuario(ana, async (tx) => {
      guardado = tx;
    });
    await assert.rejects(
      async () => guardado?.consultar("SELECT count(*) FROM obligacion_usuario"),
      /ya se cerró/,
      "un Tx guardado siguió consultando: correría con el contexto de otro usuario",
    );
  });
});
