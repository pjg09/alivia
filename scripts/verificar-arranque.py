#!/usr/bin/env python3
"""Comprueba que el ambiente se levanta con un solo comando y sigue completo.

    npm run arrancar

Ese comando es el contrato del proyecto: en una maquina recien clonada tiene
que dejar Alivia utilizable, sin pasos manuales. Un contrato que nadie
comprueba se rompe el dia que alguien anade una pieza y se olvida del compose,
y no se nota hasta que un companero clona el repositorio y no le arranca.

Este script no arranca nada: comprueba el fichero. El arranque de verdad lo
hace la integracion continua, que usa este mismo compose y no otra cosa.

Entra solo en ./scripts/verificar-todo.sh por estar aqui y llamarse asi.
El contrato completo, con el porque de cada regla, esta en docs/ambiente.md.

    python3 scripts/verificar-arranque.py
"""
import json
import pathlib
import re
import subprocess
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
COMPOSE = RAIZ / "docker-compose.yml"

# Roles de base de datos que un servicio puede declarar en la etiqueta
# alivia.rol-bd. Los dos primeros ven todos los datos de todos los usuarios y
# por eso no puede tenerlos nada que atienda peticiones (regla 1 de CLAUDE.md).
ROLES_SIN_RLS = {"motor", "propietario"}
ROLES_VALIDOS = ROLES_SIN_RLS | {"app", "avisos"}

# Directorios que nunca son un componente ejecutable del producto.
NO_COMPONENTES = {"db", "docs", "scripts", "node_modules", ".git", ".github"}

# Donde puede esconderse una copia de un puerto que luego deriva.
FICHEROS_CON_PUERTOS = [
    ".env.example",
    "README.md",
    "CLAUDE.md",
    "CONTRIBUTING.md",
    "db/aplicar.sh",
    "scripts/verificar-todo.sh",
    "scripts/verificar-mailpit.py",
    "scripts/verificar-arranque.py",
    ".github/workflows/release.yml",
]

fallos = []


def comprobar(condicion, bien, mal):
    print(f"  {'ok   ' if condicion else 'FALLA'} {bien if condicion else mal}")
    if not condicion:
        fallos.append(mal)


def main() -> int:
    if not COMPOSE.exists():
        print("  FALLA no existe docker-compose.yml, que es el ambiente entero")
        return 1

    crudo = COMPOSE.read_text(encoding="utf-8")

    # El compose lo lee docker, no un analizador de YAML propio: asi esta
    # comprobacion falla por lo mismo que fallaria el arranque, y de paso no
    # anade una dependencia de Python que la CI tendria que instalar.
    #
    # --env-file /dev/null para leer los valores por defecto del fichero y no
    # los del .env de quien lo ejecute.
    try:
        r = subprocess.run(
            ["docker", "compose", "-f", str(COMPOSE), "--env-file", "/dev/null",
             "config", "--format", "json"],
            cwd=RAIZ, capture_output=True, text=True, timeout=120,
        )
    except FileNotFoundError:
        print("  FALLA docker no esta instalado, y el ambiente del proyecto es docker")
        return 1
    except subprocess.TimeoutExpired:
        print("  FALLA docker compose config no respondio en 120s")
        return 1

    if r.returncode != 0:
        print(f"  FALLA docker rechaza el compose, asi que 'up' tampoco funcionaria:\n"
              f"        {r.stderr.strip()[:400]}")
        return 1
    comprobar(True, "docker acepta el compose", "")
    servicios = json.loads(r.stdout).get("services") or {}

    # --- Las piezas minimas del ambiente -------------------------------------
    for nombre in ("postgres", "mailpit", "migraciones"):
        comprobar(nombre in servicios,
                  f"el compose levanta «{nombre}»",
                  f"el compose no declara «{nombre}»: 'up' ya no deja el proyecto utilizable")

    # --- Cada servicio dice como se sabe que esta listo -----------------------
    # Sin esto, --wait devuelve antes de tiempo y la CI corre contra un
    # servicio a medio arrancar, que falla de forma intermitente.
    efimeros = []
    for nombre, s in servicios.items():
        efimero = str((s.get("labels") or {}).get("alivia.efimero", "")).lower() == "true"
        if efimero:
            efimeros.append(nombre)
        comprobar(bool(s.get("healthcheck")) or efimero,
                  f"«{nombre}» declara cuando esta listo",
                  f"«{nombre}» no tiene healthcheck ni la etiqueta alivia.efimero: "
                  f"--wait no puede saber si arranco (ver docs/ambiente.md)")
        if efimero:
            comprobar(str(s.get("restart", "")) == "no",
                      f"«{nombre}» es efimero y no se reinicia en bucle",
                      f"«{nombre}» es efimero pero no declara restart: \"no\"")

    # --- Un healthcheck que miente es peor que no tenerlo --------------------
    # Durante la inicializacion, postgres levanta un servidor temporal que
    # escucha solo en el socket unix. `pg_isready` sin -h lo encuentra y declara
    # la base sana antes de que acepte conexiones TCP, y lo que dependa de ella
    # arranca contra un puerto cerrado.
    for nombre, s in servicios.items():
        prueba = " ".join(str(x) for x in ((s.get("healthcheck") or {}).get("test") or []))
        if "pg_isready" not in prueba:
            continue
        comprobar("-h " in prueba,
                  f"el healthcheck de «{nombre}» comprueba postgres por TCP",
                  f"el healthcheck de «{nombre}» usa pg_isready sin -h: pasa contra el "
                  f"servidor temporal de la inicializacion y declara la base lista "
                  f"antes de que acepte conexiones TCP")

    # --- Regla 1 de CLAUDE.md, aplicada al ambiente ---------------------------
    for nombre, s in servicios.items():
        etiquetas = s.get("labels") or {}
        rol = etiquetas.get("alivia.rol-bd")
        texto = json.dumps(s, ensure_ascii=False)
        toca_bd = "alivia_propietario" in texto or "alivia_app" in texto \
            or "alivia_avisos" in texto or "POSTGRES_USER" in texto

        if not toca_bd:
            continue

        comprobar(rol in ROLES_VALIDOS,
                  f"«{nombre}» declara con que rol de base de datos corre: {rol}",
                  f"«{nombre}» usa la base de datos sin declarar alivia.rol-bd "
                  f"(uno de {sorted(ROLES_VALIDOS)})")

        if "alivia_propietario" in texto:
            comprobar(rol in ROLES_SIN_RLS,
                      f"«{nombre}» usa el propietario y lo declara",
                      f"«{nombre}» conecta como alivia_propietario declarandose «{rol}»: "
                      f"el propietario ignora RLS por completo (regla 1 de CLAUDE.md)")

        # Un servicio que se construye desde el repositorio atiende peticiones.
        # Ninguno de esos puede saltarse RLS, por mucho que lo declare.
        if s.get("build"):
            comprobar(rol not in ROLES_SIN_RLS,
                      f"«{nombre}» se construye del repositorio y esta sujeto a RLS",
                      f"«{nombre}» se construye del repositorio y corre como «{rol}»: "
                      f"eso deja a un usuario viendo los datos de otro, en silencio "
                      f"y sin un solo error (regla 1 de CLAUDE.md)")

    # --- Lo que existe en el repositorio, existe en el compose ---------------
    # Esta es la comprobacion por la que este fichero existe: el dia que
    # aparezca api/ o web/, el compose tiene que levantarlos o esto se pone rojo.
    # docker resuelve build.context a ruta absoluta, asi que se compara por el
    # directorio al que apunta y no por el texto escrito en el fichero.
    construidos = set()
    for s in servicios.values():
        b = s.get("build")
        contexto = b if isinstance(b, str) else (b or {}).get("context")
        if not contexto:
            continue
        ruta = pathlib.Path(contexto)
        if not ruta.is_absolute():
            ruta = RAIZ / ruta
        try:
            construidos.add(ruta.resolve().relative_to(RAIZ).as_posix())
        except ValueError:
            construidos.add(ruta.resolve().as_posix())   # fuera del repositorio

    for d in sorted(p for p in RAIZ.iterdir() if p.is_dir()):
        if d.name in NO_COMPONENTES or d.name.startswith("."):
            continue
        if not ((d / "package.json").exists() or (d / "Dockerfile").exists()):
            continue
        comprobar(d.name in construidos,
                  f"«{d.name}/» es un componente y el compose lo levanta",
                  f"existe «{d.name}/» y ningun servicio del compose lo construye: "
                  f"quien clone el repositorio no tendra esa pieza corriendo "
                  f"(ver docs/ambiente.md)")

    # La disposicion decidida es api/ y web/ (decision 0 de docs/arquitectura.md),
    # pero la regla no puede depender de que se respete: un servidor puesto en la
    # RAIZ del repositorio no lo detectaba el bucle de arriba, y la regla 7 se
    # quedaba en letra muerta justo en la tarea 1. Comprobado: con src/datos/ y un
    # Dockerfile en la raiz, este script devolvia 0.
    if (RAIZ / "Dockerfile").exists() or (RAIZ / "src").is_dir():
        que = "Dockerfile" if (RAIZ / "Dockerfile").exists() else "src/"
        comprobar("." in construidos,
                  f"hay un componente en la raiz ({que}) y el compose lo construye",
                  f"hay un componente en la raiz del repositorio ({que}) y ningun "
                  f"servicio del compose lo construye con «build: .». La disposicion "
                  f"decidida es api/ y web/: ver la decision 0 de docs/arquitectura.md")

    for df in sorted(RAIZ.glob("*/Dockerfile")):
        if df.parent.name in NO_COMPONENTES:
            continue
        comprobar(df.parent.name in construidos,
                  f"«{df.parent.name}/Dockerfile» lo usa un servicio",
                  f"«{df.parent.name}/Dockerfile» no lo construye ningun servicio: "
                  f"una imagen que nadie levanta no es parte del ambiente")

    # --- Toda variable del compose esta documentada --------------------------
    ejemplo = (RAIZ / ".env.example")
    texto_ejemplo = ejemplo.read_text(encoding="utf-8") if ejemplo.exists() else ""
    for var in sorted(set(re.findall(r"\$\{([A-Z_][A-Z0-9_]*)", crudo))):
        comprobar(re.search(rf"^#?\s*{var}=", texto_ejemplo, re.M) is not None,
                  f"{var} esta documentada en .env.example",
                  f"el compose lee {var} y .env.example no la menciona: "
                  f"nadie va a adivinar que existe")

    # --- Un solo sitio decide los puertos ------------------------------------
    # release.yml declaraba 5432 y .env.example 5434: dos copias de la misma
    # verdad que ya habian divergido. Cualquier localhost:<puerto> del proyecto
    # tiene que ser un puerto que el compose publique.
    publicados = {}
    for linea in re.findall(r'^\s*-\s*"([^"]+:\d+)"', crudo, re.M):
        m = re.match(r"\$\{([A-Z_]+):-(\d+)\}:(\d+)$", linea)
        comprobar(m is not None,
                  f"el puerto {linea} se puede mover sin editar el compose",
                  f"el puerto {linea} esta fijo en el compose: en una maquina donde ese "
                  f"puerto este ocupado, 'up' falla y no hay forma de moverlo")
        if m:
            publicados[int(m.group(2))] = m.group(1)
    comprobar(len(publicados) >= 3,
              f"el compose publica {len(publicados)} puertos, todos movibles",
              f"solo se reconocieron {len(publicados)} puertos publicados: "
              f"faltan los de postgres, SMTP y Mailpit")

    for ruta in FICHEROS_CON_PUERTOS:
        f = RAIZ / ruta
        if not f.exists():
            continue
        for puerto in sorted(set(int(x) for x in re.findall(
                r"(?:localhost|127\.0\.0\.1):(\d+)", f.read_text(encoding="utf-8")))):
            comprobar(puerto in publicados,
                      f"{ruta} usa el puerto {puerto}, el mismo que publica el compose",
                      f"{ruta} apunta a localhost:{puerto} y el compose no publica ese "
                      f"puerto (publica {sorted(publicados)}): una de las dos copias derivo")

    # --- La integracion continua arranca con este compose, no con otra cosa --
    flujo = RAIZ / ".github/workflows/release.yml"
    if flujo.exists():
        t = flujo.read_text(encoding="utf-8")
        comprobar(not re.search(r"^\s{4,}services:", t, re.M),
                  "la CI no monta un ambiente paralelo al del compose",
                  "la CI declara sus propios 'services:': eso es un segundo ambiente "
                  "que deriva del compose, que es justo lo que ya paso")

    # --- El arranque es uno, y esta escrito igual en todas partes -------------
    # `up --wait` espera a que los servicios esten sanos O CORRIENDO, asi que un
    # servicio efimero le vale con haber arrancado: devuelve antes de que
    # termine. Comprobado con un efimero de 12s, devolvio 0 a los 6. Por eso el
    # arranque tiene que esperar explicitamente a cada efimero, y por eso este
    # script deriva el comando del compose en vez de confiar en lo que se
    # escribio a mano en cada sitio.
    arranque = "docker compose up -d --wait" + "".join(
        f" && docker compose wait {n}" for n in sorted(efimeros))
    print(f"  ---   arranque derivado del compose: {arranque}")

    lugares = {
        "README.md": "README.md",
        "CLAUDE.md": "CLAUDE.md",
        "docs/ambiente.md": "docs/ambiente.md",
        ".github/workflows/release.yml": ".github/workflows/release.yml",
        "CONTRIBUTING.md": "CONTRIBUTING.md",
        "package.json": "package.json",
    }
    for etiqueta, ruta in lugares.items():
        f = RAIZ / ruta
        comprobar(f.exists() and arranque in f.read_text(encoding="utf-8"),
                  f"{etiqueta} documenta el arranque completo",
                  f"{etiqueta} no contiene «{arranque}»: un arranque a medias deja "
                  f"las pruebas corriendo contra una base a medio poblar")

    if fallos:
        print(f"\n  {len(fallos)} comprobacion(es) en rojo. El contrato del ambiente "
              f"esta en docs/ambiente.md")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
