#!/usr/bin/env python3
"""Comprueba el contrato de la capa de acceso a datos contra la base real.

    python3 scripts/verificar-datos.py

Criterio de la tarea 3: toda consulta de datos de usuario pasa por `conUsuario()`,
e intentar consultar fuera de una transaccion con contexto es imposible por
construccion y no por disciplina.

«Por construccion» tiene dos mitades, y hacen falta las dos:

  - El tipo. `Tx` lleva una marca con un simbolo que no sale de contexto.ts, asi
    que el compilador rechaza fabricar uno. Eso se comprueba aqui compilando un
    fichero que lo intenta.
  - El pool. Se puede forzar el TIPO con una conversion, pero no se puede
    obtener una CONEXION: importar `pg` fuera de api/src/datos lo prohibe
    scripts/verificar-arquitectura.py. Una cosa sin la otra no basta.

Y luego el comportamiento, contra postgres de verdad: que el contexto llegue,
que se deshaga al cerrar --si no, la conexion vuelve al pool contaminada y la
siguiente transaccion consulta con el usuario de otro--, que anidar falle, que
un Tx guardado no sirva despues, y que una fecha civil vuelva como cadena.

Entra solo en ./scripts/verificar-todo.sh por estar aqui y llamarse asi.
"""
import json
import os
import pathlib
import subprocess
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
URL_PROPIETARIO = os.environ.get(
    "DATABASE_URL_MIGRACIONES", "postgres://alivia_propietario:desarrollo@localhost:5434/alivia"
)

fallos = []


def comprobar(condicion, bien, mal):
    print(f"  {'ok   ' if condicion else 'FALLA'} {bien if condicion else mal}")
    if not condicion:
        fallos.append(mal)


def psql(sql):
    r = subprocess.run(["psql", URL_PROPIETARIO, "-tAc", sql],
                       capture_output=True, text=True, timeout=60)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def main() -> int:
    # --- Los usuarios de prueba, que es contra lo que se mide el aislamiento --
    codigo, salida, error = psql(
        "SELECT (SELECT id FROM usuario WHERE correo='ana@prueba.local') || ' ' || "
        "(SELECT id FROM usuario WHERE correo='beto@prueba.local')"
    )
    if codigo != 0 or " " not in salida:
        comprobar(False, "", f"no se pudieron leer los usuarios de prueba: {error or salida}. "
                             f"¿Falta `./db/aplicar.sh --semillas`?")
        return 1
    ana, beto = salida.split(" ")
    comprobar(True, f"usuarios de prueba: Ana {ana[:8]}…, Beto {beto[:8]}…", "")

    # --- El tipo: el compilador tiene que rechazar un Tx fabricado -----------
    intento = RAIZ / "api/src/datos/_intento_de_falsificacion.ts"
    intento.write_text(
        'import type { Tx } from "./contexto.js";\n'
        "// Un Tx a mano, sin la marca. Esto NO puede compilar.\n"
        "export const falso: Tx = { consultar: async () => [] };\n",
        encoding="utf-8",
    )
    try:
        r = subprocess.run(["npm", "run", "tipos", "--silent"], cwd=RAIZ,
                           capture_output=True, text=True, timeout=180)
        comprobar(r.returncode != 0 and "marcaDeTransaccion" in (r.stdout + r.stderr),
                  "el compilador rechaza fabricar un Tx sin pasar por conUsuario()",
                  "el compilador ACEPTA un Tx fabricado a mano: entonces consultar sin "
                  "contexto no es imposible por construccion, solo por disciplina. "
                  f"Salida: {(r.stdout + r.stderr)[-300:]}")
    finally:
        intento.unlink(missing_ok=True)

    # --- Y que el proyecto siga compilando sin ese fichero -------------------
    r = subprocess.run(["npm", "run", "tipos", "--silent"], cwd=RAIZ,
                       capture_output=True, text=True, timeout=180)
    comprobar(r.returncode == 0,
              "el proyecto compila",
              f"el proyecto no compila: {(r.stdout + r.stderr)[-400:]}")

    # --- El comportamiento, contra la base -----------------------------------
    entorno = {**os.environ, "ID_ANA": ana, "ID_BETO": beto}
    r = subprocess.run(["npx", "tsx", "api/src/datos/comprobar.ts"], cwd=RAIZ,
                       capture_output=True, text=True, timeout=180, env=entorno)

    casos = [json.loads(l) for l in r.stdout.splitlines() if l.startswith("{")]
    comprobar(len(casos) >= 10,
              f"se ejercitaron {len(casos)} casos contra la base de datos",
              f"solo llegaron {len(casos)} casos. Salida: {(r.stdout + r.stderr)[-500:]}")

    for caso in casos:
        comprobar(caso["ok"], f"{caso['caso']} — {caso['detalle']}",
                  f"{caso['caso']}: {caso['detalle']}")

    if fallos:
        print(f"\n  {len(fallos)} comprobacion(es) en rojo.")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
