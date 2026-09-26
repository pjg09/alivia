// Punto de entrada del servidor.
//
// Lo que falta, y dónde:
//
//   datos/     el pool y conUsuario(): el ÚNICO sitio que conoce la conexión
//              (decisión 1)                                        tarea 3
//   http/      Express y el estado real de /salud, con la base y el correo
//              comprobados de verdad                               tareas 7
//   dominio/   cálculo de vencimientos, selección de avisos    tarea 19 y ss.
//
// El servidor es todavía `node:http` y no Express: eso llega en la tarea 7. Lo
// que sí está terminado es la POLÍTICA de errores y el registro --tarea 6--, que
// vive en http/ y no depende de ningún marco, así que la tarea 7 solo la
// conecta.

import { createServer } from "node:http";
import { ErrorDeConfiguracion } from "./configuracion/entorno.js";
import {
  avisosDeArranque,
  cargarConfiguracionServidor,
  resumir,
} from "./configuracion/servidor.js";
import { ErrorDeAplicacion, identificar, rutaNoEncontrada, traducir } from "./http/errores.js";
import { partirDireccion, registrarError, registrarPeticion } from "./http/registro.js";

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

/**
 * Lo que responde cada ruta. Devuelve el cuerpo o LANZA: nadie construye una
 * respuesta de error por su cuenta, porque el cuerpo lo da un solo sitio
 * (decisión 4 de docs/arquitectura.md).
 */
function atender(ruta: string): { estado: number; cuerpo: unknown } {
  if (ruta === "/salud") {
    return {
      estado: 200,
      cuerpo: {
        estado: "arrancado",
        // Honesto a propósito: todavía no comprueba nada. Tarea 7.
        comprueba: [],
        nota: "esqueleto de la tarea 1: no verifica la base de datos ni el correo",
      },
    };
  }
  throw rutaNoEncontrada();
}

const servidor = createServer((peticion, respuesta) => {
  const comenzo = process.hrtime.bigint();
  const identificador = identificar();
  const { ruta, nombresDeConsulta } = partirDireccion(peticion.url ?? "/");

  let estado: number;
  let cuerpo: unknown;

  try {
    const resultado = atender(ruta);
    estado = resultado.estado;
    cuerpo = resultado.cuerpo;
  } catch (error) {
    // Aquí acaba TODO lo que se lance, conocido o no. Sin este punto único, un
    // TypeError sale al cliente con la forma interna del servidor dentro.
    const traducido = traducir(error, identificador);
    estado = traducido.estado;
    cuerpo = traducido.cuerpo;
    registrarError(
      identificador,
      traducido.paraElRegistro,
      traducido.inesperado,
      error instanceof ErrorDeAplicacion && error.detalle !== undefined,
    );
  }

  respuesta.writeHead(estado, {
    "content-type": "application/json; charset=utf-8",
    "x-alivia-peticion": identificador,
  });
  respuesta.end(JSON.stringify(cuerpo));

  registrarPeticion({
    metodo: peticion.method ?? "?",
    ruta,
    nombresDeConsulta,
    estado,
    milisegundos: Number((process.hrtime.bigint() - comenzo) / 1_000_000n),
    identificador,
  });
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
