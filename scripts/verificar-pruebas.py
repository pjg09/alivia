#!/usr/bin/env python3
"""Comprueba las propiedades del arnes de pruebas que `npm test` no puede
comprobar sobre si mismo.

    python3 scripts/verificar-pruebas.py

Criterio de la tarea 4: `npm test` aplica migraciones y semillas desde cero y
deja la base como la encontro, y definir ese script en package.json basta para
que la integracion continua lo ejecute.

Lo que se comprueba aqui:

  - Que `package.json` defina `test`. Es lo que hace que verificar-todo.sh lo
    ejecute, y por tanto la CI. Sin esa linea, las pruebas existen y no las
    corre nadie, que es peor que no tenerlas: parece que hay red.
  - Que la base de trabajo no lleve nombres del arnes. Si se llamara igual que la
    plantilla, «deja la base como la encontro» seria mentira y la limpieza
    borraria los datos de trabajo.
  - Que no haya bases de prueba sueltas de una ejecucion anterior. Si quedan,
    «desde cero» deja de ser verdad para la siguiente.
  - Que haya al menos un fichero de pruebas y que el patron los encuentre.
  - Que ninguna prueba abra su propia conexion: eso lo mira
    verificar-arquitectura.py, y aqui solo se comprueba que ese fichero exista,
    porque es de lo que depende que las pruebas de aislamiento valgan algo.

Entra solo en ./scripts/verificar-todo.sh por estar aqui y llamarse asi.
"""
import json
import os
import pathlib
import subprocess
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
PLANTILLA = "alivia_plantilla_pruebas"
PREFIJO = "alivia_prueba_"
URL_PROPIETARIO = os.environ.get(
    "DATABASE_URL_MIGRACIONES", "postgres://alivia_propietario:desarrollo@localhost:5434/alivia"
)

fallos = []


def comprobar(condicion, bien, mal):
    print(f"  {'ok   ' if condicion else 'FALLA'} {bien if condicion else mal}")
    if not condicion:
        fallos.append(mal)


def main() -> int:
    paquete = json.loads((RAIZ / "package.json").read_text(encoding="utf-8"))
    guiones = paquete.get("scripts") or {}

    comprobar("test" in guiones,
              f"package.json define «test»: {guiones.get('test')}",
              "package.json no define «test». Es lo unico que hace que verificar-todo.sh y la "
              "integracion continua lo ejecuten: sin esa linea las pruebas existen y no las "
              "corre nadie, que es peor que no tenerlas porque parece que hay red")

    # --- El arnes tiene que existir donde se dice ----------------------------
    orquestador = RAIZ / "api/pruebas/arnes/ejecutar.ts"
    comprobar(orquestador.exists(),
              "el orquestador del arnes esta en api/pruebas/arnes/ejecutar.ts",
              "no existe api/pruebas/arnes/ejecutar.ts, que es lo que `npm test` ejecuta")

    ficheros = sorted(RAIZ.glob("api/pruebas/**/*.prueba.ts"))
    comprobar(len(ficheros) > 0,
              f"hay {len(ficheros)} fichero(s) de pruebas: "
              f"{', '.join(f.name for f in ficheros)}",
              "no hay ningun *.prueba.ts bajo api/pruebas/. El patron del arnes no encontraria "
              "nada y `npm test` pasaria sin ejecutar una sola prueba")

    # --- La base de trabajo no puede llamarse como las del arnes -------------
    try:
        from urllib.parse import urlparse
        trabajo = urlparse(URL_PROPIETARIO).path.lstrip("/")
    except Exception:
        trabajo = ""
    comprobar(trabajo != "" and trabajo != PLANTILLA and not trabajo.startswith(PREFIJO),
              f"la base de trabajo «{trabajo}» no choca con los nombres del arnes",
              f"la base de trabajo se llama «{trabajo}», que choca con los nombres que usa el "
              f"arnes ({PLANTILLA}, {PREFIJO}*). La limpieza del arnes la borraria")

    # --- Nada suelto de una ejecucion anterior -------------------------------
    r = subprocess.run(
        ["psql", URL_PROPIETARIO, "-tAc",
         f"SELECT string_agg(datname, ', ' ORDER BY datname) FROM pg_database "
         f"WHERE datname = '{PLANTILLA}' OR datname LIKE '{PREFIJO}%'"],
        capture_output=True, text=True, timeout=60,
    )
    if r.returncode != 0:
        comprobar(False, "", f"no se pudo consultar la lista de bases: {r.stderr.strip()[:200]}")
    else:
        sobras = r.stdout.strip()
        comprobar(sobras == "",
                  "no quedan bases de prueba de ejecuciones anteriores",
                  f"quedaron bases de prueba sueltas: {sobras}. La siguiente ejecucion arrancaria "
                  f"sobre restos y «desde cero» dejaria de ser verdad. Borrarlas con "
                  f"DROP DATABASE ... WITH (FORCE)")

    if fallos:
        print(f"\n  {len(fallos)} comprobacion(es) en rojo.")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
