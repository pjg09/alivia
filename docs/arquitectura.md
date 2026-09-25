# Arquitectura

## Qué es esto y qué no

Seis decisiones. No hay diagrama de capas ni modelo C4, a propósito: eso sería decoración y competiría por tiempo con el criterio único de aceptación. Lo que evita daño real es esta media página, y las comprobaciones automáticas que la respaldan.

**Lo que ya estaba decidido no se repite aquí.** Vive donde le corresponde y manda sobre este documento:

| Decisión | Dónde |
|---|---|
| Dónde vive la autorización: en la base, con RLS | Regla 1 de `CLAUDE.md` · `db/migraciones/007_rls.sql` |
| El modelo de datos y su porqué | `docs/modelo-datos.md` |
| El reloj es inyectable (`app.hoy()`) | `CLAUDE.md` · `db/migraciones/001_base_roles_y_reloj.sql` |
| Un solo ambiente, en contenedores, sin despliegue | Regla 7 de `CLAUDE.md` · `docs/ambiente.md` |
| Qué se construye y en qué orden | `docs/backlog.md` |

Estas seis son las que el backlog da por supuestas y que, sin escribirlas, cuatro personas resolverían de cuatro maneras al tomar las tareas 1, 3, 6 y 7.

**Cada una trae su comprobación.** No porque falte confianza, sino porque una regla que no se pone roja se rompe sin que nadie se entere: eso ya pasó con el ambiente. Las comprobaciones entran con la tarea que las hace posibles, no antes — la tabla del final dice cuál con cuál.

---

## 0 · El servidor es `api/` y la interfaz `web/`, como paquetes separados

Esta sí es una decisión de estructura de carpetas, y está aquí porque **de ella depende que la regla 7 se pueda comprobar**. Las demás decisiones de disposición siguen siendo de quien tome la tarea.

```
alivia/
├── package.json        ← raíz: espacios de trabajo, herramientas comunes
├── api/                ← servidor. Su propio package.json y su Dockerfile
│   └── src/datos/      ← el único sitio que conoce el pool (decisión 1)
├── web/                ← interfaz. Su propio package.json y su Dockerfile
└── avisos/             ← si el proceso de avisos no vive dentro de api/ (decisión 5)
```

**Por qué separados y no un `src/` en la raíz:**

- **Los árboles de dependencias no se mezclan.** La imagen del servidor no instala React, y la de la interfaz no instala `pg`. Con un solo `package.json` en la raíz, las dos imágenes cargan todo.
- **`scripts/verificar-arranque.py` detecta los componentes por directorio de primer nivel.** Un servidor en la raíz no lo detectaba, así que la regla 7 —«el compose levanta todo»— era letra muerta justo en la tarea 1. El hueco se cerró además por el otro lado: un `Dockerfile` o un `src/` en la raíz también exigen su servicio. Pero la disposición decidida es esta.
- Cada paquete declara su propio `test`, y la raíz los agrega.

---

## 1 · La transacción la abre el caso de uso, nunca un repositorio

**Una petición HTTP es una transacción.** La abre el caso de uso; un repositorio no puede abrirla porque no tiene con qué.

```ts
// api/src/datos/contexto.ts — el ÚNICO fichero que conoce el pool
export type Tx = { readonly __tx: unique symbol; query(...): ... }

export async function conUsuario<T>(
  usuarioId: string,
  fn: (tx: Tx) => Promise<T>,
): Promise<T>
```

El pool no se exporta. Un repositorio se declara `listarObligaciones(tx: Tx, …)` y **no existe forma de construir un `Tx`** fuera de `conUsuario`. El compilador hace el trabajo que si no haría la disciplina: consultar sin transacción con contexto no compila.

**`conUsuario` fija las dos variables de sesión, no una:**

```sql
SELECT set_config('alivia.usuario_id',       $1, true);
SELECT set_config('alivia.fecha_referencia', $2, true);   -- si se inyectó
```

`app.hoy()` lee la segunda. Fijando solo la primera no se puede demostrar una ventana de 30 días sin mover el reloj de la máquina.

**El contexto se pasa como parámetro. No se usa `AsyncLocalStorage`.** Es más verboso y lo preferimos por eso: un contexto implícito se pierde con un `await` mal colocado, en silencio, y la consulta devuelve cero filas sin dar error — que es exactamente el fallo del que nace la regla 1. No se reconstruye en TypeScript el problema que ya se resolvió en SQL. Además, pasar `tx` explícitamente hace el anidamiento **imposible por construcción**, no detectable a posteriori.

**Lo que ya no hay que resolver:** la tarea 11 exige que la cuenta y la constancia de autorización queden en la misma transacción. `app.registrar_usuario()` hace las dos cosas en una llamada, así que la atomicidad la garantiza el motor.

---

## 2 · El rol `alivia_avisos` no existe en el proceso que atiende peticiones

`alivia_avisos` lee obligaciones de **todos** los usuarios: es su trabajo, y tiene políticas propias que lo permiten (`db/migraciones/007_rls.sql`). Ese camino salta el aislamiento a propósito. Si ese pool fuera alcanzable desde un manejador HTTP, la regla 1 quedaría anulada por la puerta de atrás, y **ninguna prueba de RLS se enteraría**, porque las políticas estarían haciendo justo lo que se les pidió.

**Se separa por proceso, no por convención.** El proceso de avisos es otro servicio (ver decisión 5). El pool no está en la memoria del que atiende peticiones.

**Dos módulos de configuración, no uno.** La tarea 2 valida el entorno al arrancar; valida **dos esquemas distintos**, y el del servidor **no declara `DATABASE_URL_AVISOS`**. Si la validación rechaza lo que no está declarado, el servidor no puede construir ese pool ni queriendo: no tiene de dónde sacar la URL.

**La defensa en profundidad que ya está puesta**, y conviene conocer para no debilitarla:

- `alivia_avisos` tiene `SELECT` y nada más sobre `usuario`, `obligacion_usuario` y `ocurrencia`. Una fuga permitiría leer datos de otros usuarios; no escribirlos.
- `alivia_app` tiene `SELECT` y nada más sobre `aviso`. **El servidor no puede fabricar un aviso «entregado»**: la regla 3 ya es estructural, no una promesa del código.

Añadir `INSERT` o `UPDATE` a cualquiera de esos dos grants deshace una de estas dos garantías. No se hace sin una razón escrita en `docs/deuda-conocida.md`.

---

## 3 · Una fecha civil cruza el cable como cadena `AAAA-MM-DD`

Siempre. Nunca un objeto `Date`. Y la línea que lo resuelve de verdad:

```ts
// Antes de crear el pool. node-postgres convierte date (OID 1082) en un Date
// de JavaScript a medianoche local, y a partir de ahí toda aritmética y toda
// serialización es una ocasión de desfasar el día. Que siga siendo texto.
pg.types.setTypeParser(1082, (v) => v)
```

**El riesgo, sin exagerarlo:** con `TZ=America/Bogota` (UTC−5), serializar esa `Date` conserva el día por casualidad, porque el desplazamiento es negativo. Se rompe con cualquier zona al este de Greenwich, y se rompe **siempre** en cuanto alguien compare esa `Date` con un `new Date()` o haga `toISOString().slice(0, 10)`. No es un fallo garantizado hoy; es una clase entera de fallos que desaparece por una línea.

**Convención de nombres, que el esquema ya cumple:**

| Sufijo | Tipo SQL | En el JSON | Ejemplos |
|---|---|---|---|
| `fecha_*` | `date` | `"2026-03-14"` | `fecha_base`, `fecha_vencimiento` |
| `*_en` | `timestamptz` | ISO con desplazamiento | `creada_en`, `archivada_en`, `enviado_en` |

Mezclarlos desfasa los avisos un día, y el sitio donde se mezclan es la frontera HTTP.

Cuando exista el servicio del servidor en el compose, lleva `TZ: America/Bogota`, como ya lo lleva postgres.

---

## 4 · Contrato HTTP: cinco reglas

Solo lo que cuatro personas inventarían distinto.

**a) Errores, un único cuerpo.** Lo da forma el middleware de la tarea 6, y **solo** ese sitio.

```json
{ "error": { "codigo": "OBLIGACION_NO_ENCONTRADA", "mensaje": "…" } }
```

`codigo` estable, en mayúsculas con guion bajo, para que la interfaz decida sin leer texto. `mensaje` legible para el usuario. Nunca el texto de psql, nunca una traza, nunca el dato de otro usuario.

| Código | Cuándo |
|---|---|
| 400 | El cuerpo o los parámetros no validan |
| 401 | Sin sesión, o con token inválido o caducado |
| 403 | Con sesión, sin acceso a ese módulo o recurso |
| 404 | No existe, o no es de este usuario y no se distingue |
| 409 | Conflicto de estado: cumplir algo ya cumplido, solapar suscripciones |
| 500 | Lo demás, con cuerpo genérico y el detalle solo en el registro |

**b) Rutas en español, sustantivos en plural; las acciones son subrecursos en verbo.**

```
GET  /obligaciones
POST /ocurrencias/:id/cumplir
POST /obligaciones/:id/archivar
```

No es estética. La regla 6 exige confirmación explícita, y una acción con nombre propio tiene dónde pedirla —un cuerpo `{"confirmar": true}`—. Un `DELETE /obligaciones/:id` no tiene dónde ponerla.

**c) Sesión en `Authorization: Bearer <token>`.** El identificador de usuario **nunca** viaja en la URL ni en el cuerpo, ni como redundancia: el día que alguien lo lea de ahí, `conUsuario()` recibe lo que mande el cliente.

**d) Fechas** según la decisión 3.

**e) La fecha de referencia se inyecta por variable de entorno del proceso, nunca por cabecera de petición.** Una cabecera tipo `X-Alivia-Fecha` es cómoda para la sustentación y es un agujero el día que se queda puesta: cualquiera adelantaría el reloj de su propia sesión. Para demostrar el servidor con otra fecha, se reinicia el servicio con la variable.

---

## 5 · La evaluación es una función; el disparador es un proceso aparte

Son tres capas y hacen falta las tres. «Función o proceso» es una disyuntiva falsa:

| Capa | Qué es | Por qué separada |
|---|---|---|
| **Evaluación** | Función: recibe fecha de referencia y acceso a datos, devuelve qué avisos toca enviar | Se prueba sin SMTP y sin esperar a mañana |
| **Envío y registro** | Adaptador sobre SMTP que escribe en `aviso` el resultado **real** | Regla 3 |
| **Disparador** | Dos adaptadores sobre la misma función: el comando de la tarea 34 y el programador de la 35 | Si no comparten la función, se escriben dos veces y divergen |

**El proceso de avisos es su propio servicio, no un hilo del servidor.** Razones, por orden de peso:

1. **Vuelve estructural la decisión 2.** El pool de `alivia_avisos` no existe en la memoria del proceso que atiende peticiones. Es la filosofía del proyecto —«el aislamiento lo hace la base de datos, no el código»— aplicada un nivel más arriba. Ninguna otra razón bastaría sola; esta sí.
2. Un cuelgue de SMTP no bloquea las peticiones.
3. Reiniciar el servidor no se salta la evaluación del día.
4. Los fallos se leen en `docker compose logs avisos`, sin el ruido de las peticiones.

**Lo que cuesta, dicho entero:**

- Cambia la redacción de la tarea 35, que decía «dentro del proceso del servidor». No cambia sus dependencias.
- Un servicio más en el compose, con su healthcheck y su etiqueta `alivia.rol-bd: avisos`. Lo exige `scripts/verificar-arranque.py` en cuanto exista el directorio.
- **La tarea 32 sigue siendo obligatoria.** Un proceso aparte no elimina la duplicación, la desplaza: ya no es «dos réplicas del servidor», es «un reinicio a las 8:01 vuelve a evaluar». La idempotencia es lo que hace seguro cualquiera de los dos diseños.

**El programador, sin cron dentro del contenedor.** Un bucle que despierta cada 60 segundos, compara `app.hoy()` con la fecha de la última ejecución registrada, y evalúa solo si cambió. Tres ventajas de una: la fecha inyectable lo hace probable en segundos, la idempotencia de la tarea 32 lo cubre, y cada vuelta puede tocar un fichero de latido que sirve de healthcheck.

---

## 6 · `obligacion_catalogo_id` sirve solo para procedencia

**Esto ya lo garantiza el esquema**, y conviene saberlo antes de escribir la primera consulta: `obligacion_usuario` guarda `nombre`, `descripcion`, `periodicidad`, `desfase_primera`, `tipo_exigibilidad` y `fuente_normativa` como columnas propias. Son una copia del catálogo en el momento de crear la obligación, no una referencia viva. Corregir el catálogo no mueve hacia atrás un vencimiento que un usuario ya tiene calculado.

Lo único que queda expuesto es una consulta que, para mostrar el nombre, haga `JOIN obligacion_catalogo` en lugar de leer la copia. Es fácil de escribir sin darse cuenta, porque la columna está ahí invitando.

**La referencia sirve para saber de dónde salió la obligación: agrupar, informar, auditar.** Ninguna lectura de lo que se muestra al usuario y ningún cálculo de vencimiento pasa por ella.

**Se comprueba con el dato, no con el código.** Una prueba en `db/pruebas/` crea una obligación desde el catálogo, **modifica la fila del catálogo** —nombre y periodicidad— y afirma que el nombre de la obligación, su periodicidad y la fecha de la ocurrencia pendiente no se movieron. Eso vale para cualquier código que se escriba encima; un analizador de `import`s no llega ahí.

---

## Qué comprobación entra con qué tarea

Una regla que no se pone roja se rompe sin que nadie se entere. Cada comprobación va en la tarea que la hace posible, y por su ubicación entra sola en `scripts/verificar-todo.sh`.

| # | Decisión | Comprobación | Con la tarea |
|---|---|---|---|
| 1 | La transacción la abre el caso de uso | Ningún fichero fuera de `api/src/datos/` importa `pg` | 3 |
| 1 | Las dos variables de sesión | Una consulta con fecha inyectada devuelve lo que corresponde a esa fecha | 3 |
| 2 | El rol de avisos no está en el servidor | `DATABASE_URL_AVISOS` solo aparece en el módulo de avisos, `.env.example` y el compose | 31 |
| 3 | Fechas civiles como cadena | Un vencimiento pedido por HTTP encaja en `^\d{4}-\d{2}-\d{2}$` | 22 |
| 4 | Un solo sitio da forma a los errores | Ningún fichero de rutas contiene `res.status(…).json({ error` | 6 |
| 5 | Un servicio propio para avisos | `scripts/verificar-arranque.py`, ya escrito, lo exige al aparecer el directorio | 35 |
| 6 | El snapshot no se mueve | Prueba SQL: cambiar el catálogo no altera una obligación ya creada | 20 |

## Lo que este documento no decide, a propósito

Estructura de carpetas por dentro de `api/` y `web/` más allá de `api/src/datos/`, biblioteca de validación, gestión de estado en la interfaz, formato del registro. Son decisiones reversibles y baratas: quien tome la tarea las toma. Lo de arriba no es reversible ni barato, y por eso está escrito.
