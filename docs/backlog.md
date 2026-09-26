# Backlog

De donde está el proyecto hoy hasta la aplicación completa.

**El orden es una dependencia, no una sugerencia.** Leyendo de arriba abajo, ninguna tarea depende de otra que aparezca más abajo. Se mide por **posición**, no por número: los identificadores son estables y no se renumeran, así que reordenar el trabajo es mover la fila. Eso lo comprueba un script, no la buena fe:

```bash
python3 scripts/verificar-backlog.py
```

Si alguien añade o reordena tareas, ese script tiene que seguir pasando.

**Qué significa cada columna**

| Columna | Qué es |
|---|---|
| `#` | Identificador estable. No se reutiliza ni se renumera |
| Tarea | Qué se construye |
| Hecho cuando | La condición que decide si está terminada. Si no se puede comprobar, no es un criterio |
| Dep. | Tareas que deben estar terminadas antes. Siempre tareas que ya aparecieron **más arriba** |

**Una tarea terminada se marca `**HECHA**` al principio de su celda, y se queda donde está.** No se borra: el orden es un grafo de dependencias, y quitar un nodo deja huérfanas a las que colgaban de él. `verificar-backlog.py` comprueba que ninguna tarea marcada dependa de otra sin marcar — si eso pasa, o la marca está de más o falta una.

**Lo que ya está hecho** y por eso no aparece aquí: ambiente de contenedores, las trece migraciones del esquema, el catálogo sembrado con 40 entradas y sus 8 obligaciones sancionables verificadas contra la norma, las deudas D1 a D5 saldadas, y las verificaciones de `db/pruebas/`.

**Paralelismo.** Son cuatro personas. Dos tareas con el mismo número en `Dep.` y sin relación entre sí pueden ir a la vez; el grafo de dependencias es lo que dice qué se puede repartir, no la numeración.

---

## Fase 0 · Cimientos del código

Nada de esto entrega valor al usuario y todo lo demás depende de ello. La tarea 3 es la más importante del proyecto: es donde vive el patrón del que cuelga el aislamiento entre usuarios.

| # | Tarea | Hecho cuando | Dep. |
|---|---|---|---|
| 1 | **HECHA** · Proyecto del servidor en **`api/`**, con TypeScript y script de arranque en desarrollo | `npm run dev` levanta un proceso que compila y recarga. El servidor va en `api/` y la interfaz en `web/`, como paquetes separados — decisión 0 de `docs/arquitectura.md`. Y el servicio entra en `docker-compose.yml` **en el mismo cambio**, o `scripts/verificar-arranque.py` se pone rojo | — |
| 8 | **HECHA** · Convenciones de código y formato automático | El formateador corre igual en las cuatro máquinas y no genera ruido en los diffs. **Va de segunda a propósito**: cuatro personas sin formateador generan ruido en los diffs desde el primer día, y el cambio que lo introduce después toca todos los ficheros a la vez | 1 |
| 2 | **HECHA** · Configuración leída del entorno y **validada al arrancar** | Falta una variable obligatoria y el proceso muere con un mensaje que dice cuál, en lugar de fallar más tarde. Y distingue **ausente** de **de plantilla**: sin `JWT_SECRETO` el servidor genera uno aleatorio y avisa de que las sesiones no sobreviven a un reinicio; con `JWT_SECRETO=cambiar-en-cada-maquina` **muere**. Es lo único que deja convivir la regla 7 —arranca sin `.env`—, el rechazo del valor de plantilla y la prohibición de secretos en el repositorio: ver la decisión 2 de `docs/arquitectura.md`. Son **dos esquemas distintos**, el del servidor y el del proceso de avisos, y el del servidor no declara `DATABASE_URL_AVISOS` — decisión 2 de `docs/arquitectura.md` | 1 |
| 3 | **HECHA** · Acceso a datos: pool de conexiones y función `conUsuario()` que abre transacción, fija `alivia.usuario_id` y la cierra | Toda consulta de datos de usuario pasa por ahí. Intentar consultar fuera de una transacción con contexto es imposible por construcción, no por disciplina | 2 |
| 4 | Arnés de pruebas con esquema efímero: cada prueba corre contra una base limpia | `npm test` aplica migraciones y semillas desde cero y deja la base como la encontró. **Definir ese script en `package.json` basta para que la integración continua lo ejecute**: no hay que tocar el flujo de trabajo | 3 |
| 5 | Las trece comprobaciones de `db/pruebas/rls.sql` portadas a la capa de datos de la aplicación | `npm test` falla si alguien conecta con el rol equivocado o pierde el contexto de transacción | 4 |
| 6 | **HECHA** · Manejo de errores HTTP y registro de peticiones | Un error no controlado devuelve un código y un cuerpo coherentes, y **nunca** filtra detalles internos ni datos de usuario | 1 |
| 7 | Servidor Express con endpoint de salud | `GET /salud` responde y reporta si la base de datos y el correo están accesibles | 2, 6 |

---

## Fase 1 · Cuentas

| # | Tarea | Hecho cuando | Dep. |
|---|---|---|---|
| 9 | Hash y verificación de contraseña con Argon2, con **`@node-rs/argon2`** | Una contraseña correcta verifica, una incorrecta no, y el hash nunca sale en un registro ni en una respuesta. La biblioteca es `@node-rs/argon2`, con binarios precompilados, y no `argon2`, que exige node-gyp y herramientas de compilación en las cuatro máquinas | 4 |
| 10 | Token de sesión: emisión y verificación | Un token válido identifica al usuario; uno manipulado, caducado o firmado con otra clave se rechaza | 2, 4 |
| 11 | Registro de usuario, vía `app.registrar_usuario()` | Crea la cuenta, **deja constancia de la autorización de tratamiento en la misma transacción** y activa los tres módulos gratuitos | 3, 7, 9, 10 |
| 12 | Ingreso, vía `app.credenciales_por_correo()` | Devuelve sesión con credenciales correctas. Con correo inexistente o contraseña errada, la respuesta y el tiempo de respuesta son indistinguibles entre sí | 3, 7, 9, 10 |
| 13 | Middleware de autenticación: del token al contexto de la transacción | Una petición sin token o con token inválido no llega al manejador. El identificador que usa `conUsuario()` sale del token, nunca del cuerpo ni de la URL | 7, 10 |
| 14 | Perfil: consultar y editar nombre, ventana de anticipación y activación de avisos | El usuario cambia su ventana a 30 días y el cambio persiste | 3, 13 |
| 15 | Prueba de extremo a extremo: registro, ingreso, perfil, y **un usuario no alcanza los datos del otro por ninguna ruta HTTP** | `npm test` cubre el recorrido completo y el intento cruzado falla | 5, 11, 12, 14 |

---

## Fase 2 · Catálogo y módulos

| # | Tarea | Hecho cuando | Dep. |
|---|---|---|---|
| 16 | Listar los siete módulos con el estado de cada uno para el usuario: activo, disponible o requiere suscripción | La respuesta distingue los tres estados sin que la interfaz tenga que deducirlos | 3, 13 |
| 17 | Listar el catálogo de un módulo, separando obligaciones sancionables de tareas recomendadas | La respuesta trae periodicidad, fuente normativa y **si esa fuente está verificada o no** | 16 |
| 18 | Activar y desactivar módulos gratuitos | Desactivar suspende el acceso y **no borra nada**: reactivar devuelve las obligaciones intactas | 16 |

---

## Fase 3 · Obligaciones del usuario

| # | Tarea | Hecho cuando | Dep. |
|---|---|---|---|
| 19 | Cálculo de vencimientos como función pura: primer vencimiento desde la fecha base con `desfase_primera`, y siguiente desde el anterior | Pruebas que cubren año bisiesto, el desfase de cinco años de la tecnomecánica y periodicidades en meses | 4 |
| 20 | Crear obligación desde el catálogo: copia el snapshot y genera la primera ocurrencia | Los datos del catálogo quedan copiados, no referenciados: cambiar el catálogo después no mueve este vencimiento | 3, 17, 18, 19 |
| 21 | Crear obligación libre, sin catálogo | El usuario define nombre, fecha y periodicidad propias | 20 |
| 22 | Listar obligaciones del usuario y las próximas a vencer | Ordenadas por vencimiento, con los días que faltan calculados contra `app.hoy()` y no contra el reloj del proceso | 20 |
| 23 | Editar una obligación: nombre, fecha base, periodicidad | Cambiar la fecha base recalcula la ocurrencia pendiente, y no toca las ya cumplidas | 22 |
| 24 | Marcar una ocurrencia como cumplida y **generar sola la siguiente** | Al cumplir, aparece la siguiente ocurrencia con la fecha correcta. La cumplida queda en el historial | 19, 22 |
| 25 | Archivar una obligación sin destruir su historial | La obligación desaparece de las vistas activas y sus ocurrencias siguen en la base | 22 |
| 26 | Confirmación explícita en toda acción destructiva | Ninguna ruta elimina o archiva sin una confirmación distinta de la propia acción | 25 |
| 27 | Prueba de la reprogramación automática a lo largo de varios ciclos | Cumplir tres veces seguidas produce tres vencimientos correctos y ningún duplicado | 24 |

---

## Fase 4 · El servicio de avisos

**Esta fase es el producto.** El criterio único de aceptación se gana o se pierde aquí; todo lo anterior es andamiaje para llegar.

Las tres capas —evaluación, envío y disparador— y por qué el disparador es un proceso aparte están en `docs/arquitectura.md`.

| # | Tarea | Hecho cuando | Dep. |
|---|---|---|---|
| 28 | Cliente SMTP hacia Mailpit | Un correo de prueba sale del proceso y aparece en la bandeja de `localhost:8025`. El camino completo ya está verificado con `scripts/verificar-mailpit.py` | 2, 4 |
| 29 | Plantilla del correo de aviso: qué vence, cuándo, de qué módulo y qué pasa si no se cumple | El correo se lee bien en texto plano, no solo en HTML. **Es lo primero que un usuario ve de Alivia**, antes que cualquier pantalla, así que el tono y el nombre que se fijen aquí son los que recoge el sistema visual de la tarea 70. No se decide una identidad por cada sitio | 28 |
| 30 | Consulta de las obligaciones que vencen **dentro de la ventana de anticipación de cada usuario**, con el rol `alivia_avisos` | La consulta parte de la anticipación, no del vencimiento. Buscar lo ya vencido es avisar tarde | 3, 22 |
| 31 | Proceso de evaluación diaria: selecciona, envía y **registra el resultado real del envío** | Un envío que falla queda como `fallido` con su error. Nada se marca `entregado` sin que el servidor SMTP lo haya aceptado | 29, 30 |
| 32 | Idempotencia verificada: correr la evaluación dos veces el mismo día no duplica avisos | La segunda ejecución no genera correos nuevos ni filas nuevas | 31 |
| 33 | Reintento de avisos fallidos, con tope de intentos | Un fallo transitorio se reintenta; uno permanente deja de consumir intentos y queda registrado | 31 |
| 34 | Comando de disparo bajo demanda, con fecha de referencia inyectable | `npm run avisos -- --fecha 2026-12-01` evalúa como si hoy fuera esa fecha. **Sin esto no hay sustentación posible** | 31 |
| 35 | Programación diaria en **su propio proceso**, como servicio del compose | La evaluación corre sola una vez al día y deja constancia de cada ejecución. El pool de `alivia_avisos` **no existe** en el proceso que atiende peticiones: es la decisión 5 de `docs/arquitectura.md`, y lo que impide que la regla 1 se anule por la puerta de atrás. Sin cron dentro del contenedor | 31 |
| 36 | **Prueba del criterio único de aceptación contra la API de Mailpit** | Se siembra un vencimiento, se corre la evaluación con fecha controlada y se verifica en la bandeja que el aviso existe, es del usuario correcto y **salió antes del vencimiento**. Es la prueba que no puede fallar nunca. El cruce por `Message-ID` exige el prefijo `message-id:` y sin corchetes angulares — ver `CLAUDE.md` | 5, 34 |
| 37 | Baja de avisos y frecuencia configurable, por la Ley 2300 de 2023 | El usuario desactiva los avisos y deja de recibirlos, sin perder sus datos | 14, 31 |

> **Hito.** Terminada la tarea 36, el producto cumple lo único con lo que se comprometió. Todo lo que viene después lo hace usable y vendible, pero el compromiso ya está cumplido y demostrable.

---

## Fase 5 · Suscripciones y pasarela simulada

No mueve dinero y no habla con ningún proveedor. Reproduce el flujo para demostrar la conversión.

| # | Tarea | Hecho cuando | Dep. |
|---|---|---|---|
| 38 | Simulador de pasarela: iniciar un pago | Queda un pago `iniciado` con su referencia única | 3, 13 |
| 39 | Cerrar el pago: aprobado, rechazado o expirado, los tres forzables | Los cuatro estados se pueden provocar a voluntad para demostrarlos | 38 |
| 40 | Crear la suscripción con vigencia al aprobar el pago | Un pago aprobado deja una suscripción con inicio y fin. Dos suscripciones del mismo módulo no se solapan: lo impide el motor | 39 |
| 41 | Activar un módulo de pago con suscripción vigente | Sin suscripción no se puede activar **por ninguna ruta**, incluida una petición hecha a mano | 18, 40 |
| 42 | Expiración de la suscripción: suspende el acceso y conserva los datos | Al expirar, el usuario deja de ver ese módulo; al renovar, sus obligaciones reaparecen intactas | 41 |
| 43 | Prueba del flujo completo de conversión | Pago, suscripción, activación, expiración y renovación, verificados de extremo a extremo | 41, 42 |

---

## Fase 6 · Interfaz web

El alcance pide no gastar esfuerzo en decoración, con una excepción declarada: **la configuración inicial y el primer aviso son los dos momentos de verdad**. Si la carga del catálogo confunde, el usuario abandona antes de recibir un solo aviso y el producto nunca demuestra para qué sirve. Las tareas 48 a 50 son ese momento, y la **70** es lo que les da con qué: una escala de urgencia y una distinción sancionable/recomendada que se lea sin depender del color. Está antes de la primera pantalla a propósito — definirla después obliga a improvisar estilos en el registro y a reescribirlos.

| # | Tarea | Hecho cuando | Dep. |
|---|---|---|---|
| 44 | Proyecto de interfaz en **`web/`**, con React y Vite y proxy al servidor | `npm run dev` sirve la interfaz y las llamadas al servidor funcionan sin configurar CORS. **Crear `web/` pone la integración continua en rojo** hasta que su servicio entre en `docker-compose.yml`: `scripts/verificar-arranque.py` exige que todo directorio con `package.json` tenga el suyo. No es un estorbo, es la regla 7 funcionando — una pieza que no está en el compose es una pieza que los otros tres no tienen. Va en el mismo cambio | 7 |
| 70 | **Sistema visual: tokens, escala de urgencia y distinción sancionable/recomendada** | Hay una paleta, una tipografía y una escala de espaciado declaradas en **un solo sitio**, y ninguna pantalla define un color propio. Dentro de eso, dos decisiones que no son decoración sino lo que la interfaz tiene que comunicar: una **escala de urgencia** según los días que faltan, y la distinción **sancionable / recomendada** resuelta con forma, texto o icono **además del color** — cerca del 8 % de los hombres tiene alguna deficiencia de visión al color, y confundir «te multan» con «conviene» es el peor error que puede cometer esta interfaz. El tono y el nombre ya los fijó el correo de la tarea 29: aquí se recogen, no se inventan otros | 44 |
| 45 | Cliente HTTP y manejo de sesión en la interfaz | El token se guarda, se envía en cada petición y se descarta al caducar, llevando al ingreso | 12, 13, 44 |
| 46 | Pantallas de registro e ingreso, con la autorización de tratamiento de datos explícita | No se puede crear una cuenta sin autorizar el tratamiento de forma deliberada. Una casilla premarcada no es autorización | 11, 45, 70 |
| 47 | Navegación y armazón de página, responsivo | Se usa en un teléfono sin desplazamiento horizontal. **El aspecto no se decide aquí**: los tokens y la paleta vienen de la 70. Aquí se resuelve el recorrido entre pantallas y la estructura que las envuelve | 46, 70 |
| 48 | Selección de áreas de la vida a gestionar | El usuario elige entre los siete módulos y ve cuáles son gratuitos | 16, 18, 47 |
| 49 | **Carga del catálogo al activar un área.** El momento en que se entrega el valor diferencial | Al activar «Vehículo», el usuario ve SOAT y tecnomecánica con sus plazos reales, distinguiendo lo sancionable de lo recomendado, **sin haber escrito nada** | 17, 48 |
| 50 | Ajuste de las fechas base y alta de las obligaciones elegidas | El usuario dice cuándo compró el carro y el sistema muestra el vencimiento que calculó | 20, 49 |
| 51 | Panel principal con las obligaciones próximas a vencer | Lo primero que se ve al entrar es qué vence pronto, ordenado por urgencia | 22, 47 |
| 52 | Vista por módulo | Se puede mirar un área concreta sin el ruido de las demás | 51 |
| 53 | Marcar cumplida desde la interfaz, mostrando la siguiente fecha | Al marcar cumplido, la interfaz dice cuándo vuelve a vencer. Es donde se ve que el producto piensa por el usuario | 24, 51 |
| 54 | Crear un recordatorio libre | Se puede añadir algo que no esté en el catálogo | 21, 52 |
| 55 | Preferencias de aviso en el perfil | Cambiar la ventana de anticipación y desactivar los avisos, desde la interfaz | 14, 37, 47 |
| 56 | Flujo de activación de un módulo de pago, con la pasarela simulada | El recorrido completo se demuestra sin salir de la máquina | 41, 52 |
| 57 | Confirmaciones destructivas en la interfaz | Archivar o desactivar pide confirmación y dice exactamente qué pasará con los datos | 26, 53 |

---

## Fase 7 · Cumplimiento, deuda y cierre

| # | Tarea | Hecho cuando | Dep. |
|---|---|---|---|
| 58 | Política de tratamiento de datos, redactada y accesible desde la aplicación | Se puede leer antes de autorizar, no después | 46 |
| 59 | Autorización separada para datos de salud, con negativa sin penalización | Quien no autoriza datos de salud **conserva el resto del servicio completo**. Es categoría especial bajo la Ley 1581 de 2012 | 48, 58 |
| 60 | Canal de consultas y reclamos del titular | Existe una vía documentada para ejercer los derechos de la ley, con sus plazos declarados | 58 |
| 61 | Carga del calendario tributario de **2027**, cuando se publique: predial de los municipios cubiertos y renta de la DIAN | El sistema deja de quedarse sin fechas. Los decretos se expiden hacia diciembre del año anterior, así que **antes de enero de 2027 no se puede hacer**: hasta entonces vale la fecha de referencia inyectada (D7) | 20, 49 |
| 62 | Validar con usuarios las anticipaciones sugeridas del catálogo | Los 30 días del SOAT y los 5 de la tarjeta dejan de ser criterio del equipo y pasan a estar respaldados | 23 |
| 63 | Carga de los cinco municipios del Valle de Aburrá que faltan (Bello, Envigado, Itagüí, La Estrella, Caldas) | Cada calendario se lee de su resolución, no de prensa. Solo lo comprobado queda marcado como verificado | 17 |
| 64 | Modelo de información documentado, derivado del esquema | Entregable 7 del alcance. Se genera del esquema real, no se redacta aparte | 61 |
| 65 | Semillas de demostración y guion de sustentación | Un comando deja la base en un estado que permite recorrer el producto entero delante de un jurado. **Fija `alivia.fecha_referencia` en una fecha de la primera mitad de 2026 y lo declara en el guion**: en noviembre no queda ninguna fecha futura de renta, y con el reloj real esa parte de la demostración no existe (D7) | 36, 43, 56 |
| 66 | Repaso final contra las siete reglas duras de `CLAUDE.md` | Cada regla tiene una prueba que la respalda, o una explicación de por qué no la tiene | 65 |

---

## Fase 8 · Administración del catálogo

**Fuera del alcance de esta etapa.** Está aquí para que quede planificado y con sus dependencias resueltas, no porque se vaya a construir ahora. El alcance dice explícitamente que el panel de administración no entra en esta etapa.

**Por qué está registrado en vez de dejarse como deuda:** no es un defecto, es trabajo que no se ha hecho. Hoy el catálogo se administra con SQL, y eso funciona mientras administre el equipo. Deja de funcionar en dos momentos concretos, los dos conocidos:

- **Cada enero**, cuando hay que recargar los calendarios tributarios del año nuevo: los de predial de cada municipio y el de renta de la DIAN. Son decretos que se expiden hacia diciembre, y sin ellos el sistema se queda sin fechas.
- **Cuando la curaduría deje de hacerla quien escribe SQL.** Corregir una fuente normativa o añadir una obligación no debería exigir acceso a la base de datos.

| # | Tarea | Hecho cuando | Dep. |
|---|---|---|---|
| 67 | Rol de administración separado, verificado en el servidor | Un usuario corriente no alcanza ninguna ruta de administración, ni siquiera con una petición hecha a mano. La verificación vive donde no se puede eludir, igual que la de los módulos de pago | 3, 13 |
| 68 | Panel de administración del catálogo: obligaciones, variantes y fuentes | Se puede corregir una fuente normativa, marcarla como verificada o añadir una obligación sin abrir la base de datos. Los cambios no alteran las obligaciones ya creadas por los usuarios, que guardan copia | 17, 47, 67 |
| 69 | Carga de calendarios territoriales desde el panel | Subir el calendario de un municipio o el de la DIAN para un año nuevo deja de ser una migración. Cada calendario cargado exige declarar su norma, y sólo se marca verificado lo que alguien leyó | 68 |

---

## Dos advertencias sobre este orden

### Las deudas del modelo ya están saldadas, y eso cambia el punto de partida

Cuando se escribió este backlog, las tareas 61 y 62 arreglaban defectos del modelo de datos —el predial y la renta calculados desde una fecha base inventada, la tecnomecánica sin distinguir carro de moto— y se advertía aquí de lo caro que salía dejarlos para el final.

**Se resolvieron antes de empezar la fase 0**, junto con la separación de fuentes y la ventana de anticipación por obligación. El detalle está en `docs/deuda-conocida.md`.

Lo que queda de aquellas tareas es carga de datos, no corrección de modelo: los calendarios de 2027 cuando se publiquen, los cinco municipios del Valle de Aburrá sin cargar, y la validación con usuarios de las anticipaciones sugeridas. Ninguna bloquea la construcción.

**Lo que sí conviene tener presente al construir:** los calendarios cargados sólo cubren **2026**, y no aguantan hasta enero. La renta se agota el **26 de octubre de 2026** y el predial el **31 de diciembre**. Como la sustentación es en noviembre, toda prueba y toda demostración que toque el calendario tributario **fija `alivia.fecha_referencia`**; con el reloj real, pasan hoy y fallan en noviembre. Aceptado a sabiendas como D7 en `docs/deuda-conocida.md`, con salida en enero de 2027.

### El producto está terminado en la tarea 36, no en la 66

El compromiso del proyecto es que el aviso llegue antes del vencimiento. Eso queda demostrado en la tarea 36, con treinta tareas por delante todavía.

Si el tiempo se acaba —y el cronograma son 114 días hábiles que no caben en un semestre—, lo que se recorta sale de las fases 5 a 7, nunca de la 4. Un producto sin interfaz bonita sigue siendo Alivia. Un producto que avisa tarde es otra cosa.
