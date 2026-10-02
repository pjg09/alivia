// GET /salud — qué funciona y qué no.
//
// Criterio de la tarea 7: reporta si la base de datos y el correo están
// accesibles. «Accesible» no es «el puerto está abierto»: eso ya nos engañó una
// vez. Para la base se ejecuta una consulta; para el correo se lee el saludo y
// se exige que sea un 220 de SMTP.
//
// QUÉ NO SALE DE AQUÍ. Ni cadenas de conexión, ni anfitriones, ni puertos, ni
// el saludo del servidor de correo literal --el de Mailpit lleva dentro el
// identificador del contenedor--. Solo qué se comprobó, si funcionó y cuánto
// tardó. `/salud` es un endpoint operativo y no está autenticado: si algún día
// esto se publica, hay que protegerlo.

import { createConnection } from "node:net";
import { comprobarConexion } from "../datos/contexto.js";

export type EstadoDeDependencia = {
  readonly que: string;
  /**
   * `true` si el servidor no puede hacer su trabajo sin esto. Solo la base de
   * datos lo es: sin correo el servidor sigue atendiendo todo --el que envía es
   * el proceso de avisos, decisión 5--, así que declararse enfermo por eso
   * sería mentir. El healthcheck del contenedor lee el código HTTP, y «api
   * enfermo» tiene que querer decir que el api está mal.
   */
  readonly esencial: boolean;
  readonly estado: "sano" | "caido";
  readonly milisegundos: number;
  /** Corto y sin topología. Vacío si no hay nada que valga la pena decir. */
  readonly detalle?: string;
  /** Por qué falló, ya saneado. Solo cuando está caído. */
  readonly problema?: string;
};

export type Salud = {
  /** `degradado` si algo está caído, aunque no sea esencial. */
  readonly estado: "sano" | "degradado";
  /** `true` si falló algo sin lo que el servidor no puede trabajar. */
  readonly falloEsencial: boolean;
  /** La fecha que ve `app.hoy()`: dice si el reloj está inyectado. */
  readonly hoy?: string;
  readonly relojInyectado: boolean;
  readonly comprueba: readonly EstadoDeDependencia[];
};

const TIEMPO_LIMITE = 2000;

async function medir(
  que: string,
  esencial: boolean,
  trabajo: () => Promise<string | undefined>,
): Promise<EstadoDeDependencia> {
  const comenzo = process.hrtime.bigint();
  const ms = () => Number((process.hrtime.bigint() - comenzo) / 1_000_000n);
  try {
    // Con limite. Sin el, un fallo de resolucion de nombres tardaba cinco
    // segundos --medido-- y /salud se pasaba del tiempo del healthcheck del
    // contenedor: el sintoma dejaba de ser «la base no responde» y pasaba a ser
    // «/salud no responde», que dice menos.
    const detalle = await Promise.race([
      trabajo(),
      new Promise<never>((_, rechazar) =>
        setTimeout(
          () => rechazar(Object.assign(new Error("tiempo agotado"), { code: "ETIMEDOUT" })),
          TIEMPO_LIMITE,
        ).unref(),
      ),
    ]);
    return detalle === undefined
      ? { que, esencial, estado: "sano", milisegundos: ms() }
      : { que, esencial, estado: "sano", milisegundos: ms(), detalle };
  } catch (error) {
    // El mensaje de un fallo de conexión puede llevar el anfitrión y el puerto,
    // así que se reduce a su causa. El detalle entero va al registro, no aquí.
    const codigo = (error as { code?: string } | null)?.code;
    return {
      que,
      esencial,
      estado: "caido",
      milisegundos: ms(),
      problema: codigo ?? "no respondió",
    };
  }
}

/** Lee el saludo y exige un 220: un puerto abierto no es un servidor SMTP. */
export function comprobarCorreo(host: string, puerto: number): Promise<string> {
  return new Promise((resolver, rechazar) => {
    const conexion = createConnection({ host, port: puerto });
    let saludo = "";

    const terminar = (error?: Error) => {
      conexion.removeAllListeners();
      conexion.destroy();
      if (error) rechazar(error);
      else resolver(saludo);
    };

    conexion.setTimeout(TIEMPO_LIMITE);
    conexion.on("timeout", () =>
      terminar(Object.assign(new Error("tiempo agotado"), { code: "ETIMEDOUT" })),
    );
    conexion.on("error", (error) => terminar(error));
    conexion.on("data", (trozo) => {
      saludo += trozo.toString("utf8");
      if (!saludo.includes("\n")) return;
      const primera = saludo.split("\n")[0] ?? "";
      if (!primera.startsWith("220 ")) {
        terminar(Object.assign(new Error("no saludó como SMTP"), { code: "NO_ES_SMTP" }));
        return;
      }
      // El saludo lleva el identificador del contenedor: solo se devuelve si
      // parece Mailpit, y sin el resto.
      conexion.write("QUIT\r\n");
      saludo = primera.includes("Mailpit") ? "Mailpit" : "SMTP";
      terminar();
    });
  });
}

export async function reunirSalud(opciones: {
  smtp: { host: string; puerto: number };
  /** La del arranque. Si está, el reloj NO es el real y conviene que se vea. */
  fechaReferencia?: string | undefined;
}): Promise<Salud> {
  const { smtp } = opciones;
  let hoy: string | undefined;

  const [baseDeDatos, correo] = await Promise.all([
    medir("base de datos", true, async () => {
      const { version, hoy: fecha } = await comprobarConexion();
      hoy = fecha;
      // La versión mayor basta: «postgres 16» no cuenta nada de la topología.
      return `postgres ${version.split(".")[0] ?? "?"}`;
    }),
    medir("correo", false, async () => comprobarCorreo(smtp.host, smtp.puerto)),
  ]);

  const comprueba = [baseDeDatos, correo];
  const sano = comprueba.every((c) => c.estado === "sano");

  const salud: Salud = {
    estado: sano ? "sano" : "degradado",
    falloEsencial: comprueba.some((c) => c.esencial && c.estado === "caido"),
    relojInyectado: opciones.fechaReferencia !== undefined,
    comprueba,
  };
  if (hoy === undefined) return salud;
  return { ...salud, hoy };
}

/**
 * El código HTTP que le corresponde a un estado de salud.
 *
 * 503 solo si falló algo ESENCIAL. Está aquí y no incrustado en la ruta para
 * poder probar la decisión sin tener que tumbar la base de datos.
 */
export function codigoDeSalud(salud: Salud): 200 | 503 {
  return salud.falloEsencial ? 503 : 200;
}
