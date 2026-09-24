# CLAUDE.md

Guía para Claude Code en este repositorio.

## Qué es esto

El **código** de Alivia: una aplicación que le avisa a un adulto colombiano de las obligaciones que se le olvidan y le cuestan dinero (SOAT, tecnomecánica, predial, renta, controles médicos).

La diferencia con cualquier gestor de tareas es que Alivia **llega con el calendario ya construido**: el usuario declara qué tiene —un carro, una vivienda, una mascota— y el sistema ya sabe cada cuánto vence cada cosa.

**El alcance no se decide aquí.** Vive en `../gestion-de-proyectos/docs/proyecto/alcance-tecnico.md` y manda sobre cualquier cosa escrita en este repositorio. Si algo de aquí lo contradice, gana el alcance. Si el alcance está mal, se corrige allá, no aquí.

## Criterio único de aceptación

> **El aviso debe llegar antes del vencimiento, no después.**

Una funcionalidad que no contribuya a eso compite por el tiempo del equipo con una que sí. Ante una disyuntiva de diseño, gana la opción que hace más probable que el aviso llegue a tiempo.

## Las seis reglas duras

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

## Dos cosas que no son obvias y hay que respetar

- **El reloj es inyectable.** No usar `CURRENT_DATE` ni `new Date()` en la lógica de vencimientos: usar `app.hoy()` en SQL y la fecha de referencia que se inyecta en la aplicación. Sin esto no se puede probar una ventana de 30 días ni demostrar nada en una sustentación.
- **Las fechas de vencimiento son fechas civiles colombianas** (`date`), no instantes. Los eventos del sistema sí son instantes (`timestamptz`). Mezclarlos desfasa los avisos un día.

## Stack

PostgreSQL 16 con RLS · Node.js + Express + TypeScript · React + Vite + TypeScript · Mailpit para correo · todo en contenedores locales.

**No hay despliegue.** El ambiente de desarrollo es el único ambiente. Por eso `docker compose up -d` tiene que bastar y las migraciones tienen que aplicar desde cero.

Supabase, Vercel, Railway y Resend aparecen en la documentación académica como *arquitectura de despliegue prevista*. No son dependencias de este código y no hay que instalarlas.

## Comandos

```bash
docker compose up -d          # PostgreSQL + Mailpit
./db/aplicar.sh               # aplicar migraciones pendientes
./db/aplicar.sh --semillas    # catálogo base y usuarios de prueba
./db/aplicar.sh --reiniciar   # destruir y recrear el esquema (pide confirmación)
```

Bandeja de correo: http://localhost:8025 · API de consulta: `http://localhost:8025/api/v1`

## Convenciones

- **Todo en español**: identificadores, columnas, mensajes de commit, comentarios y textos de interfaz.
- El esquema se cambia **añadiendo una migración**, nunca editando una ya aplicada.
- Ningún secreto en el repositorio, ni siquiera de pruebas. `.env.example` lleva plantillas, no valores reales.
- No inventar comandos de build o test que no existan todavía: este repositorio está empezando.

## Verificar el aislamiento

```bash
psql "$DATABASE_URL" -f db/pruebas/rls.sql
```

Trece comprobaciones. Cualquier línea que diga `FALLA` es un defecto. Correrlo después de tocar políticas, roles o el esquema de cualquier tabla con datos de usuario.

## Estado actual

Hay ambiente, esquema y catálogo sembrado. **No hay aplicación todavía**: ni servidor, ni interfaz, ni pruebas de la aplicación. Lo siguiente es el esqueleto del servidor con el patrón de contexto por transacción, que es de lo que cuelga la regla 1.

## Dónde mirar

| Documento | Para qué |
|---|---|
| `docs/backlog.md` | **Qué hacer y en qué orden.** 66 tareas, de aquí hasta la aplicación completa. Ninguna depende de otra posterior |
| `docs/modelo-datos.md` | Por qué el esquema es como es |
| `docs/deuda-conocida.md` | Lo que está mal a sabiendas, con su costo |

Al tomar la siguiente tarea, leer su fila del backlog: la columna «Hecho cuando» es el criterio de aceptación, no una sugerencia.

El orden del backlog se comprueba con `python3 scripts/verificar-backlog.py`. Si se añaden o reordenan tareas, ese script tiene que seguir pasando.

**Antes de construir sobre el modelo de datos**, conocer D1 y D2 de `docs/deuda-conocida.md`: el impuesto predial y la declaración de renta **hoy se calculan mal**, y son dos de las cinco obligaciones emblema del producto.
