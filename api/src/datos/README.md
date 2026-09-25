# `api/src/datos/`

**El único sitio del proyecto que conoce el pool de conexiones.** Decisión 1 de `docs/arquitectura.md`.

Aquí vive `conUsuario()`, que abre la transacción, fija `alivia.usuario_id` y `alivia.fecha_referencia`, y la cierra. El pool **no se exporta**: un repositorio recibe un `Tx` como primer parámetro y no hay forma de construir uno fuera de aquí, así que consultar sin contexto no compila.

Una comprobación de la tarea 3 falla si algún fichero fuera de esta carpeta importa `pg`.

Lo llena la **tarea 3**.
