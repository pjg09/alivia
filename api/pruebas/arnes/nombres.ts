// De dónde salen las URLs del arnés, y por qué el arnés NUNCA toca la base con
// la que se trabaja.
//
// «Deja la base como la encontró» se puede cumplir de dos formas: limpiando
// después, o no tocándola nunca. La segunda es la única que sobrevive a que una
// prueba se caiga a mitad, así que el arnés se crea sus propias bases y la de
// trabajo no aparece en ninguna cadena de conexión.
//
// Hace falta el rol propietario porque CREATE DATABASE lo exige. Es el único
// sitio del proyecto donde aparece: `api/src/` no puede nombrarlo, y eso lo
// comprueba scripts/verificar-arquitectura.py. Un arnés de pruebas no corre en
// ningún contenedor y no atiende peticiones.

const URL_PROPIETARIO_POR_DEFECTO =
  "postgres://alivia_propietario:desarrollo@localhost:5434/alivia";

/** La base cuyo esquema se copia. Se crea una vez por ejecución de `npm test`. */
export const PLANTILLA = "alivia_plantilla_pruebas";

/** Prefijo de las bases de cada fichero de pruebas. Lo usa la limpieza. */
export const PREFIJO_EFIMERA = "alivia_prueba_";

function urlPropietario(): URL {
  const crudo = process.env["DATABASE_URL_MIGRACIONES"]?.trim();
  return new URL(crudo !== undefined && crudo !== "" ? crudo : URL_PROPIETARIO_POR_DEFECTO);
}

/** La base de trabajo, la que no se toca. Solo para comprobar que no se toca. */
export function nombreDeLaBaseDeTrabajo(): string {
  return urlPropietario().pathname.replace(/^\//, "");
}

/**
 * Conexión a `postgres`, la base de mantenimiento. CREATE DATABASE y DROP
 * DATABASE no se pueden ejecutar desde la base que se está creando o borrando.
 */
export function urlDeMantenimiento(): string {
  const url = urlPropietario();
  url.pathname = "/postgres";
  return url.toString();
}

/** Como propietario, sobre la base que se indique. Para aplicar migraciones. */
export function urlDePropietarioSobre(base: string): string {
  const url = urlPropietario();
  url.pathname = `/${base}`;
  return url.toString();
}

/**
 * Como `alivia_app`, que está SUJETO a las políticas RLS. Las pruebas corren
 * con este rol a propósito: con el propietario pasarían todas y no comprobarían
 * nada, porque el propietario ignora RLS por completo. Regla 1 de CLAUDE.md.
 */
export function urlDeAplicacionSobre(base: string): string {
  const url = urlPropietario();
  url.username = "alivia_app";
  url.pathname = `/${base}`;
  return url.toString();
}

/** Nombre único por proceso: `node --test` corre cada fichero en el suyo. */
export function nombreEfimero(): string {
  const azar = Math.random().toString(36).slice(2, 8);
  return `${PREFIJO_EFIMERA}${process.pid}_${azar}`;
}
