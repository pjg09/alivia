// Primitivas para leer y validar el entorno. Sin biblioteca: son ocho campos, y
// a cambio los mensajes dicen exactamente qué hacer y en español, y la imagen
// del servidor sigue sin una sola dependencia de ejecución.
//
// Dos decisiones que no son obvias:
//
//  1. Se acumulan TODOS los problemas y se muere una vez. Morir en el primero
//     obliga a arrancar, leer, corregir y repetir tantas veces como variables
//     falten, que es exactamente lo que hace que nadie configure bien nada.
//  2. Del fichero .env se leen SOLO las variables que el esquema declara. El
//     .env es del proyecto entero y lleva las URLs de los tres roles; cargarlo
//     completo mete en el proceso la del propietario, que ignora RLS. Es la
//     misma fuga que docker-compose.yml tiene prohibida con env_file, y aquí
//     ocurriría dentro del proceso. Decisión 2 de docs/arquitectura.md.

import { readFileSync } from "node:fs";

export type Problema = {
  variable: string;
  problema: string;
  remedio: string;
};

export class ErrorDeConfiguracion extends Error {
  constructor(
    readonly problemas: Problema[],
    readonly perfil: string,
  ) {
    super(`configuración inválida de ${perfil}: ${problemas.length} problema(s)`);
    this.name = "ErrorDeConfiguracion";
  }

  /** Para imprimir antes de morir: una línea por problema, con su remedio. */
  informe(): string {
    const lineas = [
      `[alivia/${this.perfil}] no se puede arrancar: ${this.problemas.length} problema(s) de configuración`,
      "",
    ];
    for (const p of this.problemas) {
      lineas.push(`  ${p.variable}`);
      lineas.push(`    ${p.problema}`);
      lineas.push(`    → ${p.remedio}`);
      lineas.push("");
    }
    lineas.push("  Los valores por defecto y qué significa cada variable están en .env.example.");
    return lineas.join("\n");
  }
}

/**
 * Lee un fichero .env y devuelve solo las claves `declaradas`. Si no existe,
 * devuelve un objeto vacío: arrancar sin .env es la regla 7, no un error.
 */
export function leerArchivoEnv(
  declaradas: readonly string[],
  ruta = ".env",
): Record<string, string> {
  let crudo: string;
  try {
    crudo = readFileSync(ruta, "utf8");
  } catch {
    return {};
  }

  const permitidas = new Set(declaradas);
  const valores: Record<string, string> = {};

  for (const linea of crudo.split("\n")) {
    const limpia = linea.trim();
    if (limpia === "" || limpia.startsWith("#")) continue;

    const igual = limpia.indexOf("=");
    if (igual < 1) continue;

    const nombre = limpia.slice(0, igual).trim();
    if (!permitidas.has(nombre)) continue;

    let valor = limpia.slice(igual + 1).trim();
    // Comillas envolventes, como las que lleva SMTP_REMITENTE en .env.example.
    if (valor.length >= 2 && (valor.startsWith('"') || valor.startsWith("'"))) {
      const cierre = valor[valor.length - 1];
      if (cierre === valor[0]) valor = valor.slice(1, -1);
    }
    valores[nombre] = valor;
  }

  return valores;
}

/**
 * El entorno del proceso gana sobre el fichero. Así la CI y los contenedores
 * fijan sus propios valores sin que un .env local los tumbe, que es el mismo
 * orden de precedencia que usan db/aplicar.sh y scripts/verificar-todo.sh.
 */
export function combinar(
  archivo: Record<string, string>,
  entorno: NodeJS.ProcessEnv,
  declaradas: readonly string[],
): Record<string, string | undefined> {
  const valores: Record<string, string | undefined> = {};
  for (const nombre of declaradas) {
    const delEntorno = entorno[nombre];
    // Una variable fijada a cadena vacía cuenta como ausente: compose la pasa
    // así cuando se declara `VAR: ${VAR:-}` y nadie la definió.
    valores[nombre] =
      delEntorno !== undefined && delEntorno.trim() !== "" ? delEntorno : archivo[nombre];
  }
  return valores;
}

/** Acumula problemas en lugar de lanzar en el primero. */
export class Lector {
  readonly problemas: Problema[] = [];

  constructor(private readonly valores: Record<string, string | undefined>) {}

  private crudo(nombre: string): string | undefined {
    const v = this.valores[nombre];
    return v === undefined || v.trim() === "" ? undefined : v.trim();
  }

  problema(variable: string, problema: string, remedio: string): void {
    this.problemas.push({ variable, problema, remedio });
  }

  obligatoria(nombre: string, paraQue: string, ejemplo: string): string {
    const v = this.crudo(nombre);
    if (v === undefined) {
      this.problema(nombre, `falta, y es obligatoria: ${paraQue}`, `añadirla al .env — ${ejemplo}`);
      return "";
    }
    return v;
  }

  texto(nombre: string, porDefecto: string): string {
    return this.crudo(nombre) ?? porDefecto;
  }

  entero(nombre: string, porDefecto: number, minimo: number, maximo: number): number {
    const v = this.crudo(nombre);
    if (v === undefined) return porDefecto;

    const n = Number(v);
    if (!Number.isInteger(n)) {
      this.problema(
        nombre,
        `«${v}» no es un número entero`,
        `poner un entero entre ${minimo} y ${maximo}`,
      );
      return porDefecto;
    }
    if (n < minimo || n > maximo) {
      this.problema(
        nombre,
        `${n} está fuera de rango`,
        `poner un entero entre ${minimo} y ${maximo}`,
      );
      return porDefecto;
    }
    return n;
  }

  urlDePostgres(nombre: string, rolEsperado: string, paraQue: string): string {
    const v = this.obligatoria(
      nombre,
      paraQue,
      `postgres://${rolEsperado}:contraseña@servidor:5432/alivia`,
    );
    if (v === "") return v;

    let url: URL;
    try {
      url = new URL(v);
    } catch {
      this.problema(
        nombre,
        "no es una URL válida",
        `usar la forma postgres://usuario:contraseña@servidor:puerto/base`,
      );
      return v;
    }
    if (url.protocol !== "postgres:" && url.protocol !== "postgresql:") {
      this.problema(
        nombre,
        `el esquema es «${url.protocol}» y tiene que ser postgres:`,
        "corregir la URL",
      );
      return v;
    }
    // Regla 1 de CLAUDE.md: conectar con el rol equivocado no da ningún error,
    // simplemente deja de aislar. Aquí se nota al arrancar y no en producción.
    if (url.username !== rolEsperado) {
      this.problema(
        nombre,
        `conecta con el rol «${url.username}» y este proceso tiene que usar «${rolEsperado}»`,
        `cambiar el usuario de la URL a ${rolEsperado}. Ver la regla 1 de CLAUDE.md`,
      );
    }
    return v;
  }

  /**
   * Fecha civil colombiana, AAAA-MM-DD. Es la que inyecta el reloj: sin ella,
   * app.hoy() usa la fecha real. Nunca un instante: mezclar los dos tipos
   * desfasa los avisos un día.
   */
  fechaCivil(nombre: string): string | undefined {
    const v = this.crudo(nombre);
    if (v === undefined) return undefined;

    if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) {
      this.problema(
        nombre,
        `«${v}» no es una fecha civil AAAA-MM-DD`,
        "usar por ejemplo 2026-12-01. Nunca un instante con hora ni zona",
      );
      return undefined;
    }
    // Number.isNaN sobre la fecha construida atrapa 2026-02-30.
    const [a, m, d] = v.split("-").map(Number) as [number, number, number];
    const fecha = new Date(Date.UTC(a, m - 1, d));
    if (fecha.getUTCFullYear() !== a || fecha.getUTCMonth() !== m - 1 || fecha.getUTCDate() !== d) {
      this.problema(nombre, `«${v}» no existe en el calendario`, "corregir la fecha");
      return undefined;
    }
    return v;
  }

  cerrar(perfil: string): void {
    if (this.problemas.length > 0) throw new ErrorDeConfiguracion(this.problemas, perfil);
  }
}
