#!/usr/bin/env python3
"""Comprueba que las migraciones se puedan aplicar en el orden en que se leen.

    python3 scripts/verificar-migraciones.py

Cuatro personas trabajan directamente sobre `main`, sin ramas. Dos pueden
crear `014_*.sql` el mismo dia: git conserva las dos, `db/aplicar.sh` las
aplica por orden alfabetico, y si una necesita la tabla de la otra, funciona
en la maquina de quien las fue aplicando y falla en una instalacion desde
cero. Es exactamente la clase de fallo que CLAUDE.md ya documenta como sufrida
una vez, con tres migraciones a la vez.

Un numero repetido deja de ser un descuido que alguien tiene que ver en una
revision que aqui no existe, y pasa a ser una prueba en rojo.

Entra solo en ./scripts/verificar-todo.sh por estar aqui y llamarse asi.
"""
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
NOMBRE = re.compile(r"^(\d{3})_[a-z0-9]+(?:_[a-z0-9]+)*\.sql$")

fallos = []


def comprobar(condicion, bien, mal):
    print(f"  {'ok   ' if condicion else 'FALLA'} {bien if condicion else mal}")
    if not condicion:
        fallos.append(mal)


def revisar(directorio, contiguo):
    """`contiguo`: las migraciones van 001, 002, 003...; las semillas van por
    grupos (010 modulos, 020 catalogo, 030 usuarios...) y no tienen por que."""
    d = RAIZ / directorio
    ficheros = sorted(f for f in d.glob("*.sql"))
    if not ficheros:
        comprobar(False, "", f"{directorio}/ no tiene ningun .sql. ¿Se movieron?")
        return

    numeros = {}
    for f in ficheros:
        m = NOMBRE.match(f.name)
        comprobar(m is not None,
                  f"{directorio}/{f.name} tiene el nombre esperado",
                  f"{directorio}/{f.name} no encaja en NNN_nombre_en_minusculas.sql: "
                  f"el orden de aplicacion es el del nombre, asi que el nombre es "
                  f"parte del contrato")
        comprobar(f.stat().st_size > 0,
                  f"{directorio}/{f.name} no esta vacio",
                  f"{directorio}/{f.name} esta vacio: se aplica, se marca como "
                  f"aplicado y no hace nada, y ya nunca se vuelve a mirar")
        if m:
            numeros.setdefault(int(m.group(1)), []).append(f.name)

    # El fallo que este script existe para atrapar.
    for n, nombres in sorted(numeros.items()):
        comprobar(len(nombres) == 1,
                  f"{directorio}/: el numero {n:03d} lo usa un solo fichero",
                  f"{directorio}/: el numero {n:03d} lo usan {len(nombres)} ficheros "
                  f"({', '.join(nombres)}). Se aplicaran por orden alfabetico, que no "
                  f"tiene por que ser el orden correcto. Renumerar la que llego despues")

    if contiguo and numeros:
        faltan = sorted(set(range(1, max(numeros) + 1)) - set(numeros))
        comprobar(not faltan,
                  f"{directorio}/: numeracion contigua de 001 a {max(numeros):03d}",
                  f"{directorio}/: faltan los numeros {['%03d' % n for n in faltan]}. "
                  f"Un hueco suele ser una migracion que se quedo sin subir, y la "
                  f"siguiente se escribio suponiendo que estaba")


def main() -> int:
    revisar("db/migraciones", contiguo=True)
    revisar("db/semillas", contiguo=False)
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
