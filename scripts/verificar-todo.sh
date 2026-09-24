#!/usr/bin/env bash
#
# Corre TODAS las pruebas del proyecto y falla si alguna no pasa.
#
#   ./scripts/verificar-todo.sh              contra el ambiente local
#   ./scripts/verificar-todo.sh --reiniciar  recreando el esquema desde cero
#
# No hay una lista de pruebas que mantener: se descubren por dónde están.
#
#   db/pruebas/*.sql          pruebas de base de datos
#   scripts/verificar-*.py    verificadores del proyecto
#   npm test                  pruebas de la aplicación, si package.json lo define
#
# Añadir una prueba nueva en cualquiera de esos sitios la mete en la
# integración continua sin tocar el flujo de trabajo ni este script.
#
# Una prueba SQL corre como alivia_app salvo que declare otra cosa en sus
# primeras líneas:
#
#   -- @rol: propietario
#
set -uo pipefail

cd "$(dirname "$0")/.."
# El .env aporta valores por defecto; NO pisa lo que ya venga del entorno.
# Sin esto, un .env montado dentro de un contenedor sobrescribe la URL que le
# pasa docker compose --cuyo anfitrion es «postgres»-- por la de «localhost»,
# que dentro de la red de contenedores no resuelve, y la conexion falla.
cargar_env() {
  [ -f .env ] || return 0
  while IFS= read -r linea || [ -n "$linea" ]; do
    case "$linea" in ''|'#'*) continue ;; esac
    nombre="${linea%%=*}"
    case "$nombre" in [A-Za-z_][A-Za-z0-9_]*) ;; *) continue ;; esac
    [ -n "${!nombre:-}" ] && continue
    valor="${linea#*=}"
    case "$valor" in
      \"*\") valor="${valor#\"}"; valor="${valor%\"}" ;;
      \'*\') valor="${valor#\'}"; valor="${valor%\'}" ;;
    esac
    export "$nombre=$valor"
  done < .env
}
cargar_env

URL_APP="${DATABASE_URL:-postgres://alivia_app:desarrollo@localhost:5434/alivia}"
URL_PROP="${DATABASE_URL_MIGRACIONES:-postgres://alivia_propietario:desarrollo@localhost:5434/alivia}"

fallos=0
total_ok=0
declare -a resumen

rojo()  { printf '\033[31m%s\033[0m\n' "$*"; }
verde() { printf '\033[32m%s\033[0m\n' "$*"; }

if [ "${1:-}" = "--reiniciar" ]; then
  echo "== Recreando el esquema desde cero =="
  echo "si" | ./db/aplicar.sh --reiniciar >/dev/null 2>&1
  ./db/aplicar.sh --semillas >/dev/null || { rojo "No se pudo aplicar el esquema"; exit 1; }
fi

# --- Pruebas de base de datos ------------------------------------------------
echo
echo "== Pruebas de base de datos =="
encontradas=0
for f in db/pruebas/*.sql; do
  [ -e "$f" ] || continue
  encontradas=$((encontradas + 1))
  nombre=$(basename "$f" .sql)

  # El rol se declara en el propio fichero; por defecto, el de la aplicación.
  if head -20 "$f" | grep -qiE '^--[[:space:]]*@rol:[[:space:]]*propietario'; then
    url="$URL_PROP"; rol="propietario"
  else
    url="$URL_APP"; rol="app"
  fi

  salida=$(psql "$url" -v ON_ERROR_STOP=1 -f "$f" 2>&1)
  codigo=$?
  n_ok=$(printf '%s\n' "$salida" | grep -cE '^ok|NOTICE.*ok' || true)
  n_falla=$(printf '%s\n' "$salida" | grep -c 'FALLA' || true)

  if [ $codigo -ne 0 ]; then
    rojo "  ERROR  $nombre (psql salió con $codigo)"
    printf '%s\n' "$salida" | tail -5 | sed 's/^/         /'
    fallos=$((fallos + 1))
    resumen+=("$nombre: error de ejecución")
  elif [ "$n_falla" -gt 0 ]; then
    rojo "  FALLA  $nombre — $n_falla de $((n_ok + n_falla))  [rol: $rol]"
    printf '%s\n' "$salida" | grep 'FALLA' | sed 's/^/         /'
    fallos=$((fallos + 1))
    resumen+=("$nombre: $n_falla comprobación(es) en rojo")
  elif [ "$n_ok" -eq 0 ]; then
    # Ni ok ni FALLA: el fichero no comprobó nada. Casi siempre es un error.
    rojo "  VACÍA  $nombre no produjo ninguna comprobación  [rol: $rol]"
    fallos=$((fallos + 1))
    resumen+=("$nombre: no comprobó nada")
  else
    verde "  ok     $nombre — $n_ok comprobaciones  [rol: $rol]"
    total_ok=$((total_ok + n_ok))
  fi
done

if [ "$encontradas" -eq 0 ]; then
  rojo "  No se encontró ninguna prueba en db/pruebas/. ¿Se movieron?"
  fallos=$((fallos + 1))
fi

# --- Verificadores del proyecto ----------------------------------------------
echo
echo "== Verificadores =="
for f in scripts/verificar-*.py; do
  [ -e "$f" ] || continue
  nombre=$(basename "$f" .py)
  if salida=$(python3 "$f" 2>&1); then
    n=$(printf '%s\n' "$salida" | grep -cE '^\s*ok' || true)
    verde "  ok     $nombre${n:+ — $n comprobaciones}"
    total_ok=$((total_ok + n))
  else
    rojo "  FALLA  $nombre"
    printf '%s\n' "$salida" | tail -8 | sed 's/^/         /'
    fallos=$((fallos + 1))
    resumen+=("$nombre: falló")
  fi
done

# --- Pruebas de la aplicación ------------------------------------------------
# Todavía no existen: las crea la tarea 4 del backlog. En cuanto package.json
# defina un script "test", se ejecutan aquí sin tocar nada.
echo
echo "== Pruebas de la aplicación =="
if [ -f package.json ] && node -e "process.exit(require('./package.json').scripts?.test ? 0 : 1)" 2>/dev/null; then
  if npm test --silent; then
    verde "  ok     npm test"
  else
    rojo "  FALLA  npm test"
    fallos=$((fallos + 1))
    resumen+=("npm test: falló")
  fi
else
  echo "  (package.json todavía no define 'test' — tarea 4 del backlog)"
fi

# --- Resumen -----------------------------------------------------------------
echo
if [ "$fallos" -eq 0 ]; then
  verde "== Todo en verde: $total_ok comprobaciones =="
  exit 0
fi
rojo "== $fallos grupo(s) con fallos =="
for r in "${resumen[@]}"; do rojo "   · $r"; done
exit 1
