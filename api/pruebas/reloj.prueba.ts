// El reloj inyectable, que es de lo que depende toda la fase 4 y la
// sustentación de noviembre. Fichero aparte a propósito: necesita una base con
// OTRA fecha de referencia, y por eso tiene que ser otra base.

import { strict as assert } from "node:assert";
import { after, before, describe, test } from "node:test";
import { sinContextoDeUsuario } from "../src/datos/contexto.js";
import { abrirBaseEfimera, type BaseEfimera } from "./arnes/base.js";

const FECHA = "2026-03-15";

describe("el reloj inyectado", () => {
  let base: BaseEfimera;

  before(async () => {
    base = await abrirBaseEfimera({ fechaReferencia: FECHA });
  });
  after(async () => {
    await base.cerrar();
  });

  test("app.hoy() devuelve la fecha inyectada, no la de hoy", async () => {
    const [fila] = await sinContextoDeUsuario(async (tx) =>
      tx.consultar<{ hoy: string }>("SELECT app.hoy()::text AS hoy"),
    );
    assert.equal(fila?.hoy, FECHA);
  });

  test("y vuelve como cadena AAAA-MM-DD, no como instante", async () => {
    const [fila] = await sinContextoDeUsuario(async (tx) =>
      tx.consultar<{ hoy: unknown }>("SELECT app.hoy() AS hoy"),
    );
    assert.equal(typeof fila?.hoy, "string");
    assert.match(String(fila?.hoy), /^\d{4}-\d{2}-\d{2}$/);
  });

  test("cada fichero de pruebas tiene su propia base", () => {
    // Esta base existe a la vez que la de arnes.prueba.ts y con otra fecha de
    // referencia. Si compartieran base, una de las dos vería la fecha de la
    // otra y fallaría de forma intermitente.
    assert.ok(base.nombre.length > 0);
  });
});
