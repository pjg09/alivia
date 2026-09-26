// Configuración del proceso que atiende peticiones.
//
// LO QUE NO DECLARA, Y ES LO IMPORTANTE: `DATABASE_URL_AVISOS`. Ese rol lee las
// obligaciones de TODOS los usuarios, y si este proceso pudiera construir ese
// pool, el aislamiento entre usuarios quedaría anulado por la puerta de atrás,
// en silencio y sin que ninguna prueba de RLS se enterara, porque las políticas
// estarían haciendo justo lo que se les pidió. Decisión 2 de
// docs/arquitectura.md, y lo comprueba scripts/verificar-arquitectura.py.
//
// Tampoco declara `DATABASE_URL_MIGRACIONES`: aplicar el esquema es trabajo del
// servicio `migraciones`, con el rol propietario, que ignora RLS por completo.

import { randomBytes } from "node:crypto";
import { combinar, ErrorDeConfiguracion, Lector, leerArchivoEnv } from "./entorno.js";

/** Las únicas variables que este proceso lee. Del .env no se toca nada más. */
const DECLARADAS = [
  "PUERTO",
  "DATABASE_URL",
  "JWT_SECRETO",
  "ZONA_HORARIA",
  "DIAS_ANTICIPACION_POR_DEFECTO",
  "SMTP_HOST",
  "SMTP_PUERTO",
  "FECHA_REFERENCIA",
] as const;

/**
 * Valores que están en .env.example para ser copiados, no usados. Arrancar con
 * uno de estos es peor que no tener nada: parece configurado y no lo está.
 */
const DE_PLANTILLA = new Set([
  "cambiar-en-cada-maquina",
  "cambiar-en-cada-máquina",
  "cambiame",
  "cámbiame",
  "secreto",
  "changeme",
  "CAMBIAR",
]);

const LARGO_MINIMO_SECRETO = 32;

export type ConfiguracionServidor = {
  readonly puerto: number;
  /** Rol `alivia_app`, SUJETO a las políticas RLS. Regla 1 de CLAUDE.md. */
  readonly urlBaseDeDatos: string;
  readonly jwtSecreto: string;
  /** true si el secreto se generó al arrancar: las sesiones no sobreviven a un reinicio. */
  readonly jwtSecretoEfimero: boolean;
  readonly zonaHoraria: string;
  readonly diasAnticipacionPorDefecto: number;
  /** Solo para sondear el puerto en `GET /salud`. Este proceso no envía correo. */
  readonly smtp: { readonly host: string; readonly puerto: number };
  /** Fecha civil que inyecta el reloj. Sin ella, `app.hoy()` usa la fecha real. */
  readonly fechaReferencia: string | undefined;
};

type ResultadoSecreto = { valor: string; efimero: boolean };

/**
 * `JWT_SECRETO` es el único caso con tratamiento especial, y la razón es que
 * tres reglas del proyecto chocan en él:
 *
 *   - La regla 7 dice que `up` sin .env deja el proyecto listo.
 *   - Esta validación rechaza los valores de plantilla.
 *   - Y no puede haber secretos en el repositorio, ni de pruebas.
 *
 * Con un valor por defecto en el compose se incumple la tercera, y si ese valor
 * es el de plantilla, el proceso muere y se incumple la primera. Sin ninguno,
 * muere igual. La salida es distinguir AUSENTE de INVÁLIDO: ausente se genera,
 * inválido mata. Decisión 2 de docs/arquitectura.md.
 *
 * Es el único caso: una URL de base de datos ausente no se inventa.
 */
function resolverSecreto(lector: Lector, crudo: string | undefined): ResultadoSecreto {
  if (crudo === undefined || crudo.trim() === "") {
    return { valor: randomBytes(32).toString("base64url"), efimero: true };
  }

  const valor = crudo.trim();

  if (DE_PLANTILLA.has(valor)) {
    lector.problema(
      "JWT_SECRETO",
      `«${valor}» es el valor de plantilla de .env.example, no un secreto`,
      "quitarlo del .env para que el servidor genere uno, o poner uno propio de " +
        `al menos ${LARGO_MINIMO_SECRETO} caracteres`,
    );
    return { valor, efimero: false };
  }

  if (valor.length < LARGO_MINIMO_SECRETO) {
    lector.problema(
      "JWT_SECRETO",
      `tiene ${valor.length} caracteres y hacen falta al menos ${LARGO_MINIMO_SECRETO}`,
      "quitarlo del .env para que el servidor genere uno, o alargarlo",
    );
    return { valor, efimero: false };
  }

  return { valor, efimero: false };
}

export function cargarConfiguracionServidor(
  entorno: NodeJS.ProcessEnv = process.env,
  rutaEnv = ".env",
): ConfiguracionServidor {
  const valores = combinar(leerArchivoEnv(DECLARADAS, rutaEnv), entorno, DECLARADAS);
  const lector = new Lector(valores);

  const secreto = resolverSecreto(lector, valores.JWT_SECRETO);

  const configuracion: ConfiguracionServidor = {
    puerto: lector.entero("PUERTO", 3000, 1, 65535),
    urlBaseDeDatos: lector.urlDePostgres(
      "DATABASE_URL",
      "alivia_app",
      "es por donde el servidor lee y escribe los datos del usuario",
    ),
    jwtSecreto: secreto.valor,
    jwtSecretoEfimero: secreto.efimero,
    zonaHoraria: lector.texto("ZONA_HORARIA", "America/Bogota"),
    diasAnticipacionPorDefecto: lector.entero("DIAS_ANTICIPACION_POR_DEFECTO", 15, 1, 365),
    smtp: {
      host: lector.texto("SMTP_HOST", "localhost"),
      puerto: lector.entero("SMTP_PUERTO", 1025, 1, 65535),
    },
    fechaReferencia: lector.fechaCivil("FECHA_REFERENCIA"),
  };

  lector.cerrar("api");
  return configuracion;
}

/** Lo que se imprime al arrancar. Nunca el secreto ni la contraseña de la URL. */
export function resumir(c: ConfiguracionServidor): string[] {
  const url = new URL(c.urlBaseDeDatos);
  const lineas = [
    `puerto            ${c.puerto}`,
    `base de datos     ${url.username}@${url.host}${url.pathname}`,
    `zona horaria      ${c.zonaHoraria}`,
    `anticipación      ${c.diasAnticipacionPorDefecto} días por defecto`,
    `correo (sondeo)   ${c.smtp.host}:${c.smtp.puerto}`,
  ];
  if (c.fechaReferencia !== undefined) {
    lineas.push(`RELOJ INYECTADO   hoy es ${c.fechaReferencia}, no la fecha real`);
  }
  return lineas;
}

export function avisosDeArranque(c: ConfiguracionServidor): string[] {
  const avisos: string[] = [];
  if (c.jwtSecretoEfimero) {
    avisos.push(
      "JWT_SECRETO no estaba definido: se generó uno aleatorio. Las sesiones no " +
        "sobrevivirán a un reinicio del proceso. Para que lo hagan, definirlo en el .env.",
    );
  }
  if (c.fechaReferencia !== undefined) {
    avisos.push(
      `El reloj está inyectado en ${c.fechaReferencia}. Los vencimientos se calculan ` +
        "contra esa fecha y no contra hoy.",
    );
  }
  return avisos;
}

export { ErrorDeConfiguracion };
