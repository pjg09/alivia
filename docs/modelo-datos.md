# Modelo de datos

**La fuente de verdad son las migraciones de `db/migraciones/`.** Este documento explica *por qué* el esquema es como es. Si los dos se contradicen, gana el SQL y este documento está desactualizado.

Verificado el 23 de septiembre de 2026 contra PostgreSQL 16 en contenedor: las ocho migraciones aplican desde cero y `db/pruebas/rls.sql` pasa sus trece comprobaciones.

---

## 1. Mapa

```
modulo ──┬── categoria
         └── obligacion_catalogo        el catálogo curado, igual para todos
                      │
                      │ (copia, no referencia viva)
                      ▼
usuario ──┬── autorizacion_tratamiento  evidencia del consentimiento
          ├── modulo_usuario            qué áreas activó
          ├── suscripcion               vigencia de los módulos de pago
          ├── pago_simulado
          └── obligacion_usuario        lo que el usuario tiene
                      │
                      └── ocurrencia    cada vencimiento concreto
                                │
                                └── aviso   un envío, con su resultado real
```

---

## 2. Las decisiones que importan

### 2.1 El compromiso y el vencimiento son dos tablas distintas

`obligacion_usuario` es *«tengo un carro y su SOAT»*. `ocurrencia` es *«ese SOAT vence el 2026-11-04»*.

El prototipo tenía una sola tabla: al marcar cumplido, el recordatorio se cerraba y no volvía nunca. Con la separación, reprogramar es insertar una fila, el historial de cumplimiento queda íntegro y el aviso puede apuntar al vencimiento exacto en lugar de a una obligación genérica.

Un índice único parcial garantiza que una obligación no tenga dos vencimientos pendientes a la vez, de modo que un fallo en la reprogramación no pueda duplicar la siguiente ocurrencia.

### 2.2 La obligación del usuario copia el catálogo, no lo referencia

Cuando el usuario crea una obligación desde el catálogo, el nombre, la periodicidad, el tipo de exigibilidad y la fuente normativa se **copian** en su fila.

El motivo: el catálogo va a cambiar mucho, porque curarlo es trabajo pendiente y es donde está el valor del producto. Si las obligaciones ya creadas apuntaran en vivo al catálogo, corregir una periodicidad movería hacia atrás vencimientos que el usuario ya tiene calculados, y podría convertir un aviso que iba a llegar a tiempo en uno que llega tarde. Eso viola el criterio único de aceptación por un cambio de contenido.

`obligacion_catalogo_id` se conserva igualmente, para poder saber de dónde salió cada obligación y ofrecer una actualización cuando el catálogo mejore. Ofrecerla, no imponerla.

### 2.3 La periodicidad es un `interval`, no un número de días

El alcance dice «periodicidad en días». El esquema usa `interval` porque 365 días no es lo mismo que un año: el SOAT vence el mismo día del año siguiente, y con aritmética de días el vencimiento se desplaza un día cada bisiesto. A cuatro años de uso, el sistema avisa del día equivocado.

`interval '1 year'` deja que PostgreSQL resuelva el calendario. Es más correcto y no cuesta nada.

### 2.4 El primer vencimiento no siempre cae a una periodicidad de la fecha base

`desfase_primera` existe por un caso real del dominio: la revisión técnico-mecánica se exige por primera vez **al quinto año** en carros particulares, y desde entonces es anual.

Sin ese campo, el sistema le avisaría a alguien que acaba de comprar un carro de una tecnomecánica que no es exigible hasta dentro de cinco años. Es el tipo de error que destruye la credibilidad del producto entero: la promesa es que la aplicación *sabe* cuándo vence cada cosa.

### 2.5 Fechas civiles y instantes no se mezclan

Los vencimientos son `date`: son fechas de calendario colombianas, no instantes. Los eventos del sistema —cuándo se envió un aviso, cuándo se creó una fila— son `timestamptz`.

Mezclarlos desfasa los avisos un día según la zona horaria del proceso, y un día de desfase en este producto es la diferencia entre avisar antes o después del vencimiento.

### 2.6 El reloj se inyecta

`app.hoy()` devuelve la fecha de referencia de la transacción si se fijó `alivia.fecha_referencia`, y el día civil colombiano si no.

Sin esto no hay forma de probar una ventana de anticipación de treinta días sin cambiarle la hora al computador, ni de demostrar en una sustentación un aviso que vence dentro de seis meses. **Nunca usar `CURRENT_DATE` en lógica de vencimientos.**

### 2.7 El aislamiento lo hace el motor

Las políticas RLS filtran por `app.usuario_actual()`, que lee un parámetro de la transacción en curso.

**El detalle que hace que funcione o no:** `set_config('alivia.usuario_id', ..., true)` es **local a la transacción**. Una API en autocommit fija el contexto en una transacción y consulta en otra, donde el contexto ya no existe: no ve nada. Todo acceso a datos de usuario tiene que ir dentro de una transacción explícita que primero fije el contexto.

Esto está comprobado, no supuesto: la primera versión de `db/pruebas/rls.sql` fallaba exactamente por esto.

**La condición crítica:** `alivia_app` no es dueño de las tablas y no tiene `BYPASSRLS`. Si la API se conectara con `alivia_propietario`, las políticas se ignorarían **en silencio**, sin un solo mensaje de error, y el aislamiento desaparecería. La comprobación 8 de la prueba existe para eso.

Si no hay contexto, `app.usuario_actual()` devuelve NULL, la comparación no es verdadera y no salen filas. Falla cerrado: una consulta mal escrita devuelve vacío en lugar de devolverlo todo.

### 2.8 La verificación de pago vive en las políticas

`app.tiene_acceso()` se evalúa dentro de la política de `obligacion_usuario`. Un módulo gratuito siempre pasa; uno de pago exige suscripción vigente a la fecha de referencia.

Que esté en la política y no en el código significa que no hay ruta que la eluda: ni un endpoint que alguien olvide proteger, ni una consulta directa. En el prototipo la restricción vivía solo en la interfaz y cualquiera podía activar un módulo de pago sin pagarlo.

**Consecuencia aceptada:** al expirar la suscripción, el usuario deja de *ver* esas obligaciones. No se borran y reaparecen intactas al renovar — comprobaciones 6, 7 y 8 de la prueba. Es lo que pide el alcance: la desactivación conserva la información y solo suspende el acceso.

### 2.9 La ocurrencia lleva `usuario_id` duplicado, y no puede mentir

`ocurrencia.usuario_id` está desnormalizado para que la política RLS filtre sin un join en cada consulta. Para que ese dato no pueda contradecir a su obligación, la clave foránea es compuesta contra `(id, usuario_id)` de `obligacion_usuario`. El motor impide la incoherencia.

### 2.10 La idempotencia del aviso es un índice, no un `if`

`UNIQUE (ocurrencia_id, tipo)` impide que un mismo vencimiento genere dos veces el mismo aviso, pase lo que pase con los reintentos. El alcance exige que un aviso ya entregado no se repita; una comprobación en código se salta en cuanto haya dos procesos o un reintento mal puesto.

### 2.11 Solo dos operaciones ocurren sin contexto de usuario

Registrarse e iniciar sesión, por definición, pasan antes de que exista identidad. Con RLS activo no tienen por dónde entrar: un usuario nuevo no puede insertarse a sí mismo.

La salida no fue aflojar las políticas ni conectar la API con el propietario, sino dos funciones `SECURITY DEFINER` acotadas: `app.registrar_usuario()` y `app.credenciales_por_correo()`. Dos puertas auditables en lugar de un boquete. Todo lo demás sigue pasando por RLS.

La verificación de la contraseña ocurre en la aplicación, nunca en la base de datos: `credenciales_por_correo` devuelve el hash y ahí acaba su trabajo.

### 2.12 Una obligación sancionable sin fuente normativa no entra

Restricción `sancionable_exige_fuente`. Impide por construcción que se cuele una tarea doméstica presentada como obligación con consecuencia legal, que es el defecto que hoy tiene el catálogo heredado —«lavado y aspirado cada 14 días», «revisar pico y placa cada 7 días»—.

`fuente_verificada` es un campo aparte, y **está en `false` en las 40 entradas sembradas**. Declarar lo que no se ha comprobado es más útil que presentarlo como comprobado.

---

## 3. Limitaciones conocidas

Ninguna es un descuido: son decisiones de no resolver algo todavía.

| Limitación | Consecuencia | Qué haría falta |
|---|---|---|
| **Las obligaciones de fecha fija de calendario no se modelan.** La declaración de renta vence según los últimos dígitos del NIT y el predial según el acuerdo de cada municipio. No son periodicidad relativa a una fecha base del usuario | Hoy se tratan como anuales desde una fecha que el usuario declara, lo cual es **incorrecto** para ambas | Un tipo de recurrencia por calendario, con tabla de fechas oficiales por año. Es trabajo de curaduría antes que de esquema |
| **La tecnomecánica no distingue carro de motocicleta** (quinto año contra segundo) | El desfase sembrado es el de carros particulares | Variantes de una misma obligación según un atributo del bien declarado por el usuario |
| **Ninguna fuente normativa está verificada** | Las 40 entradas del catálogo llevan `fuente_verificada = false` | Curaduría contra la norma. Es el trabajo que le da valor al producto |
| **No hay interfaz de administración del catálogo** | Se administra con SQL, por el propietario | Está fuera del alcance de esta etapa |
| **El usuario tiene una sola ventana de anticipación**, común a todas sus obligaciones | No se puede pedir aviso con 30 días para el SOAT y 3 para el pago de una tarjeta | Una columna opcional en `obligacion_usuario` que tenga prioridad sobre la del usuario. Barato de añadir cuando haga falta |

---

## 4. Cómo se verifica

```bash
docker compose up -d
./db/aplicar.sh --reiniciar && ./db/aplicar.sh --semillas
psql "$DATABASE_URL" -f db/pruebas/rls.sql
```

Trece comprobaciones. Cualquier línea que diga `FALLA` es un defecto. La comprobación del aislamiento no es opcional: es el requisito del que cuelga que la aplicación pueda manejar datos de salud.
