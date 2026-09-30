#!/usr/bin/env node
// Esto es lo que corre `npm test`.
//
//   1. Crea la base PLANTILLA y le aplica migraciones y semillas desde cero,
//      con el mismo db/aplicar.sh que usa todo el mundo. Una sola
//      implementación: si las migraciones se aplican mal aquí, se aplican mal
//      en todas partes.
//   2. Lanza el ejecutor de pruebas de Node. Cada fichero se copia su propia
//      base de la plantilla, en su propio proceso.
//   3. Borra la plantilla y cualquier base efímera que haya quedado suelta,
//      pase lo que pase.
//
// La base de trabajo no se toca en ningún momento: el arnés no se conecta a
// ella. «Deja la base como la encontró» por construcción, no por limpieza.

import { spawn } from "node:child_process";
import { enMantenimiento, exigirQueSeaAlivia } from "./mantenimiento.js";
import {
  nombreDeLaBaseDeTrabajo,
  PLANTILLA,
  PREFIJO_EFIMERA,
  urlDeMantenimiento,
  urlDePropietarioSobre,
} from "./nombres.js";

const RAIZ = new URL("../../../", import.meta.url).pathname;
const PATRON = "api/pruebas/**/*.prueba.ts";

function correr(
  orden: string,
  argumentos: string[],
  entorno: NodeJS.ProcessEnv = {},
): Promise<number> {
  return new Promise((resolver) => {
    const hijo = spawn(orden, argumentos, {
      cwd: RAIZ,
      stdio: "inherit",
      env: { ...process.env, ...entorno },
    });
    hijo.on("close", (codigo) => resolver(codigo ?? 1));
  });
}

async function limpiar(): Promise<string[]> {
  return enMantenimiento(async (cliente) => {
    const { rows } = await cliente.query<{ datname: string }>(
      "SELECT datname FROM pg_database WHERE datname = $1 OR datname LIKE $2",
      [PLANTILLA, `${PREFIJO_EFIMERA}%`],
    );
    for (const { datname } of rows) {
      await cliente.query(`DROP DATABASE IF EXISTS ${datname} WITH (FORCE)`);
    }
    return rows.map((f) => f.datname);
  });
}

const trabajo = nombreDeLaBaseDeTrabajo();
if (trabajo === PLANTILLA || trabajo.startsWith(PREFIJO_EFIMERA)) {
  console.error(
    `[arnés] la base de trabajo se llama «${trabajo}», que choca con los nombres que usa ` +
      "el arnés. Renombrarla en DATABASE_URL_MIGRACIONES.",
  );
  process.exit(2);
}

console.log(`[arnés] base de trabajo: ${trabajo} (no se toca)`);

// Un puerto publicado no es una identidad: antes de crear nada, comprobar que
// quien contesta es la base de Alivia y no la de otro proyecto de la maquina.
await exigirQueSeaAlivia(trabajo);

const sobras = await limpiar();
if (sobras.length > 0)
  console.log(`[arnés] sobras de una ejecución anterior: ${sobras.join(", ")}`);

console.log(`[arnés] creando la plantilla ${PLANTILLA} y aplicando el esquema desde cero`);
await enMantenimiento(async (cliente) => {
  await cliente.query(`CREATE DATABASE ${PLANTILLA}`);
});

let codigo = 1;
try {
  const aplicado = await correr("./db/aplicar.sh", ["--semillas"], {
    DATABASE_URL_MIGRACIONES: urlDePropietarioSobre(PLANTILLA),
  });
  if (aplicado !== 0) {
    console.error("[arnés] no se pudo aplicar el esquema a la plantilla");
    codigo = aplicado;
  } else {
    codigo = await correr("npx", ["tsx", "--test", PATRON], {
      URL_PLANTILLA: PLANTILLA,
    });
  }
} finally {
  const borradas = await limpiar();
  console.log(`[arnés] borradas ${borradas.length} base(s) de prueba`);

  // Si algo quedó, es un defecto del arnés: la próxima ejecución arrancaría
  // sobre restos y «desde cero» dejaría de ser verdad.
  const quedan = await limpiar();
  if (quedan.length > 0) {
    console.error(`[arnés] quedaron bases sin borrar: ${quedan.join(", ")}`);
    codigo = codigo === 0 ? 1 : codigo;
  }
}

process.exit(codigo);
