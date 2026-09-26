#!/usr/bin/env node
// Valida la configuración y sale, sin arrancar nada.
//
//     npm run configuracion                        # el perfil del servidor
//     npm run configuracion -- avisos              # el del proceso de avisos
//     npm run configuracion -- api /otra/ruta/.env # validando otro fichero
//
// Sirve para dos cosas: contestar «¿está bien mi .env?» sin levantar la pila, y
// que scripts/verificar-configuracion.py pueda comprobar el comportamiento sin
// dejar un servidor escuchando.

import { cargarConfiguracionAvisos } from "./avisos.js";
import { ErrorDeConfiguracion } from "./entorno.js";
import { avisosDeArranque, cargarConfiguracionServidor, resumir } from "./servidor.js";

const perfil = process.argv[2] ?? "api";
const rutaEnv = process.argv[3] ?? ".env";

if (perfil !== "api" && perfil !== "avisos") {
  console.error(`Perfil desconocido: «${perfil}». Los que hay son «api» y «avisos».`);
  process.exit(2);
}

try {
  if (perfil === "avisos") {
    const c = cargarConfiguracionAvisos(process.env, rutaEnv);
    const url = new URL(c.urlBaseDeDatos);
    console.log(`[alivia/avisos] configuración válida`);
    console.log(`  base de datos     ${url.username}@${url.host}${url.pathname}`);
    console.log(`  correo            ${c.smtp.host}:${c.smtp.puerto} como ${c.smtp.remitente}`);
    console.log(`  zona horaria      ${c.zonaHoraria}`);
    if (c.fechaReferencia !== undefined) {
      console.log(`  RELOJ INYECTADO   hoy es ${c.fechaReferencia}, no la fecha real`);
    }
  } else {
    const c = cargarConfiguracionServidor(process.env, rutaEnv);
    console.log(`[alivia/api] configuración válida`);
    for (const linea of resumir(c)) console.log(`  ${linea}`);
    for (const aviso of avisosDeArranque(c)) console.warn(`  AVISO: ${aviso}`);
  }
  process.exit(0);
} catch (error) {
  if (error instanceof ErrorDeConfiguracion) {
    console.error(error.informe());
    process.exit(1);
  }
  throw error;
}
