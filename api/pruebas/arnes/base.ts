// La base efímera de cada fichero de pruebas.
//
// `node --test` corre cada fichero en su propio proceso, así que cada uno se
// hace una base propia copiando la plantilla. Copiar es mucho más rápido que
// aplicar veintitrés ficheros SQL: postgres copia los ficheros de la plantilla
// en lugar de ejecutar nada.
//
// Por eso «cada prueba corre contra una base limpia» no es una aspiración: lo
// que una prueba escriba no existe para ninguna otra, porque están en bases
// distintas.

import { Client } from "pg";
import { cerrarAcceso, iniciarAcceso } from "../../src/datos/contexto.js";
import { enMantenimiento } from "./mantenimiento.js";
import {
  nombreEfimero,
  PLANTILLA,
  urlDeAplicacionSobre,
  urlDeMantenimiento,
  urlDePropietarioSobre,
} from "./nombres.js";

export type BaseEfimera = {
  readonly nombre: string;
  /** Cierra el pool y borra la base. Va en un `after()`. */
  readonly cerrar: () => Promise<void>;
};

/**
 * Crea una base copiando la plantilla, inicia el acceso a datos contra ella con
 * el rol `alivia_app`, y devuelve cómo deshacerlo.
 *
 * Se llama en un `before()` y su `cerrar` en un `after()`.
 */
export async function abrirBaseEfimera(
  opciones: { fechaReferencia?: string } = {},
): Promise<BaseEfimera> {
  const nombre = nombreEfimero();

  await enMantenimiento(async (cliente) => {
    // Los identificadores no admiten parámetros, así que van interpolados. El
    // nombre lo genera nombreEfimero() y no viene de fuera, pero se comprueba
    // igual: una interpolación sin comprobar en un CREATE DATABASE es el sitio
    // exacto donde nadie la busca.
    if (!/^[a-z0-9_]+$/.test(nombre)) throw new Error(`nombre de base inválido: ${nombre}`);
    await cliente.query(`CREATE DATABASE ${nombre} TEMPLATE ${PLANTILLA}`);
  });

  iniciarAcceso({
    url: urlDeAplicacionSobre(nombre),
    fechaReferencia: opciones.fechaReferencia,
  });

  return {
    nombre,
    cerrar: async () => {
      // Primero el pool: DROP DATABASE falla si queda una conexión abierta.
      await cerrarAcceso();
      await enMantenimiento(async (cliente) => {
        // FORCE por si una prueba dejó algo colgando: sin él, un solo cliente
        // olvidado deja la base ahí y la siguiente ejecución la encuentra.
        await cliente.query(`DROP DATABASE IF EXISTS ${nombre} WITH (FORCE)`);
      });
    },
  };
}

/**
 * Consulta la base efímera con el rol PROPIETARIO, que ignora RLS.
 *
 * Solo para fixtures: leer el identificador de un usuario sembrado, contar
 * migraciones aplicadas, preparar un estado de partida. Una fixture puede tener
 * privilegios que el servidor no tiene; lo que NO puede es comprobar con ellos,
 * porque con el propietario cualquier prueba de aislamiento pasa sin comprobar
 * nada. Las afirmaciones van por `conUsuario()`, con `alivia_app`.
 *
 * Vive aquí y no en una prueba a propósito: `verificar-arquitectura.py` falla si
 * un fichero *.prueba.ts importa `pg` por su cuenta.
 */
export async function comoPropietario<Fila extends Record<string, unknown>>(
  base: BaseEfimera,
  sql: string,
  parametros: readonly unknown[] = [],
): Promise<Fila[]> {
  const cliente = new Client({ connectionString: urlDePropietarioSobre(base.nombre) });
  await cliente.connect();
  try {
    const resultado = await cliente.query(sql, [...parametros]);
    return resultado.rows as Fila[];
  } finally {
    await cliente.end();
  }
}

/** Los identificadores de los usuarios que siembra 030_usuarios_prueba.sql. */
export async function usuariosDePrueba(base: BaseEfimera): Promise<{ ana: string; beto: string }> {
  const filas = await comoPropietario<{ correo: string; id: string }>(
    base,
    "SELECT correo, id::text AS id FROM usuario ORDER BY correo",
  );
  const ana = filas.find((f) => f.correo === "ana@prueba.local")?.id;
  const beto = filas.find((f) => f.correo === "beto@prueba.local")?.id;
  if (ana === undefined || beto === undefined) {
    throw new Error(
      `faltan los usuarios de prueba en la base efímera: se encontraron ${filas.length}. ` +
        "¿Se aplicaron las semillas a la plantilla?",
    );
  }
  return { ana, beto };
}
