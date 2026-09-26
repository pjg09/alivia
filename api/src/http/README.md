# `api/src/http/`

| Fichero | Qué es |
|---|---|
| `errores.ts` | **El único sitio que da forma a una respuesta de error.** Taxonomía y traducción |
| `registro.ts` | Una línea por petición, y qué no entra en ella |
| `comprobar.ts` | `npm run errores` — el catálogo de códigos, y `-- fugas` para probar la frontera |

Express, los middlewares y las rutas llegan con la **tarea 7**. La política de errores y el registro —tarea 6— no dependen de ningún marco a propósito: son funciones puras, así que se prueban sin levantar un servidor y la tarea 7 solo las conecta.

## El contrato

Decisión 4 de `docs/arquitectura.md`. Un único cuerpo, generado en un solo sitio:

```json
{ "error": { "codigo": "OBLIGACION_NO_ENCONTRADA", "mensaje": "…", "identificador": "a1b2c3d4e5" } }
```

`codigo` es estable y en mayúsculas: la interfaz decide contra él, no contra el texto. `mensaje` está escrito para que lo lea quien usa Alivia. `identificador` es aleatorio y es lo que une lo que vio la persona con la línea del registro.

`npm run errores` imprime el catálogo, y lo genera desde la implementación para que no pueda quedar documentando otra cosa.

## Por qué un solo sitio

Un cuerpo de error construido a mano en un manejador es por donde se escapa el mensaje de psql con la cadena de conexión, o el `Key (correo)=(ana@…) already exists` que **confirma a cualquiera que ese correo está registrado**. Nadie lo hace a propósito: se hace por ser útil con el que depura.

Un manejador **lanza** —`throw new NoEncontrado(…)`— y la frontera traduce. Lo que el servidor no reconoce sale como `500 ERROR_INTERNO` **sin describirse**: decir «TypeError: cannot read property usuario_id of undefined» cuenta cómo está hecho el servidor y no le sirve de nada a quien quería ver sus vencimientos.

`scripts/verificar-arquitectura.py` falla si otro fichero construye el cuerpo. `scripts/verificar-errores.py` pasa por la frontera ocho valores hostiles —la cadena de conexión, un error de unicidad con un correo dentro, un hash de contraseña, un `throw` de texto, `null`— y afirma que de ninguno queda rastro.

## Lo que el registro no escribe

| Qué | Por qué |
|---|---|
| La cadena de consulta | Ahí acaban los tokens pegados a mano y los correos de un formulario mal hecho. Se registran los **nombres** de los parámetros, nunca los valores |
| Las cabeceras | `Authorization` lleva el token de sesión entero |
| El cuerpo | Ahí viajan las contraseñas |

Sí se registra el identificador del usuario, que es un uuid: hace falta para depurar un problema de aislamiento —«esta consulta devolvió cero filas, ¿con qué contexto corrió?»— y un uuid no dice quién es nadie. El correo no se registra nunca.

Un error **previsto** no escribe línea aparte: la de la petición ya lleva su estado. Llenar el registro de trazas por cada dirección mal escrita hace que nadie lo lea el día que aparezca una que importa. Solo lo **inesperado** va con pila completa, porque siempre es un defecto.
