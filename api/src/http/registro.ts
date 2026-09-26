// Registro de peticiones. Una línea por petición, legible en
// `docker compose logs api`, porque el único ambiente es local y quien lo lee
// es una persona.
//
// LO QUE NO SE REGISTRA, Y ES EL PUNTO DE LA TAREA:
//
//   - La cadena de consulta. Ahí es donde acaban los tokens pegados a mano y
//     los correos en un formulario mal hecho. Se registran los NOMBRES de los
//     parámetros, nunca sus valores: sirve para depurar y no cuenta nada.
//   - Las cabeceras. `Authorization` lleva el token de sesión entero.
//   - El cuerpo. Ahí viajan las contraseñas.
//
// Sí se registra el identificador del usuario, que es un uuid. Hace falta para
// depurar un problema de aislamiento --«esta consulta devolvió cero filas, ¿con
// qué contexto corrió?»-- y un uuid no dice quién es nadie. El correo no se
// registra nunca.

export type PeticionRegistrable = {
  readonly metodo: string;
  /** Sin la cadena de consulta. */
  readonly ruta: string;
  readonly nombresDeConsulta: readonly string[];
  readonly estado: number;
  readonly milisegundos: number;
  readonly identificador: string;
  readonly usuarioId?: string | undefined;
};

/** Separa la ruta de los nombres de los parámetros, descartando los valores. */
export function partirDireccion(url: string): { ruta: string; nombresDeConsulta: string[] } {
  const corte = url.indexOf("?");
  if (corte === -1) return { ruta: url, nombresDeConsulta: [] };

  const ruta = url.slice(0, corte);
  const nombres = new Set<string>();
  for (const par of url.slice(corte + 1).split("&")) {
    if (par === "") continue;
    const igual = par.indexOf("=");
    const nombre = igual === -1 ? par : par.slice(0, igual);
    if (nombre !== "") nombres.add(decodeURIComponent(nombre));
  }
  return { ruta, nombresDeConsulta: [...nombres].sort() };
}

export function lineaDePeticion(p: PeticionRegistrable): string {
  const partes = [
    String(p.estado),
    p.metodo,
    p.ruta,
    `${p.milisegundos}ms`,
    `id=${p.identificador}`,
  ];
  if (p.nombresDeConsulta.length > 0) {
    partes.push(`consulta=${p.nombresDeConsulta.join(",")}`);
  }
  if (p.usuarioId !== undefined) {
    partes.push(`usuario=${p.usuarioId}`);
  }
  return `[alivia/api] ${partes.join(" ")}`;
}

export function registrarPeticion(p: PeticionRegistrable): void {
  const linea = lineaDePeticion(p);
  if (p.estado >= 500) console.error(linea);
  else console.log(linea);
}

/**
 * El detalle interno de un error, en su propia línea y solo en el registro.
 * `paraElRegistro` viene de `traducir()` y puede contener cualquier cosa: la
 * cadena de conexión, una pila, un correo. Por eso va aquí y no a la respuesta.
 */
export function registrarError(
  identificador: string,
  paraElRegistro: string,
  inesperado: boolean,
  hayDetalle: boolean,
): void {
  if (inesperado) {
    // Siempre es un defecto que alguien tiene que mirar: va todo, con la pila.
    console.error(`[alivia/api] ERROR INESPERADO id=${identificador}\n${paraElRegistro}`);
    return;
  }
  // Un error previsto ya queda contado por la linea de la peticion, con su
  // estado. Solo se anade algo si el codigo decidio poner un detalle, y ese
  // detalle es justo lo que no puede salir en la respuesta.
  if (hayDetalle) {
    console.warn(`[alivia/api] error id=${identificador} ${paraElRegistro}`);
  }
}
