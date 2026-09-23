#!/usr/bin/env bash
# Aplica las migraciones pendientes en orden. Idempotente: las ya aplicadas se
# saltan. Las migraciones no se editan nunca: el esquema se cambia añadiendo una.
set -euo pipefail

cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a

URL="${DATABASE_URL_MIGRACIONES:-postgres://alivia_propietario:desarrollo@localhost:5434/alivia}"
SEMILLAS=0

for arg in "$@"; do
  case "$arg" in
    --semillas) SEMILLAS=1 ;;
    --reiniciar)
      read -rp "Esto DESTRUYE el esquema y todos los datos locales. Escribir 'si' para continuar: " r
      [ "$r" = "si" ] || { echo "Cancelado."; exit 1; }
      psql "$URL" -v ON_ERROR_STOP=1 -q -c \
        "DROP SCHEMA IF EXISTS public CASCADE; DROP SCHEMA IF EXISTS app CASCADE; CREATE SCHEMA public;"
      echo "Esquema reiniciado."
      ;;
    *) echo "Uso: $0 [--semillas] [--reiniciar]"; exit 1 ;;
  esac
done

psql "$URL" -v ON_ERROR_STOP=1 -q -c "CREATE SCHEMA IF NOT EXISTS app;" -c \
  "CREATE TABLE IF NOT EXISTS app.migracion_aplicada (nombre text PRIMARY KEY, aplicada_en timestamptz NOT NULL DEFAULT now());"

aplicar_directorio() {
  for f in "$1"/*.sql; do
    [ -e "$f" ] || continue
    nombre="$(basename "$f")"
    ya=$(psql "$URL" -tAc "SELECT 1 FROM app.migracion_aplicada WHERE nombre = '$nombre'")
    if [ "$ya" = "1" ]; then
      echo "  = $nombre"
      continue
    fi
    # Cada migracion se aplica en una transaccion: o entra entera o no entra.
    psql "$URL" -v ON_ERROR_STOP=1 -q --single-transaction \
      -f "$f" -c "INSERT INTO app.migracion_aplicada (nombre) VALUES ('$nombre');"
    echo "  + $nombre"
  done
}

echo "Migraciones:"
aplicar_directorio db/migraciones

if [ "$SEMILLAS" = "1" ]; then
  echo "Semillas:"
  aplicar_directorio db/semillas
fi

echo "Listo."
