#!/usr/bin/env python3
"""Comprueba que los puertos a los que se van a conectar las pruebas los
publican LOS CONTENEDORES DE ALIVIA, y no otro proyecto de la misma maquina.

    python3 scripts/identidad.py        # suelto, imprime y sale

Tambien se importa: verificar-todo.sh lo corre como comprobacion previa, y
verificar-mailpit.py lo llama para sus dos puertos.

POR QUE EXISTE
--------------
Un puerto publicado no es una identidad. Esto paso de verdad, dos veces el
mismo dia:

  - Con el contenedor de postgres de Alivia parado, otro proyecto de la maquina
    se habia quedado con el puerto. Todo devolvia «password authentication
    failed for user alivia_propietario»: correcto e inutil, porque la causa no
    era la contrasena.

  - Peor: con el Mailpit de Alivia parado y el de OTRO proyecto escuchando en el
    mismo puerto, verificar-mailpit.py PASABA. Enviaba un correo y lo
    encontraba... en la bandeja equivocada. Un verde falso, que es la clase de
    fallo que este proyecto persigue: no avisa, convence.

La identidad no se puede preguntar por el protocolo --un postgres es un postgres
y un Mailpit es un Mailpit-- asi que se le pregunta a docker: quien publica ese
puerto, y es de los nuestros.
"""
import json
import os
import pathlib
import subprocess
import sys
from urllib.parse import urlparse

RAIZ = pathlib.Path(__file__).resolve().parent.parent
LOCALES = {"localhost", "127.0.0.1", "::1", ""}


class Problema:
    def __init__(self, puerto: int, para_que: str, texto: str):
        self.puerto = puerto
        self.para_que = para_que
        self.texto = texto


def _docker(argumentos, cwd=RAIZ):
    try:
        r = subprocess.run(["docker", *argumentos], cwd=cwd, capture_output=True,
                           text=True, timeout=60)
    except FileNotFoundError:
        return None, "docker no esta instalado, y el ambiente del proyecto es docker"
    except subprocess.TimeoutExpired:
        return None, "docker no respondio en 60s"
    if r.returncode != 0:
        return None, (r.stderr or r.stdout).strip()[:200]
    return r.stdout, None


def _leer_json(crudo):
    """Compose escribe un array o un objeto por linea segun la version."""
    crudo = crudo.strip()
    if crudo == "":
        return []
    try:
        d = json.loads(crudo)
        return [d] if isinstance(d, dict) else d
    except json.JSONDecodeError:
        return [json.loads(l) for l in crudo.splitlines() if l.strip()]


def puertos_declarados():
    """Los puertos que publica el compose de ESTE repositorio, con su servicio.

    Sale de `compose config` y no de `compose ps` a proposito: un contenedor
    parado no publica nada, asi que `ps` diria que el puerto no es nuestro y el
    mensaje seria «no lo publica nadie» en lugar de «el nuestro esta parado»,
    que es lo que hay que leer para saber que hacer.
    """
    salida, error = _docker(["compose", "config", "--format", "json"])
    if salida is None:
        return None, error
    try:
        configuracion = json.loads(salida)
    except json.JSONDecodeError as e:
        return None, f"no se pudo leer la configuracion del compose: {e}"

    declarados: dict[int, str] = {}
    for nombre, servicio in (configuracion.get("services") or {}).items():
        for publicado in servicio.get("ports") or []:
            crudo = publicado.get("published")
            try:
                puerto = int(crudo)
            except (TypeError, ValueError):
                continue
            declarados.setdefault(puerto, nombre)
    return declarados, None


def estado_de_los_servicios():
    """Estado y salud de cada servicio del compose, incluidos los parados."""
    salida, error = _docker(["compose", "ps", "-a", "--format", "json"])
    if salida is None:
        return None, error
    estados: dict[str, tuple[str, str]] = {}
    for fila in _leer_json(salida):
        nombre = fila.get("Service") or fila.get("Name") or "?"
        estados[nombre] = ((fila.get("State") or "").lower(), (fila.get("Health") or "").lower())
    return estados, None


def quien_publica(puerto: int):
    """El contenedor ajeno que tiene ese puerto, si hay alguno."""
    salida, _ = _docker(["ps", "--format", "{{.Names}}\t{{.Image}}\t{{.Ports}}"], cwd=None)
    if salida is None:
        return None
    for linea in salida.splitlines():
        partes = linea.split("\t")
        if len(partes) == 3 and f":{puerto}->" in partes[2]:
            return f"{partes[0]} ({partes[1]})"
    return None


def puerto_de(url: str | None, por_defecto: int):
    """El puerto de una URL, solo si apunta a esta maquina."""
    if url is None or url.strip() == "":
        return por_defecto
    try:
        partes = urlparse(url.strip())
    except ValueError:
        return por_defecto
    if (partes.hostname or "") not in LOCALES:
        return None  # apunta a otra maquina: docker no puede decir nada
    return partes.port or por_defecto


def puertos_que_se_van_a_usar():
    """Los puertos a los que se conectan las pruebas, leidos del mismo entorno
    que leen ellas. No se incluye el del servidor: no hay verificador que lo
    use todavia, y pararlo para correr `npm run dev` es legitimo."""
    entorno = os.environ
    puertos: dict[int, str] = {}

    for variable, por_defecto in (
        ("DATABASE_URL", 5434),
        ("DATABASE_URL_AVISOS", 5434),
        ("DATABASE_URL_MIGRACIONES", 5434),
    ):
        p = puerto_de(entorno.get(variable), por_defecto)
        if p is not None:
            puertos[p] = "la base de datos"

    p = puerto_de(entorno.get("MAILPIT_API"), 8025)
    if p is not None:
        puertos[p] = "la bandeja de correo (API)"

    if (entorno.get("SMTP_HOST") or "localhost") in LOCALES:
        try:
            puertos[int(entorno.get("SMTP_PUERTO") or 1025)] = "el correo (SMTP)"
        except ValueError:
            pass

    return puertos


def revisar(puertos: dict[int, str]):
    """Devuelve la lista de problemas. Vacia si todo lo publica Alivia."""
    declarados, error = puertos_declarados()
    if declarados is None:
        return [Problema(0, "el ambiente", f"no se pudo preguntar a docker: {error}")]

    estados, error = estado_de_los_servicios()
    if estados is None:
        return [Problema(0, "el ambiente", f"no se pudo preguntar a docker: {error}")]

    problemas = []
    for puerto, para_que in sorted(puertos.items()):
        servicio = declarados.get(puerto)

        if servicio is None:
            # No es nuestro. Si alguien lo tiene, decir quien: es la diferencia
            # entre media hora de depuracion y leer una linea.
            ajeno = quien_publica(puerto)
            if ajeno is not None:
                problemas.append(Problema(
                    puerto, para_que,
                    f"lo publica «{ajeno}», que NO es de Alivia.\n"
                    f"         Las pruebas hablarian con el servicio de otro proyecto, y algunas\n"
                    f"         PASARIAN: enviar un correo y encontrarlo en la bandeja equivocada\n"
                    f"         no falla, convence.\n"
                    f"         El compose de Alivia publica {sorted(declarados)}: revisar el .env."))
            else:
                problemas.append(Problema(
                    puerto, para_que,
                    f"no lo publica nadie, y el compose de Alivia tampoco: publica "
                    f"{sorted(declarados)}.\n"
                    f"         Revisar el puerto en el .env, o levantar el ambiente con "
                    f"npm run arrancar."))
            continue

        estado, salud = estados.get(servicio, ("", ""))
        if estado != "running":
            # Y si alguien se quedo con el hueco, decir quien: eso es la
            # diferencia entre «algo no arranca» y «estoy probando contra otro».
            ocupante = quien_publica(puerto)
            quien = (
                f"\n         Y ahora mismo lo tiene «{ocupante}»: lo que se pruebe contra ese\n"
                f"         puerto NO es Alivia, y puede pasar en verde."
                if ocupante is not None
                else "\n         Mientras este parado, cualquier otro proyecto puede quedarse con el."
            )
            problemas.append(Problema(
                puerto, para_que,
                f"lo declara «{servicio}» de Alivia, pero el contenedor esta "
                f"«{estado or 'sin crear'}».{quien}\n"
                f"         Levantarlo:  npm run arrancar"))
        elif salud not in ("", "healthy"):
            problemas.append(Problema(
                puerto, para_que,
                f"lo publica «{servicio}» de Alivia, pero su salud es «{salud}».\n"
                f"         Mirar por que:  docker compose logs {servicio}"))

    return problemas


def informe(problemas) -> str:
    lineas = ["Los puertos de las pruebas no son los de Alivia:", ""]
    for p in problemas:
        donde = f"puerto {p.puerto}" if p.puerto else "el ambiente"
        lineas.append(f"  {donde} — {p.para_que}")
        lineas.append(f"         {p.texto}")
        lineas.append("")
    lineas.append("  El porque de esta comprobacion esta en scripts/identidad.py")
    return "\n".join(lineas)


def exigir(puertos: dict[int, str]) -> None:
    """Para que la llame un verificador: lanza SystemExit si algo no es nuestro."""
    problemas = revisar(puertos)
    if problemas:
        print(informe(problemas))
        raise SystemExit(1)


def main() -> int:
    puertos = puertos_que_se_van_a_usar()
    problemas = revisar(puertos)
    if problemas:
        print(informe(problemas))
        return 1
    for puerto, para_que in sorted(puertos.items()):
        print(f"  ok    el puerto {puerto} ({para_que}) lo publica un contenedor de Alivia")
    return 0


if __name__ == "__main__":
    sys.exit(main())
