// Configuración del proceso de avisos. Es otro proceso, no un hilo del
// servidor, y esta separación es la que vuelve estructural el aislamiento:
// el pool del rol `alivia_avisos` --que lee las obligaciones de todos los
// usuarios-- no existe en la memoria de lo que atiende peticiones.
// Decisión 5 de docs/arquitectura.md.
//
// LO QUE NO DECLARA: `DATABASE_URL` ni `JWT_SECRETO`. Este proceso no atiende
// peticiones, no emite sesiones y no escribe datos de usuario: solo lee
// obligaciones y registra el resultado real de cada envío.

import { combinar, ErrorDeConfiguracion, Lector, leerArchivoEnv } from "./entorno.js";

const DECLARADAS = [
  "DATABASE_URL_AVISOS",
  "SMTP_HOST",
  "SMTP_PUERTO",
  "SMTP_REMITENTE",
  "ZONA_HORARIA",
  "FECHA_REFERENCIA",
] as const;

export type ConfiguracionAvisos = {
  /** Rol `alivia_avisos`: SELECT sobre las obligaciones de todos los usuarios. */
  readonly urlBaseDeDatos: string;
  readonly smtp: {
    readonly host: string;
    readonly puerto: number;
    readonly remitente: string;
  };
  readonly zonaHoraria: string;
  /** Lo que hace demostrable la tarea 34: evaluar como si hoy fuera otro día. */
  readonly fechaReferencia: string | undefined;
};

export function cargarConfiguracionAvisos(
  entorno: NodeJS.ProcessEnv = process.env,
  rutaEnv = ".env",
): ConfiguracionAvisos {
  const valores = combinar(leerArchivoEnv(DECLARADAS, rutaEnv), entorno, DECLARADAS);
  const lector = new Lector(valores);

  const configuracion: ConfiguracionAvisos = {
    urlBaseDeDatos: lector.urlDePostgres(
      "DATABASE_URL_AVISOS",
      "alivia_avisos",
      "es por donde el proceso de avisos lee las obligaciones que están por vencer",
    ),
    smtp: {
      host: lector.texto("SMTP_HOST", "localhost"),
      puerto: lector.entero("SMTP_PUERTO", 1025, 1, 65535),
      remitente: lector.texto("SMTP_REMITENTE", "Alivia <avisos@alivia.local>"),
    },
    zonaHoraria: lector.texto("ZONA_HORARIA", "America/Bogota"),
    fechaReferencia: lector.fechaCivil("FECHA_REFERENCIA"),
  };

  lector.cerrar("avisos");
  return configuracion;
}

export { ErrorDeConfiguracion };
