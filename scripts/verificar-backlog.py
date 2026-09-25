#!/usr/bin/env python3
"""Comprueba que el backlog se pueda leer de arriba abajo sin sorpresas.

Una tarea nunca puede depender de otra que aparezca MAS ABAJO. Si eso se
rompe, el orden del documento deja de significar nada y hay que reordenarlo.

Se mide por posicion en el documento, no por numero. Los identificadores son
estables y no se renumeran, asi que la unica forma de cambiar el orden de
trabajo es mover la fila: exigir ademas que fueran ascendentes obligaba a
renumerar para reordenar, que es justo lo que la regla de identificadores
estables prohibe.

    python3 scripts/verificar-backlog.py
"""
import re
import sys
from pathlib import Path

BACKLOG = Path(__file__).resolve().parent.parent / "docs" / "backlog.md"

# Filas de tabla cuya primera celda es un numero: son las tareas.
FILA = re.compile(r"^\|\s*(\d+)\s*\|(.+)\|\s*([\d,\s—-]+?)\s*\|\s*$")


def main() -> int:
    if not BACKLOG.exists():
        print(f"No existe {BACKLOG}")
        return 1

    tareas: dict[int, list[int]] = {}
    orden: list[int] = []
    errores: list[str] = []

    for n, linea in enumerate(BACKLOG.read_text(encoding="utf-8").splitlines(), 1):
        m = FILA.match(linea)
        if not m:
            continue
        ident = int(m.group(1))
        crudo = m.group(3).strip()
        deps = [int(d) for d in re.findall(r"\d+", crudo)]

        if ident in tareas:
            errores.append(f"linea {n}: la tarea {ident} esta duplicada")
            continue

        tareas[ident] = deps
        orden.append(ident)

        for d in deps:
            if d == ident:
                errores.append(f"linea {n}: la tarea {ident} depende de si misma")

    if not tareas:
        print("No se encontro ninguna tarea. ¿Cambio el formato de las tablas?")
        return 1

    # Toda dependencia tiene que existir.
    for ident, deps in tareas.items():
        for d in deps:
            if d not in tareas:
                errores.append(f"la tarea {ident} depende de {d}, que no existe")

    # Toda dependencia tiene que aparecer mas arriba en el documento.
    posicion = {ident: i for i, ident in enumerate(orden)}
    for ident, deps in tareas.items():
        for d in deps:
            if d in posicion and posicion[d] >= posicion[ident]:
                errores.append(
                    f"la tarea {ident} depende de {d}, que aparece MAS ABAJO "
                    f"en el documento: leyendo de arriba abajo no se puede hacer"
                )

    # Numeracion contigua desde 1: un hueco suele ser una tarea borrada sin pensar.
    faltan = sorted(set(range(1, max(tareas) + 1)) - set(tareas))
    if faltan:
        errores.append(f"faltan los identificadores: {faltan}")

    if errores:
        print(f"{len(errores)} problema(s):\n")
        for e in errores:
            print(f"  · {e}")
        return 1

    sin_dep = [i for i, d in tareas.items() if not d]
    print(f"ok · {len(tareas)} tareas, numeradas de 1 a {max(tareas)}")
    print("ok · ninguna tarea depende de otra que aparezca mas abajo")
    print(f"ok · {len(sin_dep)} tarea(s) sin dependencias: {sin_dep}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
