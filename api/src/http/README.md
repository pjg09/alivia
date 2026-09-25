# `api/src/http/`

Express, middlewares y rutas. El contrato está en la decisión 4 de `docs/arquitectura.md`:

- Un **único** cuerpo de error, `{ "error": { "codigo": "...", "mensaje": "..." } }`, y un solo sitio que lo da forma. Nunca el texto de psql, nunca una traza.
- Rutas en español, sustantivos en plural, y las acciones como subrecurso en verbo: `POST /ocurrencias/:id/cumplir`.
- Sesión en `Authorization: Bearer <token>`. El identificador de usuario **nunca** en la URL ni en el cuerpo.
- Las fechas civiles salen como cadena `AAAA-MM-DD`.

Lo llenan las **tareas 6 y 7**.
