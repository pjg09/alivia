#!/usr/bin/env python3
"""Comprueba que la configuracion se valida AL ARRANCAR y no despues.

    python3 scripts/verificar-configuracion.py

El criterio de la tarea 2 es que falte una variable obligatoria y el proceso
muera diciendo cual, en lugar de arrancar y fallar mas tarde en otro sitio.
Aqui se comprueba ejecutando el validador de verdad con entornos controlados,
no leyendo el codigo.

Tres cosas se comprueban que no son evidentes:

  - Se informan TODOS los problemas de una vez. Morir en el primero obliga a
    arrancar, leer, corregir y repetir tantas veces como variables falten.
  - `JWT_SECRETO` ausente genera uno; de plantilla, mata. Es lo unico que deja
    convivir la regla 7, el rechazo del valor de plantilla y la prohibicion de
    secretos en el repositorio. Decision 2 de docs/arquitectura.md.
  - El perfil del servidor NO lee `DATABASE_URL_AVISOS`, y del fichero .env solo
    toma las variables que declara. Ese rol ve las obligaciones de todos los
    usuarios; si el servidor pudiera construir ese pool, el aislamiento quedaria
    anulado sin que ninguna prueba de RLS se enterara.

Entra solo en ./scripts/verificar-todo.sh por estar aqui y llamarse asi.
"""
import os
import pathlib
import subprocess
import sys
import tempfile

RAIZ = pathlib.Path(__file__).resolve().parent.parent
COMPROBADOR = "api/src/configuracion/comprobar.ts"

URL_APP = "postgres://alivia_app:desarrollo@localhost:5434/alivia"
URL_AVISOS = "postgres://alivia_avisos:desarrollo@localhost:5434/alivia"
URL_PROPIETARIO = "postgres://alivia_propietario:desarrollo@localhost:5434/alivia"
SECRETO_BUENO = "z" * 40

fallos = []


def comprobar(condicion, bien, mal):
    print(f"  {'ok   ' if condicion else 'FALLA'} {bien if condicion else mal}")
    if not condicion:
        fallos.append(mal)


def correr(perfil, entorno, contenido_env=""):
    """Ejecuta el validador con un entorno y un .env controlados."""
    with tempfile.NamedTemporaryFile("w", suffix=".env", delete=False, encoding="utf-8") as f:
        f.write(contenido_env)
        ruta = f.name
    try:
        # Entorno minimo a proposito: sin PATH no se encuentra node, y sin
        # limpiar el resto las variables de quien ejecuta se colarian en la
        # prueba y la harian pasar o fallar por accidente.
        base = {"PATH": os.environ.get("PATH", ""), "HOME": os.environ.get("HOME", "")}
        r = subprocess.run(
            ["npx", "tsx", COMPROBADOR, perfil, ruta],
            cwd=RAIZ, capture_output=True, text=True, timeout=120,
            env={**base, **entorno},
        )
        return r.returncode, r.stdout + r.stderr
    finally:
        os.unlink(ruta)


def caso(titulo, perfil, entorno, env_file, espera_codigo, debe_decir=(), no_debe_decir=()):
    codigo, salida = correr(perfil, entorno, env_file)
    plano = " ".join(salida.split())

    comprobar(codigo == espera_codigo,
              f"{titulo}: sale con {codigo}",
              f"{titulo}: salio con {codigo} y se esperaba {espera_codigo}. Salida:\n"
              f"         {plano[:400]}")

    for trozo in debe_decir:
        comprobar(trozo in plano,
                  f"{titulo}: el mensaje menciona «{trozo}»",
                  f"{titulo}: el mensaje NO menciona «{trozo}», que es lo que hay que "
                  f"corregir. Dijo: {plano[:300]}")

    for trozo in no_debe_decir:
        comprobar(trozo not in plano,
                  f"{titulo}: el mensaje no menciona «{trozo}»",
                  f"{titulo}: el mensaje menciona «{trozo}» y no deberia. Dijo: {plano[:300]}")


def main() -> int:
    # --- Lo minimo valido ----------------------------------------------------
    caso("configuracion minima", "api", {"DATABASE_URL": URL_APP}, "", 0,
         debe_decir=["configuración válida", "alivia_app@localhost"])

    # --- Falta lo obligatorio, y lo dice ------------------------------------
    caso("sin DATABASE_URL", "api", {}, "", 1,
         debe_decir=["DATABASE_URL", "falta, y es obligatoria"])

    # --- Todos los problemas de una vez, no el primero -----------------------
    codigo, salida = correr("api", {"PUERTO": "no-es-un-numero", "FECHA_REFERENCIA": "2026-02-30"})
    plano = " ".join(salida.split())
    comprobar(codigo == 1 and all(v in plano for v in ("DATABASE_URL", "PUERTO", "FECHA_REFERENCIA")),
              "tres problemas a la vez se informan los tres",
              f"con tres variables mal, no se informaron las tres. Dijo: {plano[:400]}")

    # --- JWT_SECRETO: el unico caso con dos tratamientos --------------------
    caso("JWT_SECRETO ausente", "api", {"DATABASE_URL": URL_APP}, "", 0,
         debe_decir=["se generó uno aleatorio", "no sobrevivirán a un reinicio"])

    caso("JWT_SECRETO de plantilla", "api",
         {"DATABASE_URL": URL_APP, "JWT_SECRETO": "cambiar-en-cada-maquina"}, "", 1,
         debe_decir=["JWT_SECRETO", "valor de plantilla"])

    caso("JWT_SECRETO demasiado corto", "api",
         {"DATABASE_URL": URL_APP, "JWT_SECRETO": "corto"}, "", 1,
         debe_decir=["JWT_SECRETO", "al menos 32"])

    caso("JWT_SECRETO propio y suficiente", "api",
         {"DATABASE_URL": URL_APP, "JWT_SECRETO": SECRETO_BUENO}, "", 0,
         no_debe_decir=["se generó uno aleatorio"])

    # --- Regla 1: el rol equivocado se nota al arrancar ---------------------
    caso("el servidor con el rol propietario", "api", {"DATABASE_URL": URL_PROPIETARIO}, "", 1,
         debe_decir=["alivia_propietario", "alivia_app", "regla 1"])

    caso("avisos con el rol de la aplicacion", "avisos", {"DATABASE_URL_AVISOS": URL_APP}, "", 1,
         debe_decir=["alivia_app", "alivia_avisos"])

    # --- El limite entre los dos perfiles -----------------------------------
    # Con SOLO la URL de avisos, el servidor tiene que morir por falta de la
    # suya y no mencionar la de avisos para nada: no la conoce.
    caso("el servidor no lee la URL de avisos", "api", {"DATABASE_URL_AVISOS": URL_AVISOS}, "", 1,
         debe_decir=["DATABASE_URL"], no_debe_decir=["DATABASE_URL_AVISOS", "alivia_avisos"])

    # Del .env solo se toman las variables declaradas: un .env con la URL del
    # propietario no puede colarla en el proceso del servidor.
    caso("del .env solo entra lo declarado", "api", {},
         f"DATABASE_URL_MIGRACIONES={URL_PROPIETARIO}\nDATABASE_URL_AVISOS={URL_AVISOS}\n", 1,
         debe_decir=["DATABASE_URL", "falta"],
         no_debe_decir=["alivia_propietario", "DATABASE_URL_MIGRACIONES"])

    # --- El reloj inyectable, que sostiene toda la fase 4 -------------------
    caso("fecha de referencia valida", "api",
         {"DATABASE_URL": URL_APP, "FECHA_REFERENCIA": "2026-12-01"}, "", 0,
         debe_decir=["RELOJ INYECTADO", "2026-12-01"])

    caso("fecha de referencia con hora", "api",
         {"DATABASE_URL": URL_APP, "FECHA_REFERENCIA": "2026-12-01T00:00:00Z"}, "", 1,
         debe_decir=["FECHA_REFERENCIA", "fecha civil"])

    # --- El .env no hace falta para nada ------------------------------------
    codigo, salida = correr("api", {"DATABASE_URL": URL_APP}, "")
    comprobar(codigo == 0,
              "sin .env el servidor valida igual (regla 7)",
              "sin .env la configuracion no valida, y la regla 7 dice que el proyecto "
              "arranca sin el")

    if fallos:
        print(f"\n  {len(fallos)} comprobacion(es) en rojo.")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
