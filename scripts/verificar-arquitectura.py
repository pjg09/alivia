#!/usr/bin/env python3
"""Comprueba los limites que docs/arquitectura.md declara y el codigo no puede
recordar por su cuenta.

    python3 scripts/verificar-arquitectura.py

Las dos que se comprueban aqui tienen algo en comun: romperlas no produce
ningun error. El programa sigue funcionando, y lo que se pierde es el
aislamiento entre usuarios, en silencio.

  Decision 1 · El pool de conexiones vive en api/src/datos/ y en ningun otro
    sitio. Si un manejador de peticiones importa `pg` por su cuenta, puede
    consultar fuera de una transaccion con contexto, y las politicas RLS
    comparan contra NULL: la consulta devuelve cero filas sin dar error.

  Decision 2 · `DATABASE_URL_AVISOS` no existe en el proceso que atiende
    peticiones. Ese rol tiene SELECT sobre las obligaciones de todos los
    usuarios; si el servidor pudiera construir ese pool, la regla 1 quedaria
    anulada por la puerta de atras y ninguna prueba de RLS se enteraria, porque
    las politicas estarian haciendo justo lo que se les pidio.

Entra solo en ./scripts/verificar-todo.sh por estar aqui y llamarse asi.
"""
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent

# Donde puede vivir cada cosa. Si la disposicion cambia, cambia aqui y se
# explica por que, en lugar de que la regla se erosione sin que nadie lo note.
SOLO_DATOS = ("api/src/datos",)
SOLO_AVISOS = ("api/src/configuracion/avisos.ts", "api/src/avisos", "avisos/src")
SOLO_ERRORES = ("api/src/http/errores.ts",)

IMPORTA_PG = re.compile(r"""(?:from|require\()\s*['"]pg(?:['"/])""")

# El cuerpo de error, construido a mano. Es por donde se escapa el mensaje de
# psql con la cadena de conexion, o el «Key (correo)=(...) already exists» que
# confirma que un correo esta registrado. Decision 4 de docs/arquitectura.md.
FORMATEA_ERROR = re.compile(r"""["']?error["']?\s*:\s*\{\s*["']?codigo""")

BLOQUE = re.compile(r"/\*.*?\*/", re.S)


def sin_comentarios(texto):
    """Quita los comentarios antes de buscar. Un comentario que EXPLICA una regla
    no es una infraccion: sin esto, la cabecera de servidor.ts que dice «este
    esquema no declara DATABASE_URL_AVISOS» se contaba como si la declarara.

    Solo se quitan los bloques y las lineas que son comentario entero. Un `//`
    al final de una linea de codigo se deja a proposito: cortar ahi truncaria
    cualquier linea que lleve una URL con «://» y podria esconder una
    infraccion de verdad mas a la derecha.
    """
    texto = BLOQUE.sub("", texto)
    lineas = []
    for linea in texto.split("\n"):
        limpia = linea.lstrip()
        if limpia.startswith("//") or limpia.startswith("*"):
            continue
        lineas.append(linea)
    return "\n".join(lineas)

fallos = []


def comprobar(condicion, bien, mal):
    print(f"  {'ok   ' if condicion else 'FALLA'} {bien if condicion else mal}")
    if not condicion:
        fallos.append(mal)


def fuentes():
    """Todos los .ts del proyecto, sin lo generado ni las dependencias."""
    for f in sorted(RAIZ.glob("**/*.ts")):
        rel = f.relative_to(RAIZ).as_posix()
        if "node_modules" in rel or "/dist/" in rel or rel.startswith("dist/"):
            continue
        yield rel, sin_comentarios(f.read_text(encoding="utf-8"))


def permitido(rel, permitidos):
    return any(rel == p or rel.startswith(f"{p}/") for p in permitidos)


def main() -> int:
    revisados = 0
    infractores_pg = []
    infractores_avisos = []
    infractores_error = []

    for rel, texto in fuentes():
        revisados += 1

        if IMPORTA_PG.search(texto) and not permitido(rel, SOLO_DATOS):
            infractores_pg.append(rel)

        if "DATABASE_URL_AVISOS" in texto and not permitido(rel, SOLO_AVISOS):
            infractores_avisos.append(rel)

        if FORMATEA_ERROR.search(texto) and not permitido(rel, SOLO_ERRORES):
            infractores_error.append(rel)

    comprobar(revisados > 0,
              f"se revisaron {revisados} fichero(s) de TypeScript",
              "no se encontro ningun .ts. ¿Cambio la disposicion del proyecto?")

    comprobar(not infractores_pg,
              f"solo {'/'.join(SOLO_DATOS)} conoce el pool de conexiones",
              f"estos ficheros importan «pg» y no estan en {'/'.join(SOLO_DATOS)}: "
              f"{', '.join(infractores_pg)}. El pool no se exporta y un repositorio recibe "
              f"un Tx; consultar fuera de una transaccion con contexto devuelve cero filas "
              f"sin dar error (decision 1 de docs/arquitectura.md)")

    comprobar(not infractores_avisos,
              "DATABASE_URL_AVISOS solo aparece donde corre el proceso de avisos",
              f"estos ficheros nombran DATABASE_URL_AVISOS fuera del modulo de avisos: "
              f"{', '.join(infractores_avisos)}. Ese rol lee las obligaciones de TODOS los "
              f"usuarios; en el proceso que atiende peticiones anula el aislamiento sin dar "
              f"un solo error (decision 2 de docs/arquitectura.md)")

    comprobar(not infractores_error,
              f"solo {'/'.join(SOLO_ERRORES)} da forma a una respuesta de error",
              f"estos ficheros construyen el cuerpo de un error a mano: "
              f"{', '.join(infractores_error)}. Por ahi se escapa el mensaje de psql con la "
              f"cadena de conexion, o el «Key (correo)=(...) already exists» que confirma que "
              f"un correo esta registrado. Lanzar un ErrorDeAplicacion y dejar que lo traduzca "
              f"un solo sitio (decision 4 de docs/arquitectura.md)")

    # El pool no se exporta: es lo que hace que no haya otra puerta a los datos.
    contexto = RAIZ / "api/src/datos/contexto.ts"
    if contexto.exists():
        codigo = sin_comentarios(contexto.read_text(encoding="utf-8"))
        comprobar(re.search(r"export\s+(const|let|var|function)\s+pool\b", codigo) is None
                  and "export { pool" not in codigo
                  and "export default pool" not in codigo,
                  "el pool de conexiones no se exporta",
                  "contexto.ts exporta el pool. Entonces cualquiera puede pedir una conexion "
                  "y consultar fuera de una transaccion con contexto, y las politicas RLS "
                  "comparan contra NULL: cero filas, sin error (decision 1)")

        comprobar("declare const marcaDeTransaccion: unique symbol" in codigo,
                  "el tipo Tx lleva una marca que no sale de contexto.ts",
                  "el tipo Tx ya no lleva la marca con simbolo unico: sin ella el compilador "
                  "deja fabricar un Tx a mano, y consultar sin contexto vuelve a depender de "
                  "la disciplina en lugar de ser imposible")

    # El esquema del servidor tiene que seguir sin declararla: es su criterio de
    # aceptacion en la tarea 2, no una consecuencia agradable.
    servidor = RAIZ / "api/src/configuracion/servidor.ts"
    if servidor.exists():
        texto = sin_comentarios(servidor.read_text(encoding="utf-8"))
        declaradas = re.search(r"const DECLARADAS = \[(.*?)\]", texto, re.S)
        comprobar(declaradas is not None,
                  "el esquema del servidor declara explicitamente sus variables",
                  "no se encontro la lista DECLARADAS en el esquema del servidor: sin una "
                  "lista explicita, del .env entra todo y con ello las URLs de los otros roles")
        if declaradas:
            lista = declaradas.group(1)
            for prohibida in ("DATABASE_URL_AVISOS", "DATABASE_URL_MIGRACIONES"):
                comprobar(prohibida not in lista,
                          f"el esquema del servidor no declara {prohibida}",
                          f"el esquema del servidor declara {prohibida}: ese rol no puede "
                          f"existir en el proceso que atiende peticiones")

    if fallos:
        print(f"\n  {len(fallos)} comprobacion(es) en rojo. El porque esta en docs/arquitectura.md")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
