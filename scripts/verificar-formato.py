#!/usr/bin/env python3
"""Comprueba que el formateador corre igual en las cuatro maquinas.

    python3 scripts/verificar-formato.py

Que el codigo este formateado es lo de menos: lo caro es que cada maquina lo
formatee DISTINTO. Entonces guardar un fichero reescribe lineas que nadie
toco, cada envio arrastra ruido, y una revision deja de poder leerse porque el
diff es del formateador y no del cambio.

Eso pasa por tres vias, y las tres se comprueban aqui:

  - La version del formateador no esta clavada. Con `^`, una maquina instala
    2.6 y otra 2.5, y cambian las reglas de salto de linea.
  - La indentacion esta declarada en dos sitios --.editorconfig y la
    configuracion del formateador-- y divergen.
  - Los finales de linea. Alguien en Windows convierte un fichero a CRLF y el
    diff siguiente toca cada linea de cada fichero que abrio.

Entra solo en ./scripts/verificar-todo.sh por estar aqui y llamarse asi.
"""
import json
import pathlib
import re
import subprocess
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
FORMATEADOR = "@biomejs/biome"

fallos = []


def comprobar(condicion, bien, mal):
    print(f"  {'ok   ' if condicion else 'FALLA'} {bien if condicion else mal}")
    if not condicion:
        fallos.append(mal)


def leer(ruta):
    f = RAIZ / ruta
    return f.read_text(encoding="utf-8") if f.exists() else None


def main() -> int:
    paquete = json.loads((RAIZ / "package.json").read_text(encoding="utf-8"))
    version = (paquete.get("devDependencies") or {}).get(FORMATEADOR)

    comprobar(version is not None,
              f"{FORMATEADOR} es una dependencia del repositorio",
              f"{FORMATEADOR} no esta en devDependencies: el formateador tiene que venir "
              f"del repositorio y no de lo que cada quien tenga instalado o de un "
              f"complemento del editor, que trae su propia version")

    if version:
        # Clavada. Con un rango, dos maquinas formatean distinto el mismo dia.
        comprobar(re.fullmatch(r"\d+\.\d+\.\d+", version) is not None,
                  f"la version del formateador esta clavada: {version}",
                  f"la version del formateador es «{version}», un rango. Una maquina "
                  f"instalara una version distinta y formateara distinto. Fijarla exacta: "
                  f"npm install -D --save-exact {FORMATEADOR}")

    # --- Una sola fuente para la indentacion ---------------------------------
    config = leer("biome.json")
    comprobar(config is not None, "existe biome.json", "no existe biome.json")

    if config:
        c = json.loads(config)
        comprobar((c.get("formatter") or {}).get("useEditorconfig") is True,
                  "el formateador lee .editorconfig, asi que la indentacion vive en un solo sitio",
                  "biome.json no tiene formatter.useEditorconfig: true. Sin eso, la "
                  "indentacion queda declarada dos veces --aqui y en .editorconfig-- y los "
                  "editores de las cuatro maquinas pelean con el formateador")

        # El esquema que valida el editor y el binario que formatea, la misma version.
        esquema = c.get("$schema", "")
        m = re.search(r"/schemas/(\d+\.\d+\.\d+)/", esquema)
        comprobar(m is not None and m.group(1) == version,
                  f"el $schema de biome.json apunta a la version instalada ({version})",
                  f"el $schema de biome.json apunta a {m.group(1) if m else '?'} y la version "
                  f"instalada es {version}: el editor valida contra unas reglas y el binario "
                  f"aplica otras")

    # --- Finales de linea ----------------------------------------------------
    editorconfig = leer(".editorconfig")
    comprobar(editorconfig is not None, "existe .editorconfig", "no existe .editorconfig")
    if editorconfig:
        for clave, valor in (("end_of_line", "lf"), ("insert_final_newline", "true"),
                             ("indent_style", "space")):
            comprobar(re.search(rf"^{clave}\s*=\s*{valor}\s*$", editorconfig, re.M | re.I) is not None,
                      f".editorconfig declara {clave} = {valor}",
                      f".editorconfig no declara «{clave} = {valor}»")

    atributos = leer(".gitattributes")
    comprobar(atributos is not None and "eol=lf" in atributos,
              ".gitattributes fija los finales de linea en LF",
              ".gitattributes no fija «eol=lf»: quien trabaje en Windows convertira "
              "ficheros enteros a CRLF y el diff siguiente tocara cada linea")

    # --- Y el formateador, corriendo -----------------------------------------
    try:
        r = subprocess.run(["npx", "biome", "check"], cwd=RAIZ,
                           capture_output=True, text=True, timeout=180)
    except FileNotFoundError:
        comprobar(False, "", "no se pudo ejecutar npx: ¿estan instaladas las dependencias?")
        return 1
    except subprocess.TimeoutExpired:
        comprobar(False, "", "el formateador no respondio en 180s")
        return 1

    if r.returncode == 0:
        resumen = next((l for l in r.stdout.splitlines() if l.startswith("Checked")), "sin resumen")
        comprobar(True, f"el formateador no tiene nada que decir — {resumen}", "")
    else:
        salida = (r.stdout + r.stderr).strip().splitlines()
        comprobar(False, "", "el formateador encontro trabajo pendiente. Corregir con "
                             "`npm run formato`:\n         "
                             + "\n         ".join(salida[-12:]))

    if fallos:
        print(f"\n  {len(fallos)} comprobacion(es) en rojo.")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
