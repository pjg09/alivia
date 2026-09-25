# `api/src/configuracion/`

Lectura y validación del entorno **al arrancar**. Si falta una variable obligatoria, el proceso muere con un mensaje que dice cuál, en lugar de fallar más tarde y en otro sitio.

Son **dos esquemas distintos**, el del servidor y el del proceso de avisos, y el del servidor **no declara `DATABASE_URL_AVISOS`**: decisión 2 de `docs/arquitectura.md`. Ese rol ve las obligaciones de todos los usuarios, y si el servidor pudiera construir ese pool, la regla 1 quedaría anulada por la puerta de atrás.

`JWT_SECRETO` es el único caso con tratamiento especial: ausente se genera uno aleatorio con aviso; con el valor de plantilla, el proceso muere. El porqué está en la decisión 2.

Lo llena la **tarea 2**.
