# Deuda conocida

Defectos y limitaciones **identificados y no resueltos**. No son descuidos: son decisiones de no arreglar algo todavía, con su costo anotado.

Cada entrada tiene un identificador estable (`D1`, `D2`…) al que el backlog hace referencia.

---

## D1 · RESUELTO — El impuesto predial no era una obligación de periodicidad relativa

**Resuelto el 24 de septiembre de 2026.** El modelo soporta ahora la recurrencia por calendario y hay cinco municipios cargados contra su resolución. Lo que queda abierto es carga de datos, no un defecto del modelo.

### Qué estaba mal

El modelo calculaba todo vencimiento como `fecha_base + periodicidad`, con la fecha base declarada por el usuario. El predial no funciona así: vence en fechas que fija cada municipio por norma.

### Lo que se encontró al investigar

Peor de lo que decía esta entrada. **No hay un patrón común entre municipios**, ni siquiera dentro del Valle de Aburrá:

| Municipio | Régimen |
|---|---|
| **Medellín** | Trimestral, **con fecha distinta por código sectorial** (20 sectores), y dos fechas por trimestre: sin recargo y con recargo. **168 fechas al año** |
| **Copacabana** | Trimestral, una sola fecha por trimestre, sin sectores |
| Bello | Trimestral, fecha única, distinta de la de Copacabana |
| Envigado | Semestral, con descuento por pronto pago |
| Sabaneta | Anual con descuento, más un sistema opcional de cuotas |

Cualquier esquema que supusiera «una fecha por municipio y año» se rompía con el primero.

Además, **las fechas se modifican durante el año**: Bello amplió el plazo del primer trimestre y Envigado extendió el suyo. Un calendario cargado puede quedar obsoleto a mitad de vigencia.

### Cómo quedó resuelto

Migración `009_recurrencia_por_calendario.sql`:

- `municipio`, `calendario_tributario` y `vencimiento_calendario`: una lista de fechas con segmento, etiqueta y tipo, que cada municipio llena según su propio régimen.
- `obligacion_usuario.tipo_recurrencia` distingue tres casos: `relativa` (SOAT), `calendario` (predial donde hay norma cargada) y `declarada` (el usuario pone la fecha).
- `app.proximo_vencimiento_calendario()` resuelve la siguiente fecha. **Sin calendario cargado no devuelve nada**, y quien llame debe caer a recurrencia declarada en lugar de inventar una fecha.
- Las fechas `con_recargo` existen como información pero **nunca generan aviso**: avisar de ellas es avisar de que ya se pagó de más.

Verificado en `db/pruebas/calendario.sql`, once comprobaciones contrastadas contra la norma citada.

### Lo que queda pendiente

**Cinco de los diez municipios tienen calendario cargado.** Solo se sembró lo leído en la resolución que lo fija:

| Municipio | Norma | Régimen | Estado |
|---|---|---|---|
| Medellín | Resolución 202550100057 del 9-dic-2025, art. 6 | Trimestral por sector, 20 sectores | **Verificado**, 84 fechas |
| Copacabana | Resolución 2025000SHI2898 del 18-dic-2025, art. 1 | Trimestral, fecha única | **Verificado** |
| Sabaneta | Resolución 2025015914 del 29-dic-2025, art. 1 | Trimestral, fecha única | **Verificado** |
| Barbosa | Resolución 3271 del 23-dic-2025 | Trimestral, con fecha de recargo | **Verificado** |
| Girardota | Resolución 4666 de 2025 | Semestral, descuentos del 10 % y 5 % | **Verificado** |
| Bello | — | — | Sin cargar: el PDF publicado es el de **2025** |
| Envigado | — | — | Sin cargar: el portal falla por certificado y devuelve páginas vacías |
| Itagüí | — | — | Sin cargar: no se localizó la norma de 2026 |
| La Estrella | — | — | Sin cargar |
| Caldas | — | — | Sin cargar |

### Por qué no se sembró lo que no se verificó

Porque al contrastarlo, **la prensa estaba mal en los dos casos comprobables**:

| | Lo que repetían los agregadores | Lo que dice la norma |
|---|---|---|
| Sabaneta | Anual, 10 % hasta el 25-abr, sin descuento hasta el 11-jul | **Trimestral**: 30-abr, 30-jun, 30-sep, 23-dic |
| Girardota | Lo mismo, palabra por palabra | **Semestral**: 10 % hasta 24-abr, 5 % hasta 19-jun, 2.º semestre 14-dic |

Los mismos agregadores daban ese texto idéntico para Sabaneta, La Estrella y Girardota. Era copia, y era falsa. Sembrarla habría producido avisos en fechas equivocadas, que es peor que no avisar.

Y el PDF que Bello publica como «calendario tributario» resultó ser el de la vigencia **2025**, radicado en diciembre de 2024. Cargarlo sin mirar habría metido las fechas del año anterior como si fueran las vigentes.

Los cinco municipios sin cargar usan recurrencia `declarada`: el sistema avisa, pero la fecha la pone el usuario.

### El límite que no se puede resolver trabajando más

**Solo existe el año 2026.** El calendario de 2027 se publicará hacia diciembre de 2026 — el de 2026 se expidió el 9 de diciembre de 2025 —, así que **este sistema se queda sin fechas en enero** salvo que alguien las recargue. El costo recurrente es de cinco a diez cargas anuales, no de una.

Además, **las fechas se modifican durante la vigencia**: Bello amplió el plazo del primer trimestre y Envigado extendió el suyo. Un calendario cargado puede quedar obsoleto sin que nadie se entere.

---

## D2 · RESUELTO — La declaración de renta dependía del NIT, no de una fecha base

**Resuelto el 24 de septiembre de 2026.**

### Qué estaba mal

El vencimiento de la declaración de renta de personas naturales lo fija un decreto nacional que se expide cada año, y la fecha concreta depende de los **dos últimos dígitos del NIT** del contribuyente, sin el dígito de verificación. No hay fecha base que el usuario pueda declarar de la que se derive su vencimiento, ni depende del municipio.

El catálogo la tenía sembrada como anual desde una fecha base. Era incorrecto.

### Cómo quedó resuelto

Migración `010_calendario_nacional.sql`. El modelo de calendario de D1 ya servía salvo por un supuesto: daba por hecho que todo calendario es municipal.

- `calendario_tributario.ambito` distingue `nacional` de `municipal`, y `municipio_dane` pasa a ser opcional.
- El `segmento` —que en Medellín es el código sectorial del predio— pasa a ser, para la renta, los dos últimos dígitos del NIT. La misma columna sirve para ambos.
- `app.proximo_vencimiento_calendario()` acepta municipio nulo como «calendario nacional».

Sembrado el calendario completo del año gravable 2025: **los 100 dígitos**, del 12 de agosto al 26 de octubre de 2026, según el [calendario tributario oficial de la DIAN](https://www.dian.gov.co/Calendarios/Calendario_Tributario_2026.pdf).

Antes de sembrar se comprobó que la tabla leída del PDF era coherente: 50 pares cubriendo 100 dígitos exactos, fechas estrictamente crecientes, ninguna en fin de semana, y los únicos días hábiles omitidos del rango son el 17 de agosto y el 12 de octubre —festivos en Colombia— más el 29 y 30 de septiembre, que la DIAN dejó sin asignar.

Verificado en `db/pruebas/renta.sql`, once comprobaciones.

### Lo que queda advertido

**El decreto se expide cada año.** Igual que con el predial, este calendario solo cubre 2026 y el sistema se queda sin fechas después.

**Las excepciones territoriales no están cargadas.** El Decreto 1226 del 18 de agosto de 2026 fijó plazos especiales para contribuyentes de seis departamentos afectados por el terremoto del 10 de agosto de 2026. Un usuario de esas zonas tiene una fecha distinta a la que muestra el sistema. Es el mejor recordatorio de que un calendario cargado puede dejar de ser cierto sin previo aviso.

**Los dos últimos dígitos del NIT son un dato personal** que el usuario tendrá que declarar, y entra bajo el mismo régimen de tratamiento que el resto.

### Un aviso sobre las fuentes secundarias

Varias publicaciones especializadas citaban el **Decreto 2229 de 2023** como norma de plazos para el año gravable 2025, lo que no cuadra con que se expida un decreto por año. Y una lectura automática del micrositio de la DIAN devolvió una tabla de diez fechas que empezaba el 8 de agosto, cuando el plazo empieza el 12 y reparte dos dígitos por día hábil. Ninguna de las dos se usó: lo sembrado viene del PDF del calendario oficial.

---

## D3 · RESUELTO — La tecnomecánica no distinguía carro de motocicleta

**Resuelto el 24 de septiembre de 2026.**

### Qué estaba mal

El catálogo guardaba un solo `desfase_primera`, el de carros particulares. **Un motociclista habría recibido su primer aviso al quinto año en lugar del segundo: tres años tarde**, con tres años de multa posible por delante.

### Lo que dice la norma, ya verificada

| Artículo | Texto vigente según | Qué establece |
|---|---|---|
| **51** · periodicidad | art. 201 del Decreto 019 de 2012 | «todos los vehículos automotores deben someterse **anualmente** a revisión técnico-mecánica y de emisiones contaminantes» |
| **52** · primera revisión | art. 179 de la **Ley 2294 de 2023** | Particular distinto de motocicleta: **a partir del quinto (5.º) año**. Servicio público y motocicletas: **al cumplir dos (2) años** |

**Aviso para quien vuelva sobre esto:** el artículo 12 de la **Ley 1383 de 2010** dice que todo vehículo nuevo se revisa a los dos años, sin distinguir tipo. Está superado por la Ley 2294 de 2023. Quien consulte esa ley sin mirar las modificaciones posteriores sembrará el dato mal — es justo lo que estuvo a punto de pasar aquí.

### Cómo quedó resuelto

Migración `011_variantes_de_obligacion.sql`:

- `variante_obligacion`: una misma obligación con plazos distintos según un atributo del bien. Tres variantes sembradas: particular, motocicleta y servicio público.
- `obligacion_catalogo.atributo_variante` declara qué debe elegir el usuario (`tipo_vehiculo`). NULL en las obligaciones que no tienen variantes, que son casi todas.
- Un **disparador** impide crear la obligación sin declarar la variante cuando el catálogo la exige, y rechaza una variante que pertenezca a otra obligación. No es un CHECK porque cruza tablas; y no se deja a la aplicación porque olvidarlo una vez significa avisar del vehículo equivocado.

Verificado en `db/pruebas/variantes.sql`, doce comprobaciones. Entre ellas el caso que motivaba la deuda: una moto matriculada en marzo de 2026 vence en **marzo de 2028**, y un carro de la misma fecha en **marzo de 2031**.

### Efecto lateral sobre D4

La tecnomecánica pasa a ser **la primera entrada del catálogo con `fuente_verificada = true`**, porque su fuente se leyó en el texto vigente de la norma y no en un resumen.

---

## D4 · RESUELTO — Ninguna fuente normativa estaba verificada

**Resuelto el 24 de septiembre de 2026.** Resultó ser una deuda de modelo, no de datos.

### Qué se encontró al ir a verificar

El alcance (§5.2) pide que cada obligación declare «la fuente normativa que respalda esa periodicidad». Al verificarlas una por una en el texto de cada norma, aparece que **para la mayoría esa fuente no existe**. El campo confundía tres cosas distintas:

1. Qué norma hace la obligación **obligatoria**.
2. Qué norma fija la **sanción** por incumplirla.
3. Qué fija la **fecha** — y esto último muchas veces no es una norma.

| Obligación | Obligatoriedad | Sanción | Quién fija la fecha |
|---|---|---|---|
| SOAT | Ley 769/2002, art. 42 | art. 131 **D.2**, 30 SMLDV | **La póliza.** El código de tránsito no menciona la vigencia anual |
| Tecnomecánica | Ley 769/2002, arts. 51-52 | art. 131 **C.35**, 15 SMLDV | **La norma.** La única del catálogo entera |
| Predial | Acuerdo municipal | Intereses de mora | **Calendario municipal** |
| Renta | Estatuto Tributario | Extemporaneidad | **Calendario DIAN** |
| Antirrábica | Decreto 2257/1986, arts. 33 y 55 | Autoridad sanitaria | **Lineamiento.** El decreto delega la periodicidad en los ministerios |
| Servicios públicos | Ley 142/1994 | art. 140, suspensión | **La factura de cada empresa** |
| Tarjeta de crédito | — | Contrato | **El contrato.** No hay norma |
| Matrícula escolar | — | Reglamento | **Cada institución** |

**De ocho obligaciones sancionables, sólo una tiene su plazo fijado por una norma.** Guardar todo eso en un campo llamado `fuente_normativa` obliga a mentir o a dejarlo vacío.

### Dos datos rescatados

Los literales **D.2** («conducir sin portar los seguros ordenados por la ley», 30 SMLDV) y **C.35** («no realizar la revisión técnico-mecánica en el plazo legal», 15 SMLDV) son los que `revision.md` de la Entrega 1 había **retirado del documento por venir de prensa**. Quedan confirmados en el texto del artículo 131, modificado por el artículo 21 de la Ley 1383 de 2010. Pueden volver al documento académico.

### Cómo quedó resuelto

Migración `012_fuentes_separadas.sql`:

- `fuente_normativa` pasa a significar sólo «norma que hace la obligación obligatoria».
- `fuente_sancion` recoge la norma o el contrato que fija la consecuencia.
- `origen_plazo` dice de dónde sale la fecha: `norma`, `calendario`, `contrato`, `factura`, `institucion` o `practica`.
- La restricción que exigía fuente normativa a toda sancionable **se reemplazó**: codificaba el supuesto falso. Ahora se exige que declare su consecuencia, que es lo que de verdad impide que se cuele una tarea doméstica disfrazada de obligación.

Las ocho sancionables quedan con `fuente_verificada = true`, leídas en el Gestor Normativo de Función Pública. Las 32 recomendadas declaran `origen_plazo = 'practica'`: no tienen norma porque no hay sanción, y marcarlas como «sin verificar» sugeriría que existe algo que verificar.

Verificado en `db/pruebas/fuentes.sql`, doce comprobaciones.

### Lo que sigue sin verificar, y se declara

- **La vigencia anual del SOAT.** Se sabe que la fija la póliza; no se localizó la norma que la establece.
- **El monto de la multa por no vacunar contra la rabia.** Los «hasta $500.000» que circulan vienen de blogs.
- **El artículo del Estatuto Tributario** que fija la sanción por extemporaneidad.
- **La periodicidad anual del refuerzo antirrábico** sale de lineamiento del Ministerio de Salud, no del decreto. No se leyó el lineamiento.

---

## D5 · La ventana de anticipación es única por usuario

**Gravedad: baja.**

No se puede pedir aviso con 30 días para el SOAT y 3 para el pago de una tarjeta de crédito, aunque las dos cosas tengan urgencias distintas.

**Qué haría falta:** una columna opcional en `obligacion_usuario` que tenga prioridad sobre la preferencia del usuario. Es barato y no rompe nada; simplemente no hacía falta todavía.

---

## D6 · El catálogo se administra con SQL

**Gravedad: baja, y es alcance declarado.**

No hay interfaz de administración. Corregir una entrada del catálogo es escribir una migración. El alcance exige que el catálogo sea administrable **sin volver a publicar la aplicación**, y lo es —es un dato, no una constante del código—, pero administrarlo requiere acceso a la base de datos.

Construir el panel de administración está fuera del alcance de esta etapa.
