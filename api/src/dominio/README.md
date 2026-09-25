# `api/src/dominio/`

La lógica que no sabe nada de HTTP ni de SQL: cálculo de vencimientos, selección de avisos, reprogramación.

Dos reglas que vienen de `CLAUDE.md` y se notan aquí:

- **El reloj se inyecta.** Nada de `new Date()` en la lógica de vencimientos: la fecha de referencia entra como parámetro, y en SQL se usa `app.hoy()`. Sin esto no se puede probar una ventana de 30 días.
- **La evaluación de avisos es una función**, no un proceso. El comando de la tarea 34 y el programador de la 35 son dos adaptadores de la misma función. Decisión 5 de `docs/arquitectura.md`.

Lo llenan la **tarea 19** y siguientes.
