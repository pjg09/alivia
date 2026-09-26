#!/usr/bin/env python3
"""Comprueba que un error no controlado NO filtra nada.

    python3 scripts/verificar-errores.py

Criterio de la tarea 6: un error no controlado devuelve un codigo y un cuerpo
coherentes, y nunca filtra detalles internos ni datos de usuario.

«Nunca» es una palabra que solo vale si alguien la comprueba, asi que aqui se
pasan por la frontera cosas que un servidor real lanza --el mensaje de psql con
la cadena de conexion, el «Key (correo)=(...) already exists» que confirma que
un correo esta registrado, un throw de texto, un objeto con un hash de
contrasena-- y se afirma que de lo que sale no queda rastro de nada de eso.

La frontera es una funcion pura, asi que esto no necesita un servidor
levantado. La tarea 7 la conectara a Express sin tocarla.

Entra solo en ./scripts/verificar-todo.sh por estar aqui y llamarse asi.
"""
import json
import os
import pathlib
import re
import subprocess
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
COMPROBADOR = "api/src/http/comprobar.ts"

# Nada de esto puede aparecer NUNCA en un cuerpo de respuesta.
PROHIBIDO = [
    ("postgres://", "una cadena de conexion"),
    ("alivia_propietario", "el rol que ignora RLS"),
    ("alivia_app", "el rol de la aplicacion"),
    ("desarrollo", "la contrasena de la base de datos"),
    ("ejemplo.com", "el correo de una persona"),
    ("argon2", "un hash de contrasena"),
    ("contrasena_hash", "el nombre de la columna de la contrasena"),
    ("23505", "un codigo de error de postgres"),
    ("unique constraint", "el texto de una restriccion de la base"),
    ("obligacion_usuario", "el nombre de una tabla"),
    ("usuario_id", "el nombre de una columna interna"),
    ("at Object", "una pila de llamadas"),
    ("TypeError", "el tipo interno del fallo"),
    (".ts:", "una ruta de fichero fuente"),
]

ESTADOS_PERMITIDOS = {400, 401, 403, 404, 409, 500}

fallos = []


def comprobar(condicion, bien, mal):
    print(f"  {'ok   ' if condicion else 'FALLA'} {bien if condicion else mal}")
    if not condicion:
        fallos.append(mal)


def correr(*argumentos):
    base = {"PATH": os.environ.get("PATH", ""), "HOME": os.environ.get("HOME", "")}
    r = subprocess.run(["npx", "tsx", COMPROBADOR, *argumentos], cwd=RAIZ,
                       capture_output=True, text=True, timeout=120, env=base)
    if r.returncode != 0:
        comprobar(False, "", f"el comprobador de errores fallo: {(r.stdout + r.stderr)[:400]}")
        return []
    return [json.loads(l) for l in r.stdout.splitlines() if l.startswith("{")]


def main() -> int:
    casos = correr("fugas")
    comprobar(len(casos) >= 8,
              f"se pasaron {len(casos)} valores hostiles por la frontera",
              f"solo llegaron {len(casos)} casos: el comprobador no esta produciendo nada")

    for caso in casos:
        nombre = caso["nombre"]
        cuerpo = caso["cuerpo"]
        crudo = json.dumps(cuerpo, ensure_ascii=False)

        # --- La forma es siempre la misma ------------------------------------
        comprobar(
            set(cuerpo.keys()) == {"error"}
            and set(cuerpo["error"].keys()) == {"codigo", "mensaje", "identificador"},
            f"«{nombre}»: el cuerpo tiene la forma del contrato",
            f"«{nombre}»: el cuerpo no es {{error:{{codigo,mensaje,identificador}}}} sino "
            f"{crudo[:200]}",
        )

        comprobar(caso["estado"] in ESTADOS_PERMITIDOS,
                  f"«{nombre}»: responde {caso['estado']}",
                  f"«{nombre}»: responde {caso['estado']}, que no es uno de "
                  f"{sorted(ESTADOS_PERMITIDOS)} (decision 4 de docs/arquitectura.md)")

        codigo = cuerpo.get("error", {}).get("codigo", "")
        comprobar(re.fullmatch(r"[A-Z][A-Z0-9_]*", codigo) is not None,
                  f"«{nombre}»: el codigo «{codigo}» es estable y legible por la interfaz",
                  f"«{nombre}»: el codigo «{codigo}» no esta en MAYUSCULAS_CON_GUION_BAJO, "
                  f"asi que la interfaz no puede decidir contra el")

        # --- Y no se filtra nada ---------------------------------------------
        for aguja, que_es in PROHIBIDO:
            comprobar(aguja.lower() not in crudo.lower(),
                      f"«{nombre}»: no filtra {que_es}",
                      f"«{nombre}»: el cuerpo contiene «{aguja}» --{que_es}-- y eso no puede "
                      f"salir del servidor. Cuerpo: {crudo[:300]}")

    # --- Lo desconocido siempre es 500 y siempre el mismo codigo ------------
    desconocidos = [c for c in casos if c["nombre"] in
                    ("un throw de texto con un correo", "un objeto suelto", "null", "undefined")]
    comprobar(len(desconocidos) == 4 and all(
                  c["estado"] == 500 and c["cuerpo"]["error"]["codigo"] == "ERROR_INTERNO"
                  for c in desconocidos),
              "lo que el servidor no reconoce sale como 500 ERROR_INTERNO, sin describirse",
              "algo que el servidor no reconoce no salio como 500 ERROR_INTERNO: describir un "
              "fallo desconocido le cuenta a cualquiera como esta hecho el servidor")

    # --- El identificador une la respuesta con el registro ------------------
    comprobar(all(c["cuerpo"]["error"]["identificador"] for c in casos),
              "cada error lleva un identificador para cruzarlo con el registro",
              "hay errores sin identificador: sin el, nadie puede decir cual de las mil "
              "lineas del registro es la suya")

    # --- El catalogo, que es lo que consume la interfaz --------------------
    base = {"PATH": os.environ.get("PATH", ""), "HOME": os.environ.get("HOME", "")}
    r = subprocess.run(["npx", "tsx", COMPROBADOR], cwd=RAIZ, capture_output=True,
                       text=True, timeout=120, env=base)
    comprobar(r.returncode == 0 and "ERROR_INTERNO" in r.stdout,
              "el catalogo de codigos se puede consultar con `npm run errores`",
              "`npm run errores` no imprime el catalogo: la interfaz necesita la lista de "
              "codigos para decidir sin leer los textos")

    if fallos:
        print(f"\n  {len(fallos)} comprobacion(es) en rojo.")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
