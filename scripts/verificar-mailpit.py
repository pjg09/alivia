#!/usr/bin/env python3
"""Comprueba el camino completo del aviso: SMTP -> bandeja -> consulta.

De esto depende toda la fase 4 del backlog, y en particular la tarea 36, que
es la prueba del criterio unico de aceptacion. Conviene que el supuesto este
verificado antes de construir encima.

    python3 scripts/verificar-mailpit.py
"""
import email.utils
import json
import os
import smtplib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from email.message import EmailMessage

# Del entorno, con los mismos valores por defecto que publica el compose.
# Fijarlos en el codigo significaba probar contra la bandeja equivocada cuando
# los puertos se mueven; scripts/verificar-arranque.py vigila que no vuelvan
# a divergir.
SMTP = (os.environ.get("SMTP_HOST", "localhost"), int(os.environ.get("SMTP_PUERTO", "1025")))
API = os.environ.get("MAILPIT_API", "http://localhost:8025/api/v1")


def api(path, metodo="GET"):
    req = urllib.request.Request(API + path, method=metodo)
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r) if metodo == "GET" else r.status


def main() -> int:
    fallos = []

    def comprobar(condicion, bien, mal):
        print(f"  {'ok   ' if condicion else 'FALLA'} {bien if condicion else mal}")
        if not condicion:
            fallos.append(mal)

    try:
        api("/messages?limit=1")
    except (urllib.error.URLError, OSError) as e:
        print(f"No se pudo hablar con Mailpit en {API}: {e}")
        print("¿Esta levantado? npm run arrancar")
        return 1

    # Bandeja limpia, para que el recuento signifique algo.
    api("/messages", "DELETE")

    mensaje_id = email.utils.make_msgid(domain="alivia.local")
    sin_corchetes = mensaje_id.strip("<>")

    m = EmailMessage()
    m["From"] = "Alivia <avisos@alivia.local>"
    m["To"] = "prueba@alivia.local"
    m["Subject"] = "Tu SOAT vence en 30 dias"
    m["Message-ID"] = mensaje_id
    m.set_content("Vence el 2026-11-04. Renuevalo antes.")

    with smtplib.SMTP(*SMTP, timeout=10) as s:
        rechazos = s.send_message(m)
    comprobar(not rechazos, "el servidor SMTP acepta el mensaje",
              f"SMTP rechazo destinatarios: {rechazos}")

    time.sleep(1)
    lista = api("/messages?limit=10")
    comprobar(lista.get("total") == 1, "el mensaje llega a la bandeja unica",
              f"la bandeja tiene {lista.get('total')} mensajes, se esperaba 1")

    if not lista.get("messages"):
        print("\nSin mensajes en la bandeja: no se puede seguir.")
        return 1

    detalle = api("/message/" + lista["messages"][0]["ID"])
    comprobar(detalle.get("MessageID") == sin_corchetes,
              "Mailpit conserva el Message-ID que puso la aplicacion",
              "el Message-ID no se conserva: no se puede cruzar con la tabla aviso")

    # ASI se cruza aviso.mensaje_id con el correo entregado. El prefijo
    # "message-id:" es obligatorio y los corchetes angulares sobran: buscar el
    # valor crudo devuelve cero resultados.
    r = api("/search?query=" + urllib.parse.quote(f"message-id:{sin_corchetes}"))
    comprobar(r.get("messages_count", r.get("total")) == 1,
              "se puede buscar por Message-ID con el prefijo message-id:",
              "la busqueda por Message-ID no encuentra el mensaje")

    r = api("/search?query=" + urllib.parse.quote(f"{sin_corchetes}"))
    comprobar(r.get("messages_count", r.get("total")) == 0,
              "buscar el Message-ID sin prefijo da cero, como se espera",
              "el comportamiento de busqueda cambio: revisar la tarea 36")

    r = api("/search?query=" + urllib.parse.quote("to:prueba@alivia.local"))
    comprobar(r.get("messages_count", r.get("total")) == 1,
              "se puede buscar por destinatario",
              "la busqueda por destinatario no funciona")

    comprobar("2026-11-04" in (detalle.get("Text") or ""),
              "el cuerpo del correo llega completo",
              "el cuerpo no coincide con lo enviado")

    api("/messages", "DELETE")
    comprobar(api("/messages?limit=1").get("total") == 0,
              "la bandeja se puede vaciar entre pruebas",
              "no se puede vaciar la bandeja: las pruebas se contaminaran")

    print()
    if fallos:
        print(f"{len(fallos)} fallo(s).")
        return 1
    print("Camino del aviso verificado de punta a punta.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
