#!/usr/bin/env node
// Dos usos, los dos reales:
//
//     npm run errores            el catálogo de códigos, para la interfaz
//     npm run errores -- fugas   pasa cosas hostiles por la frontera y
//                                enseña qué sale
//
// El segundo lo usa scripts/verificar-errores.py: comprobar que no se filtra
// nada no necesita un servidor levantado, porque la política vive en una
// función pura. La tarea 7 la conectará a Express sin tocarla.

import { CATALOGO, ErrorDeAplicacion, ESTADOS, NoEncontrado, traducir } from "./errores.js";

/** Cosas que un servidor real lanza, con dentro justo lo que no puede salir. */
const HOSTILES: readonly { nombre: string; valor: unknown }[] = [
  {
    nombre: "error con la cadena de conexión dentro",
    valor: new Error(
      'connection to server at "postgres" failed: ' +
        "postgres://alivia_propietario:desarrollo@postgres:5432/alivia",
    ),
  },
  {
    nombre: "error de unicidad de postgres, con el correo de alguien",
    valor: Object.assign(new Error("duplicate key value violates unique constraint"), {
      code: "23505",
      detail: "Key (correo)=(ana.maria@ejemplo.com) already exists.",
      table: "usuario",
    }),
  },
  { nombre: "un throw de texto con un correo", valor: "fallo al enviar a ana.maria@ejemplo.com" },
  {
    nombre: "un objeto suelto",
    valor: { usuario_id: "b3f1", contrasena_hash: "$argon2id$v=19$..." },
  },
  { nombre: "null", valor: null },
  { nombre: "undefined", valor: undefined },
  {
    nombre: "error de aplicación con detalle interno",
    valor: new NoEncontrado("OBLIGACION_NO_ENCONTRADA", "Esa obligación no existe.", {
      detalle: "obligacion_usuario id=9c1e del usuario ana.maria@ejemplo.com",
    }),
  },
  {
    nombre: "error de aplicación con causa encadenada",
    valor: new ErrorDeAplicacion(
      "CONFLICTO_DE_ESTADO",
      ESTADOS.conflicto,
      "Eso ya estaba cumplido.",
      {
        causa: new Error("postgres://alivia_app:desarrollo@postgres:5432/alivia"),
      },
    ),
  },
];

if (process.argv[2] === "fugas") {
  // Una línea JSON por caso: {nombre, estado, cuerpo}. Lo que se imprime es
  // EXACTAMENTE lo que iría al cliente, y nada del registro.
  for (const caso of HOSTILES) {
    const r = traducir(caso.valor, "aaaaaaaaaa");
    console.log(JSON.stringify({ nombre: caso.nombre, estado: r.estado, cuerpo: r.cuerpo }));
  }
} else {
  console.log("Códigos de error del servidor. La interfaz decide contra el código, no el texto.\n");
  for (const e of CATALOGO) {
    console.log(`  ${String(e.estado).padEnd(4)} ${e.codigo.padEnd(22)} ${e.cuando}`);
  }
  // La forma se imprime desde la implementación, no como texto fijo: así no
  // puede quedar documentando algo distinto de lo que el servidor devuelve. Y
  // de paso no hay un literal que verificar-arquitectura.py tenga que perdonar.
  const ejemplo = traducir(new NoEncontrado(), "a1b2c3d4e5").cuerpo;
  console.log("\nLos códigos de cada funcionalidad se añaden con ella. El cuerpo es siempre:");
  console.log(`  ${JSON.stringify(ejemplo)}`);
}
