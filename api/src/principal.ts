// Punto de entrada del servidor.
//
// Tarea 1 del backlog: el esqueleto. Deliberadamente no hace nada más, y cada
// cosa que falta tiene su tarea y su sitio:
//
//   configuracion/  leer y validar el entorno al arrancar        tarea 2
//   datos/          el pool y conUsuario(): el ÚNICO sitio que
//                   conoce la conexión (decisión 1)              tarea 3
//   http/           Express, manejo de errores y /salud de
//                   verdad, con el estado de la base y el correo tareas 6 y 7
//   dominio/        cálculo de vencimientos, avisos              tarea 19 y siguientes
//
// Este listener existe por una razón concreta, no de adorno: el servicio del
// compose necesita un healthcheck, y sin algo que responda no hay forma de que
// `up --wait` sepa que el proceso arrancó. La tarea 7 lo reemplaza por Express
// y hace que /salud informe de verdad.

import { createServer } from "node:http";
import { ErrorDeConfiguracion } from "./configuracion/entorno.js";
import {
  avisosDeArranque,
  cargarConfiguracionServidor,
  resumir,
} from "./configuracion/servidor.js";

// La configuracion se valida ANTES de abrir el puerto: si falta una variable
// obligatoria el proceso muere aqui, diciendo cual, en lugar de arrancar y
// fallar mas tarde en otro sitio. Tarea 2.
let configuracion: ReturnType<typeof cargarConfiguracionServidor>;
try {
  configuracion = cargarConfiguracionServidor();
} catch (error) {
  if (error instanceof ErrorDeConfiguracion) {
    console.error(error.informe());
    process.exit(1);
  }
  throw error;
}

for (const linea of resumir(configuracion)) console.log(`[alivia/api] ${linea}`);
for (const aviso of avisosDeArranque(configuracion)) console.warn(`[alivia/api] AVISO: ${aviso}`);

const PUERTO = configuracion.puerto;

const servidor = createServer((peticion, respuesta) => {
  if (peticion.url === "/salud") {
    respuesta.writeHead(200, { "content-type": "application/json; charset=utf-8" });
    respuesta.end(
      JSON.stringify({
        estado: "arrancado",
        // Honesto a propósito: todavía no comprueba nada. Tarea 7.
        comprueba: [],
        nota: "esqueleto de la tarea 1: no verifica la base de datos ni el correo",
      }),
    );
    return;
  }

  respuesta.writeHead(404, { "content-type": "application/json; charset=utf-8" });
  respuesta.end(JSON.stringify({ error: { codigo: "NO_ENCONTRADO", mensaje: "No existe" } }));
});

// Un puerto ocupado es el primer tropiezo en una maquina nueva. Que diga qué
// pasa y qué hacer, no una traza de veinte lineas sobre 'error' no manejado.
servidor.on("error", (error: NodeJS.ErrnoException) => {
  if (error.code === "EADDRINUSE") {
    console.error(
      `[alivia/api] el puerto ${PUERTO} esta ocupado.\n` +
        `             Poner otro en el .env:  PUERTO=3005\n` +
        `             O parar lo que lo tenga cogido.`,
    );
    process.exit(1);
  }
  console.error(`[alivia/api] no se pudo escuchar en ${PUERTO}: ${error.message}`);
  process.exit(1);
});

servidor.listen(PUERTO, () => {
  console.log(`[alivia/api] escuchando en http://localhost:${PUERTO}`);
});

// Sin esto, `docker compose stop` espera diez segundos y mata el proceso.
for (const senal of ["SIGTERM", "SIGINT"] as const) {
  process.on(senal, () => {
    console.log(`[alivia/api] ${senal}: cerrando`);
    servidor.close(() => process.exit(0));
  });
}
