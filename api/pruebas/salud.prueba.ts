// GET /salud y el contrato HTTP, contra el servidor Express de verdad.
//
// La aplicación se levanta en un puerto efímero (`listen(0)`) en lugar de usar
// el del .env: así no choca con el contenedor ni con `npm run dev`, y cada
// fichero de pruebas es independiente.

import { strict as assert } from "node:assert";
import type { Server } from "node:http";
import { after, before, describe, test } from "node:test";
import { codigoDeSalud } from "../src/http/salud.js";
import { crearServidor } from "../src/http/servidor.js";
import { abrirBaseEfimera, type BaseEfimera } from "./arnes/base.js";

const SMTP = {
  host: process.env["SMTP_HOST"] ?? "localhost",
  puerto: Number(process.env["SMTP_PUERTO"] ?? 1025),
};

/** Lo mínimo que el servidor necesita. El resto no lo usa ninguna ruta todavía. */
function configuracionDePrueba(fechaReferencia?: string) {
  return {
    puerto: 0,
    urlBaseDeDatos: "postgres://alivia_app@no-se-usa/aqui",
    jwtSecreto: "z".repeat(40),
    jwtSecretoEfimero: false,
    zonaHoraria: "America/Bogota",
    diasAnticipacionPorDefecto: 15,
    smtp: SMTP,
    fechaReferencia,
  };
}

async function levantar(fechaReferencia?: string) {
  const app = crearServidor(configuracionDePrueba(fechaReferencia));
  const servidor: Server = await new Promise((resolver) => {
    const s = app.listen(0, () => resolver(s));
  });
  const direccion = servidor.address();
  if (direccion === null || typeof direccion === "string") throw new Error("sin puerto");
  return {
    url: `http://127.0.0.1:${direccion.port}`,
    cerrar: () => new Promise<void>((r) => servidor.close(() => r())),
  };
}

describe("GET /salud y el contrato HTTP", () => {
  let base: BaseEfimera;
  let servidor: Awaited<ReturnType<typeof levantar>>;

  before(async () => {
    base = await abrirBaseEfimera();
    servidor = await levantar();
  });
  after(async () => {
    await servidor.cerrar();
    await base.cerrar();
  });

  test("reporta la base de datos y el correo, y responde 200", async () => {
    const r = await fetch(`${servidor.url}/salud`);
    assert.equal(r.status, 200);

    const cuerpo = (await r.json()) as {
      estado: string;
      hoy?: string;
      comprueba: { que: string; estado: string }[];
    };
    assert.equal(cuerpo.estado, "sano");
    assert.deepEqual(
      cuerpo.comprueba.map((c) => `${c.que}=${c.estado}`).sort(),
      ["base de datos=sano", "correo=sano"],
      "el criterio de la tarea 7 es que reporte las dos cosas",
    );
    assert.match(String(cuerpo.hoy), /^\d{4}-\d{2}-\d{2}$/);
  });

  test("comprueba que hay un servidor SMTP, no solo un puerto abierto", async () => {
    const r = await fetch(`${servidor.url}/salud`);
    const cuerpo = (await r.json()) as { comprueba: { que: string; detalle?: string }[] };
    const correo = cuerpo.comprueba.find((c) => c.que === "correo");
    // Lee el saludo y exige un 220. Un puerto abierto ya nos engañó una vez.
    assert.ok(
      correo?.detalle === "Mailpit" || correo?.detalle === "SMTP",
      `el detalle del correo fue «${correo?.detalle}»: no se leyó el saludo`,
    );
  });

  test("no filtra anfitriones, puertos ni cadenas de conexión", async () => {
    const crudo = await (await fetch(`${servidor.url}/salud`)).text();
    for (const aguja of [
      "postgres://",
      "desarrollo",
      "alivia_app",
      String(SMTP.puerto),
      SMTP.host,
    ]) {
      assert.ok(
        !crudo.includes(aguja),
        `/salud filtró «${aguja}». Es un endpoint sin autenticar: no cuenta la topología`,
      );
    }
  });

  test("una ruta que no existe devuelve 404 con el cuerpo del contrato", async () => {
    const r = await fetch(`${servidor.url}/no-existe`);
    assert.equal(r.status, 404);
    assert.ok(r.headers.get("x-alivia-peticion"), "falta el identificador para cruzar el registro");

    const cuerpo = (await r.json()) as { error: Record<string, string> };
    assert.deepEqual(Object.keys(cuerpo), ["error"]);
    assert.deepEqual(Object.keys(cuerpo.error).sort(), ["codigo", "identificador", "mensaje"]);
    assert.equal(cuerpo.error.codigo, "RUTA_NO_ENCONTRADA");
  });

  test("el identificador de la respuesta es el del cuerpo", async () => {
    const r = await fetch(`${servidor.url}/no-existe`);
    const cuerpo = (await r.json()) as { error: { identificador: string } };
    assert.equal(cuerpo.error.identificador, r.headers.get("x-alivia-peticion"));
  });

  test("no anuncia el marco ni su versión", async () => {
    const r = await fetch(`${servidor.url}/salud`);
    assert.equal(r.headers.get("x-powered-by"), null);
  });

  test("con el reloj inyectado, /salud lo declara", async () => {
    // Que se vea es importante: una demostración con el reloj movido y sin
    // avisar es una demostración que engaña a quien la mira.
    const otro = await levantar("2026-03-15");
    try {
      const cuerpo = (await (await fetch(`${otro.url}/salud`)).json()) as {
        relojInyectado: boolean;
      };
      assert.equal(cuerpo.relojInyectado, true);
    } finally {
      await otro.cerrar();
    }
  });
});

describe("el código HTTP de /salud", () => {
  // La decisión está extraída a codigoDeSalud() para poder probarla sin tumbar
  // la base de datos. El comportamiento real se verificó parando los
  // contenedores: con el correo caído responde 200 y «degradado»; con la base
  // caída, 503. Y el servidor sobrevive a las dos cosas.

  test("solo un fallo ESENCIAL devuelve 503", () => {
    const base = { estado: "degradado" as const, relojInyectado: false };

    assert.equal(
      codigoDeSalud({
        ...base,
        falloEsencial: false,
        comprueba: [{ que: "correo", esencial: false, estado: "caido", milisegundos: 1 }],
      }),
      200,
      "con el correo caído el servidor atiende todo: enviar es del proceso de avisos",
    );

    assert.equal(
      codigoDeSalud({
        ...base,
        falloEsencial: true,
        comprueba: [{ que: "base de datos", esencial: true, estado: "caido", milisegundos: 1 }],
      }),
      503,
    );

    assert.equal(
      codigoDeSalud({
        estado: "sano",
        relojInyectado: false,
        falloEsencial: false,
        comprueba: [],
      }),
      200,
    );
  });
});
