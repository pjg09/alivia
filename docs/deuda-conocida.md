# Deuda conocida

Defectos y limitaciones **identificados y no resueltos**. No son descuidos: son decisiones de no arreglar algo todavía, con su costo anotado.

Cada entrada tiene un identificador estable (`D1`, `D2`…) al que el backlog hace referencia.

---

## D1 · El impuesto predial no es una obligación de periodicidad relativa

**Gravedad: alta.** Afecta a una de las cinco obligaciones emblema del producto.

### Qué está mal

El modelo calcula el vencimiento como `fecha_base + periodicidad`, donde `fecha_base` es un dato que declara el usuario. El predial no funciona así: **vence en una fecha del calendario fijada por el acuerdo de cada municipio**, igual para todos los contribuyentes de ese municipio, y con fechas de descuento por pronto pago que también son municipales.

Hoy el catálogo lo tiene sembrado como `interval '1 year'` desde una fecha base del usuario. Eso significa que si alguien declara que compró su casa el 10 de marzo, el sistema le avisará cada 10 de marzo — una fecha que **no tiene ninguna relación** con el vencimiento real del predial en su municipio.

### Por qué importa

El alcance cita cinco casos una y otra vez: SOAT, tecnomecánica, predial, renta y controles médicos. El predial es uno de ellos, y está en un módulo gratuito, que es donde el producto promete cubrir la multa evitable.

Un aviso en la fecha equivocada no es un aviso imperfecto: es peor que no avisar, porque el usuario confía y no revisa.

### Qué haría falta

Un segundo tipo de recurrencia, por calendario en lugar de por intervalo:

- Un campo que distinga `recurrencia_relativa` (SOAT: un año desde que compré) de `recurrencia_calendario` (predial: la fecha que dice el municipio).
- Una tabla de fechas oficiales por año y por ámbito — en este caso, municipio.
- Un atributo del usuario que diga en qué municipio está el inmueble.
- Curaduría de esas fechas, que es trabajo de investigación, no de programación.

### Mientras tanto

**El predial no debería presentarse al usuario como una fecha calculada por el sistema.** Las dos salidas honestas son dejar que el usuario declare él mismo la fecha de vencimiento que le corresponde, o retirar la entrada del catálogo hasta que se pueda hacer bien.

---

## D2 · La declaración de renta depende del NIT, no de una fecha base

**Gravedad: alta.** Mismo problema que D1, con un agravante.

### Qué está mal

El vencimiento de la declaración de renta de personas naturales lo fija el **calendario tributario que la DIAN publica cada año**, y la fecha concreta depende de los **últimos dígitos del NIT** de cada contribuyente. No hay ninguna fecha base que el usuario pueda declarar de la que se derive su vencimiento.

El catálogo la tiene sembrada como anual desde una fecha base. Es incorrecto.

### El agravante

A diferencia del predial, cuya fecha es estable de año en año dentro de un municipio, **el calendario tributario cambia todos los años** y se publica por decreto. Una tabla de fechas sembrada una vez queda obsoleta en el siguiente ciclo.

### Qué haría falta

Lo mismo que D1, más:

- El usuario declara los dos últimos dígitos de su NIT. Es un dato personal más y necesita su tratamiento.
- Una carga anual de las fechas del calendario tributario, que alguien tiene que hacer y mantener.
- Decidir qué hace el sistema cuando llega el año siguiente y el calendario aún no está cargado. Callarse es mejor que avisar mal.

### Mientras tanto

Igual que D1: que el usuario declare su fecha, o retirar la entrada.

---

## D3 · La tecnomecánica no distingue carro de motocicleta

**Gravedad: media.**

La primera revisión se exige al **quinto año** en carros particulares y al **segundo** en motocicletas. El campo `desfase_primera` soporta un solo valor por entrada del catálogo, y está sembrado con el de carros.

Un motociclista recibiría su primer aviso tres años tarde.

**Qué haría falta:** variantes de una misma obligación según un atributo del bien que el usuario declara, o entradas separadas en el catálogo con un campo que indique a qué tipo de vehículo aplican.

---

## D4 · Ninguna fuente normativa está verificada

**Gravedad: media, y es el trabajo que le da valor al producto.**

Las 40 entradas del catálogo tienen `fuente_verificada = false`. Ocho están marcadas como sancionables y su fuente dice literalmente «artículo sin verificar» o «pendiente».

El diferenciador declarado del producto es el catálogo curado con respaldo normativo. Hoy el respaldo no existe: hay una cita de la ley pero no el artículo, y nadie lo comprobó contra la norma.

**Qué haría falta:** curaduría contra las fuentes primarias, y poner `fuente_verificada = true` solo en lo que efectivamente se comprobó.

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
