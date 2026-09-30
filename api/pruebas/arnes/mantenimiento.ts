// Conexión a la base de mantenimiento, con un diagnóstico que dice qué pasa.
//
// Esto existe por media hora perdida: con el contenedor de Alivia parado, otro
// proyecto de la misma máquina se había quedado con el puerto 5434, y todo lo
// que se intentaba devolvía «password authentication failed for user
// alivia_propietario». El mensaje es correcto y no sirve de nada: la causa no
// era la contraseña, era que había OTRO postgres escuchando ahí.
//
// Un puerto publicado no es una identidad. Antes de crear nada, se comprueba
// que quien contesta es la base de Alivia.

import { Client } from "pg";
import { urlDeMantenimiento } from "./nombres.js";

function pista(error: unknown, url: string): string {
  const puerto = new URL(url).port;
  const mensaje = error instanceof Error ? error.message : String(error);
  const codigo = (error as { code?: string } | null)?.code;

  if (codigo === "ECONNREFUSED") {
    return (
      `nadie contesta en el puerto ${puerto}.\n` +
      "  El ambiente no está levantado: npm run arrancar"
    );
  }
  if (codigo === "28P01" || mensaje.includes("password authentication failed")) {
    return (
      `hay un postgres en el puerto ${puerto}, pero rechaza la contraseña.\n` +
      "  La causa más probable NO es la contraseña: es que ese puerto lo tiene otro\n" +
      '  proyecto. Comprobar con:  docker ps --format "{{.Names}}\\t{{.Ports}}" | grep ' +
      puerto +
      "\n  Si es eso, mover el de Alivia:  PUERTO_POSTGRES=5435 en el .env, y las\n" +
      "  DATABASE_URL_* al mismo puerto."
    );
  }
  return mensaje;
}

/** Conecta a `postgres` para poder crear y borrar bases. */
export async function enMantenimiento<T>(trabajo: (cliente: Client) => Promise<T>): Promise<T> {
  const url = urlDeMantenimiento();
  const cliente = new Client({ connectionString: url });

  try {
    await cliente.connect();
  } catch (error) {
    throw new Error(`[arnés] no se pudo conectar a la base de mantenimiento: ${pista(error, url)}`);
  }

  try {
    return await trabajo(cliente);
  } finally {
    await cliente.end();
  }
}

/**
 * Comprueba que quien contesta es la base de Alivia y no la de otro proyecto.
 * `app.hoy()` es de este esquema y de ningún otro: si no existe, se está
 * hablando con un postgres ajeno que además da la contraseña por buena.
 */
export async function exigirQueSeaAlivia(baseDeTrabajo: string): Promise<void> {
  await enMantenimiento(async (cliente) => {
    const { rows } = await cliente.query<{ existe: boolean }>(
      "SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = $1) AS existe",
      [baseDeTrabajo],
    );
    if (rows[0]?.existe !== true) {
      throw new Error(
        `[arnés] el postgres del puerto contesta, pero no tiene la base «${baseDeTrabajo}».\n` +
          "  Muy probablemente es el postgres de otro proyecto que casualmente acepta la\n" +
          "  misma contraseña. Comprobar qué contenedor publica ese puerto antes de seguir.",
      );
    }
  });

  const cliente = new Client({
    connectionString: urlDeMantenimiento().replace("/postgres", `/${baseDeTrabajo}`),
  });
  await cliente.connect();
  try {
    await cliente.query("SELECT app.hoy()");
  } catch {
    throw new Error(
      `[arnés] la base «${baseDeTrabajo}» existe pero no tiene app.hoy(), así que no es el\n` +
        "  esquema de Alivia. ¿Se aplicaron las migraciones?  ./db/aplicar.sh",
    );
  } finally {
    await cliente.end();
  }
}
