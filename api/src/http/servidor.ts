// La aplicación Express. No escucha: eso lo hace principal.ts, y por eso esto
// se puede probar levantándola en un puerto efímero.
//
// Lo que estaba escrito a mano con node:http en la tarea 1 pasa aquí, y la
// POLÍTICA de errores y el registro --tarea 6-- se conectan sin tocarse: se
// escribieron sin depender de ningún marco justamente para esto.

// `Express` se renombra: el nombre lo necesita el `namespace Express` de abajo,
// que es como se aumenta el tipo de Request.
import express, {
  type Express as Aplicacion,
  type NextFunction,
  type Request,
  type Response,
} from "express";
import type { ConfiguracionServidor } from "../configuracion/servidor.js";
import { ESTADOS, identificar, rutaNoEncontrada, traducir } from "./errores.js";
import { partirDireccion, registrarError, registrarPeticion } from "./registro.js";
import { codigoDeSalud, reunirSalud } from "./salud.js";

declare global {
  namespace Express {
    interface Request {
      /** Para cruzar la respuesta con la línea del registro. */
      alivia?: { identificador: string; comenzo: bigint };
    }
  }
}

export function crearServidor(configuracion: ConfiguracionServidor): Aplicacion {
  const app = express();

  // No anunciar el marco ni su versión: es información gratis para cualquiera.
  app.disable("x-powered-by");
  // Detrás de nada, por ahora. Declararlo explícito evita confiar en cabeceras
  // X-Forwarded-* que ahora mismo puede poner quien sea.
  app.set("trust proxy", false);

  app.use((peticion: Request, respuesta: Response, siguiente: NextFunction) => {
    const identificador = identificar();
    peticion.alivia = { identificador, comenzo: process.hrtime.bigint() };
    respuesta.setHeader("x-alivia-peticion", identificador);

    respuesta.on("finish", () => {
      const { ruta, nombresDeConsulta } = partirDireccion(peticion.originalUrl);
      registrarPeticion({
        metodo: peticion.method,
        ruta,
        nombresDeConsulta,
        estado: respuesta.statusCode,
        milisegundos: Number(
          (process.hrtime.bigint() - (peticion.alivia?.comenzo ?? 0n)) / 1_000_000n,
        ),
        identificador,
      });
    });

    siguiente();
  });

  app.get("/salud", async (_peticion: Request, respuesta: Response) => {
    const salud = await reunirSalud({
      smtp: configuracion.smtp,
      fechaReferencia: configuracion.fechaReferencia,
    });
    respuesta.status(codigoDeSalud(salud)).json(salud);
  });

  // Cualquier otra ruta. Se LANZA en lugar de responder: el cuerpo lo da un
  // solo sitio (decisión 4). Express 5 pasa lo lanzado al manejador de errores,
  // incluido lo de una función asíncrona.
  app.use((_peticion: Request, _respuesta: Response, siguiente: NextFunction) => {
    siguiente(rutaNoEncontrada());
  });

  // Aquí acaba TODO lo que se lance. Sin este punto único, un TypeError sale al
  // cliente con la forma interna del servidor dentro.
  app.use((error: unknown, peticion: Request, respuesta: Response, siguiente: NextFunction) => {
    const identificador = peticion.alivia?.identificador ?? identificar();
    const traducido = traducir(error, identificador);

    registrarError(
      identificador,
      traducido.paraElRegistro,
      traducido.inesperado,
      traducido.estado !== ESTADOS.interno,
    );

    if (respuesta.headersSent) {
      // Ya se empezó a responder: no se puede cambiar el estado. Se corta, y el
      // detalle queda en el registro.
      respuesta.end();
      return siguiente(error);
    }
    respuesta.status(traducido.estado).json(traducido.cuerpo);
  });

  return app;
}
