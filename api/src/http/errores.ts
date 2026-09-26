// El ÚNICO sitio que da forma a una respuesta de error.
//
// Decisión 4 de docs/arquitectura.md. Que sea uno solo no es orden por el orden:
// un cuerpo de error construido a mano en un manejador es por donde se escapa
// el mensaje de psql con la cadena de conexión, o el «Key (correo)=(ana@...)
// already exists» que confirma qué correos están registrados. Y la interfaz
// necesita un `codigo` estable para decidir sin leer texto.
//
// `scripts/verificar-arquitectura.py` falla si otro fichero construye el cuerpo.

import { randomBytes } from "node:crypto";

/** Los únicos estados que este servidor devuelve. Decisión 4a. */
export const ESTADOS = {
  peticionInvalida: 400,
  sinSesion: 401,
  sinAcceso: 403,
  noEncontrado: 404,
  conflicto: 409,
  interno: 500,
} as const;

export type Estado = (typeof ESTADOS)[keyof typeof ESTADOS];

type Opciones = {
  /** Para el registro, NUNCA para la respuesta. Aquí va lo que no puede salir. */
  readonly detalle?: string;
  readonly causa?: unknown;
};

/**
 * Un error que el servidor sabe explicar. Su `mensaje` está escrito para que lo
 * lea la persona que usa Alivia, así que no lleva nombres de tabla, ni SQL, ni
 * el correo de nadie.
 */
export class ErrorDeAplicacion extends Error {
  readonly detalle: string | undefined;

  constructor(
    readonly codigo: string,
    readonly estado: Estado,
    readonly mensajePublico: string,
    opciones: Opciones = {},
  ) {
    super(`${codigo}: ${mensajePublico}`);
    this.name = "ErrorDeAplicacion";
    this.detalle = opciones.detalle;
    if (opciones.causa !== undefined) this.cause = opciones.causa;
  }
}

export class PeticionInvalida extends ErrorDeAplicacion {
  constructor(codigo: string, mensajePublico: string, opciones?: Opciones) {
    super(codigo, ESTADOS.peticionInvalida, mensajePublico, opciones);
  }
}

export class SinSesion extends ErrorDeAplicacion {
  constructor(
    codigo = "SIN_SESION",
    mensajePublico = "Hay que iniciar sesión.",
    opciones?: Opciones,
  ) {
    super(codigo, ESTADOS.sinSesion, mensajePublico, opciones);
  }
}

export class SinAcceso extends ErrorDeAplicacion {
  constructor(codigo: string, mensajePublico: string, opciones?: Opciones) {
    super(codigo, ESTADOS.sinAcceso, mensajePublico, opciones);
  }
}

export class NoEncontrado extends ErrorDeAplicacion {
  constructor(codigo = "NO_ENCONTRADO", mensajePublico = "Eso no existe.", opciones?: Opciones) {
    super(codigo, ESTADOS.noEncontrado, mensajePublico, opciones);
  }
}

export class ConflictoDeEstado extends ErrorDeAplicacion {
  constructor(codigo: string, mensajePublico: string, opciones?: Opciones) {
    super(codigo, ESTADOS.conflicto, mensajePublico, opciones);
  }
}

export type CuerpoDeError = {
  readonly error: {
    readonly codigo: string;
    readonly mensaje: string;
    /** Aleatorio. Es lo que une lo que vio el usuario con la línea del registro. */
    readonly identificador: string;
  };
};

export type RespuestaDeError = {
  readonly estado: Estado;
  readonly cuerpo: CuerpoDeError;
  /** Lo que va al registro y NO a la respuesta. Puede contener cualquier cosa. */
  readonly paraElRegistro: string;
  /** true si el servidor no supo qué era: eso siempre es un defecto que mirar. */
  readonly inesperado: boolean;
};

export function identificar(): string {
  return randomBytes(5).toString("hex");
}

function describir(error: unknown): string {
  if (error instanceof Error) {
    const pila = error.stack ?? `${error.name}: ${error.message}`;
    const causa = error.cause === undefined ? "" : `\n  causa: ${describir(error.cause)}`;
    return `${pila}${causa}`;
  }
  // Un `throw 'texto'` o un objeto suelto: se describe sin confiar en su forma.
  try {
    return `valor lanzado que no es un Error: ${JSON.stringify(error)}`;
  } catch {
    return "valor lanzado que no es un Error y no se puede serializar";
  }
}

/**
 * Traduce cualquier cosa lanzada a una respuesta. Es la frontera: lo que entra
 * puede llevar la cadena de conexión, un correo o una pila entera; lo que sale
 * lleva un código, una frase y un identificador aleatorio, y nada más.
 *
 * Lo desconocido NO se describe al cliente. Decir «TypeError: cannot read
 * property usuario_id of undefined» le cuenta a cualquiera cómo está hecho el
 * servidor, y no le sirve de nada a quien solo quería ver sus vencimientos.
 */
export function traducir(error: unknown, identificador = identificar()): RespuestaDeError {
  if (error instanceof ErrorDeAplicacion) {
    const detalle = error.detalle === undefined ? "" : `\n  detalle: ${error.detalle}`;
    return {
      estado: error.estado,
      cuerpo: { error: { codigo: error.codigo, mensaje: error.mensajePublico, identificador } },
      // Sin la pila: un 404 de ruta inexistente no es un defecto, y llenar el
      // registro de trazas por cada direccion mal escrita hace que nadie lo lea
      // el dia que aparezca una que si importa. Lo que haga falta saber va en
      // `detalle`, que es lo que el codigo de cada caso decide poner.
      paraElRegistro: `${error.codigo} (${error.estado})${detalle}`,
      inesperado: false,
    };
  }

  return {
    estado: ESTADOS.interno,
    cuerpo: {
      error: {
        codigo: "ERROR_INTERNO",
        mensaje:
          "Algo falló de nuestro lado. El problema quedó registrado; si hace falta " +
          `reportarlo, este es su identificador: ${identificador}`,
        identificador,
      },
    },
    paraElRegistro: describir(error),
    inesperado: true,
  };
}

/** Lo que responde una ruta que no existe. Pasa por la misma frontera. */
export function rutaNoEncontrada(): NoEncontrado {
  return new NoEncontrado("RUTA_NO_ENCONTRADA", "Esa dirección no existe.");
}

/**
 * El catálogo de códigos genéricos, para que la interfaz sepa contra qué
 * decidir sin leer los textos. Los códigos de cada funcionalidad se añaden con
 * ella; estos son los que existen desde el principio.
 */
export const CATALOGO: readonly { codigo: string; estado: Estado; cuando: string }[] = [
  { codigo: "PETICION_INVALIDA", estado: 400, cuando: "el cuerpo o los parámetros no validan" },
  { codigo: "SIN_SESION", estado: 401, cuando: "no hay sesión, o el token es inválido o caducó" },
  {
    codigo: "SIN_ACCESO",
    estado: 403,
    cuando: "hay sesión, pero no acceso a ese módulo o recurso",
  },
  { codigo: "NO_ENCONTRADO", estado: 404, cuando: "no existe, o no es de este usuario" },
  {
    codigo: "RUTA_NO_ENCONTRADA",
    estado: 404,
    cuando: "la dirección no corresponde a ninguna ruta",
  },
  {
    codigo: "CONFLICTO_DE_ESTADO",
    estado: 409,
    cuando: "cumplir algo ya cumplido, solapar suscripciones",
  },
  { codigo: "ERROR_INTERNO", estado: 500, cuando: "cualquier otra cosa. Siempre es un defecto" },
];
