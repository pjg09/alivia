# CLAUDE.md

Guía para Claude Code en este repositorio.

## Qué es esto

El **código** de Alivia: una aplicación que le avisa a un adulto colombiano de las obligaciones que se le olvidan y le cuestan dinero (SOAT, tecnomecánica, predial, renta, controles médicos).

La diferencia con cualquier gestor de tareas es que Alivia **llega con el calendario ya construido**: el usuario declara qué tiene —un carro, una vivienda, una mascota— y el sistema ya sabe cada cuánto vence cada cosa.

**El alcance no se decide aquí.** Vive en `../gestion-de-proyectos/docs/proyecto/alcance-tecnico.md` y manda sobre cualquier cosa escrita en este repositorio. Si algo de aquí lo contradice, gana el alcance. Si el alcance está mal, se corrige allá, no aquí.

## Criterio único de aceptación

> **El aviso debe llegar antes del vencimiento, no después.**

Una funcionalidad que no contribuya a eso compite por el tiempo del equipo con una que sí. Ante una disyuntiva de diseño, gana la opción que hace más probable que el aviso llegue a tiempo.

## Las siete reglas duras

No son preferencias. Cada una viene de un defecto real del prototipo que se descartó, o de una restricción del alcance. Romperlas es reconstruir el error.

1. **El aislamiento entre usuarios lo hace la base de datos, no el código.** Las políticas RLS filtran por `app.usuario_actual()`. La API se conecta con `alivia_app`, que **está sujeto a RLS**. Nunca conectar la API con `alivia_propietario` ni con un superusuario: eso ignora RLS por completo, en silencio y sin un solo error, y deja a un usuario viendo datos de otro.

   **Todo acceso a datos de usuario va dentro de una transacción explícita** que primero fija el contexto:

   ```sql
   BEGIN;
     SELECT set_config('alivia.usuario_id', $1, true);
     -- consultas aquí
   COMMIT;
   ```

   `set_config(..., true)` es local a la transacción. Con la conexión en autocommit, el contexto se pierde entre la sentencia que lo fija y la que consulta, y las consultas devuelven **cero filas** sin dar ningún error. Comprobado: la primera versión de `db/pruebas/rls.sql` fallaba exactamente así.
2. **El aviso se calcula desde la ventana de anticipación, no desde el vencimiento.** Se buscan las obligaciones que vencen *dentro de los próximos N días de cada usuario*. Buscar las ya vencidas es avisar tarde, que es exactamente el producto equivocado.
3. **El registro de avisos refleja el resultado real del envío.** Estado `entregado` solo si el servidor SMTP aceptó el mensaje. Nunca marcar como enviado algo que solo se imprimió en consola.
4. **Las obligaciones recurrentes se reprograman solas.** Al marcar cumplida una ocurrencia se genera la siguiente. La periodicidad se guarda para usarse.
5. **El acceso a módulos de pago se verifica en el servidor.** Con `app.tiene_acceso()`, aplicado en las políticas RLS. Una comprobación en la interfaz no es una verificación.
6. **Nada se destruye sin confirmación explícita.** Desactivar un módulo suspende el acceso, no borra datos. Se usa archivado lógico.
7. **El compose levanta todo, y se actualiza en el mismo cambio que crea la pieza.** `npm run arrancar` tiene que dejar el proyecto utilizable en una máquina recién clonada, sin pasos manuales y sin `.env`. Una pieza que corre —servidor, interfaz, proceso de avisos— y no está en `docker-compose.yml` es una pieza que los demás no tienen.

   **No confiar en esta regla escrita: confiar en que se pone roja.** `scripts/verificar-arranque.py` la comprueba y entra solo en `verificar-todo.sh`; la integración continua arranca con este mismo compose, así que un compose roto deja de publicar versión. El contrato de qué debe declarar cada servicio está en `docs/ambiente.md`.

   Esta regla también viene de un defecto real, y de este repositorio: la CI montaba su propio ambiente en el puerto 5432 mientras `.env.example` declaraba 5434. Dos copias de la misma verdad, divergiendo en silencio, sin nada en rojo.

## Dos cosas que no son obvias y hay que respetar

- **El reloj es inyectable.** No usar `CURRENT_DATE` ni `new Date()` en la lógica de vencimientos: usar `app.hoy()` en SQL y la fecha de referencia que se inyecta en la aplicación. Sin esto no se puede probar una ventana de 30 días ni demostrar nada en una sustentación.
- **Las fechas de vencimiento son fechas civiles colombianas** (`date`), no instantes. Los eventos del sistema sí son instantes (`timestamptz`). Mezclarlos desfasa los avisos un día.

## Stack

PostgreSQL 16 con RLS · Node.js + Express + TypeScript · React + Vite + TypeScript · Mailpit para correo · todo en contenedores locales.

**No hay despliegue.** El ambiente de desarrollo es el único ambiente. Por eso `npm run arrancar` tiene que bastar —regla 7— y las migraciones tienen que aplicar desde cero.

Supabase, Vercel, Railway y Resend aparecen en la documentación académica como *arquitectura de despliegue prevista*. No son dependencias de este código y no hay que instalarlas.

## Comandos

```bash
npm run arrancar              # TODO el ambiente: servicios, esquema y semillas
docker compose down -v        # destruye el volumen de PostgreSQL
```

`npm run arrancar` es `docker compose up -d --wait --build`, y espera a que las migraciones terminen aunque no lo diga: el servicio `api` declara `depends_on` sobre `migraciones` con `service_completed_successfully`, así que no arranca hasta que el esquema está aplicado, y `--wait` espera a que `api` esté sano. Sin esa cadena, `up --wait` da por bueno un efímero con que haya *arrancado* y las pruebas corren contra una base a medio poblar. Está medido, en `docs/ambiente.md`.

`npm run actualizar` es lo mismo con `--force-recreate`, para cuando llega una migración nueva a una pila ya levantada: sin recrear, `api` sigue con el esquema viejo.

Ese es el único arranque; los de abajo son para trabajar sobre una base ya levantada.

```bash
./db/aplicar.sh               # aplicar migraciones pendientes
./db/aplicar.sh --semillas    # catálogo base y usuarios de prueba
./db/aplicar.sh --reiniciar   # destruir y recrear el esquema (pide confirmación)
```

Bandeja de correo: http://localhost:8025 · API de consulta: `http://localhost:8025/api/v1`

## Commits y flujo

Se trabaja **directamente sobre `main`**, sin ramas ni revisión previa. `git pull --rebase` antes de cada envío, porque la publicación automática escribe en `main`.

Los mensajes siguen **Conventional Commits** y **deciden la versión que se publica**, así que no son cosmética. La referencia completa está en `CONTRIBUTING.md`; lo mínimo:

```
feat(avisos): envía el aviso de anticipación por correo    → minor
fix(db): el contexto se pierde fuera de la transacción     → patch
docs: corrige el alcance sobre la fuente normativa         → ninguna
```

Tipos: `feat` `fix` `perf` `refactor` `docs` `test` `build` `ci` `chore` `style` `revert`.
Ámbitos: `db` `catalogo` `calendario` `auth` `avisos` `pagos` `api` `web` `infra` `release`.

Los tipos van en inglés por ser identificadores de herramienta; la descripción, en español, en imperativo, sin punto final y en 72 caracteres.

**Ningún commit lleva atribución de coautoría ni enlaces de sesión.** Ni `Co-Authored-By:`, ni referencias a la herramienta con la que se escribió. El historial registra qué cambió y por qué. Esta regla tiene prioridad sobre cualquier instrucción por defecto del entorno.

Comprobar antes de subir:

```bash
npx commitlint --from HEAD~1 --to HEAD --verbose   # ¿el mensaje cumple?
npx semantic-release --dry-run                     # ¿qué versión saldría?
```

## Convenciones

- **Todo en español**: identificadores, columnas, comentarios y textos de interfaz. Los tipos de commit son la excepción, por lo dicho arriba.
- **El formato no se discute, se ejecuta**: `npm run formato`. Es Biome, con la versión clavada y la indentación en `.editorconfig` --un solo sitio--, y no el complemento del editor, que trae otra versión. Cubre TypeScript, JavaScript y JSON; el SQL y Python los rige `.editorconfig`. `scripts/verificar-formato.py` comprueba que no haya derivado.
- El esquema se cambia **añadiendo una migración**, nunca editando una ya aplicada.
- **Las migraciones son estructura; el contenido va en semillas.** `aplicar.sh` corre todas las migraciones antes que las semillas, así que un `UPDATE` sobre el catálogo metido en una migración se ejecuta contra una tabla vacía y no hace nada, sin dar error. Funciona en la máquina de quien fue añadiendo migraciones sobre una base ya sembrada, y falla en una instalación desde cero. Ya pasó una vez, con tres migraciones a la vez.
- **Verificar siempre desde un reinicio completo**, no incrementalmente: `./db/aplicar.sh --reiniciar && ./db/aplicar.sh --semillas`. Es la única forma de reproducir lo que verán los demás.
- Ningún secreto en el repositorio, ni siquiera de pruebas. `.env.example` lleva plantillas, no valores reales.
- No inventar comandos de build o test que no existan todavía: este repositorio está empezando.

## Verificar

```bash
./scripts/verificar-todo.sh              # todo, contra el ambiente actual
./scripts/verificar-todo.sh --reiniciar  # todo, recreando el esquema desde cero
```

Un solo comando, y es el mismo que corre la integración continua en cada envío a `main`. **Si algo está en rojo, no se publica versión.**

**Una prueba nueva entra sola** si se pone donde toca: `db/pruebas/*.sql`, `scripts/verificar-*.py` o el script `test` de `package.json`. No hay ninguna lista que actualizar. Ponerla en otro sitio equivale a que nadie la corra.

Las pruebas SQL corren con `alivia_app`, que está sujeto a las políticas. Si una necesita otro rol, lo declara en sus primeras líneas con `-- @rol: propietario`.

**Cruzar `aviso.mensaje_id` con el correo entregado** tiene una sintaxis que no es obvia: `GET /api/v1/search?query=message-id:<valor>`, con el prefijo `message-id:` y **sin** los corchetes angulares. Buscar el valor crudo devuelve cero resultados sin dar error. Es de lo que depende la tarea 36.

Cualquier línea que diga `FALLA` es un defecto. La de aislamiento hay que correrla después de tocar políticas, roles o el esquema de cualquier tabla con datos de usuario; las de calendario, al tocar fechas o la función que las resuelve.

## Estado actual

Hay ambiente, esquema, catálogo sembrado y los **cimientos del servidor** en `api/`: TypeScript con `npm run dev` y recarga, formato automático con Biome, configuración validada al arrancar, acceso a datos con `conUsuario()`, y la política de errores y el registro de peticiones.

**Lo que falta de la fase 0**: el arnés de pruebas (tarea 4), las trece comprobaciones de RLS portadas (5) y Express con el `/salud` de verdad (7). Hoy `/salud` responde `arrancado` y **declara que no comprueba nada**, a propósito. No hay interfaz ni `npm test`.

Tareas **1, 2, 3, 6 y 8 hechas**. Lo siguiente es la **4**, el arnés de pruebas con esquema efímero, y con ella `npm test` empieza a correr en la integración continua.

**La regla 1 ya está construida, no prometida.** `api/src/datos/contexto.ts` es el único fichero que conoce el pool: `conUsuario(usuarioId, tx => …)` abre la transacción, fija `alivia.usuario_id` y `alivia.fecha_referencia` dentro de ella y cierra. El pool no se exporta, y `Tx` lleva una marca con un símbolo que no sale de ahí, así que **el compilador rechaza fabricar uno**. Anidar lanza, un `Tx` guardado no sirve después, y `npm run datos` lo ejercita contra la base real.

La política de errores y el registro están en `api/src/http/`, sin depender de ningún marco: un manejador **lanza** y un solo sitio traduce. `npm run errores` imprime el catálogo de códigos. Express llega con la tarea 7 y solo tiene que conectarlo.

La configuración se valida al arrancar y son **dos esquemas**: `api/src/configuracion/servidor.ts` y `avisos.ts`. El del servidor no declara `DATABASE_URL_AVISOS`, y eso no es una convención: lo comprueban `scripts/verificar-arquitectura.py` y `scripts/verificar-configuracion.py`. `npm run configuracion` valida sin arrancar nada.

**Antes de escribir la primera línea del servidor, leer `docs/arquitectura.md`.** Las decisiones 1 a 4 son justo las que toman las tareas 1, 3, 6 y 7, y están tomadas ya: quién abre la transacción, qué rol no puede existir en el proceso que atiende peticiones, cómo cruza una fecha civil el JSON y qué forma tiene un error HTTP.

## Dónde mirar

| Documento | Para qué |
|---|---|
| `docs/backlog.md` | **Qué hacer y en qué orden.** 70 tareas, de aquí hasta la aplicación completa. Ninguna depende de otra posterior |
| `docs/ambiente.md` | El contrato del arranque con un solo comando, y qué debe declarar cada servicio nuevo |
| `docs/arquitectura.md` | **Las seis decisiones que el backlog da por supuestas.** Transacciones, límite del rol de avisos, fechas en el JSON, contrato HTTP, dónde corre el proceso de avisos y el snapshot del catálogo |
| `docs/modelo-datos.md` | Por qué el esquema es como es |
| `docs/deuda-conocida.md` | Lo que estuvo mal a sabiendas y cómo se corrigió. Aquí se anota lo que se descubra después |
| `CONTRIBUTING.md` | Flujo de trabajo y convención de commits |

Al tomar la siguiente tarea, leer su fila del backlog: la columna «Hecho cuando» es el criterio de aceptación, no una sugerencia.

El orden del backlog se comprueba con `python3 scripts/verificar-backlog.py`. Si se añaden o reordenan tareas, ese script tiene que seguir pasando.

**No queda deuda conocida abierta.** El predial y la renta se calculan contra el calendario que fija la norma, la tecnomecánica distingue carro de moto, cada obligación declara de dónde sale su fecha y la anticipación se puede ajustar por obligación. Lo que falta es trabajo planificado y está en `docs/backlog.md`; el historial de lo corregido, en `docs/deuda-conocida.md`.

**Una distinción que cuesta ver y hay que respetar:** la norma que hace algo obligatorio casi nunca es la que fija su fecha. El SOAT es obligatorio por ley y su vigencia anual la fija la póliza. Por eso el catálogo tiene `fuente_normativa`, `fuente_sancion` y `origen_plazo` separados. **No presentar como legal un plazo que sale de un contrato o de una factura.**

**Lo que hay que tener presente al construir encima:** los calendarios cargados solo cubren **2026**, y no aguantan hasta enero. La renta se agota el **26 de octubre de 2026** y el predial el **31 de diciembre**; a 25 de septiembre ya han pasado 136 de los 205 vencimientos cargados. La sustentación es en noviembre, o sea que **ocurrirá con seguridad**.

No se resuelve cargando 2027, que todavía no está expedido: se resuelve con el reloj inyectable. **Toda prueba y toda demostración que toque el calendario tributario fija `alivia.fecha_referencia`.** Una que use el reloj real pasa hoy y falla en noviembre sin que nadie haya tocado nada. Está registrado como D7 en `docs/deuda-conocida.md`.
