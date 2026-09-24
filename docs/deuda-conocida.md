# Deuda conocida

Defectos y limitaciones **identificados y no resueltos**. No son descuidos: son decisiones de no arreglar algo todavía, con su costo anotado.

Cada entrada tiene un identificador estable (`D1`, `D2`…) al que el backlog hace referencia.

---

## D1 · El impuesto predial no es una obligación de periodicidad relativa

**Estado: saldado en el modelo el 24 de septiembre de 2026. Queda pendiente la carga de ocho municipios.**

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

**Solo dos de los diez municipios tienen calendario cargado**, porque son los dos cuya norma se leyó:

| Municipio | Norma | Estado |
|---|---|---|
| Medellín | Resolución 202550100057 del 9-dic-2025, art. 6 | **Verificado** |
| Copacabana | Resolución 2025000SHI2898 del 18-dic-2025, art. 1 | **Verificado** |
| Bello, Envigado, Itagüí, Sabaneta, La Estrella, Caldas, Girardota, Barbosa | — | **Sin cargar** |

Los ocho restantes **no se sembraron a propósito**. La información disponible venía de prensa y de agregadores que repiten las mismas fechas —«25 de abril / 11 de julio»— para Sabaneta, La Estrella y Girardota por igual, lo que es señal de copia y no de fuente. Este proyecto ya tuvo que corregir tres datos propagados desde prensa; no se repite el error.

Mientras no se carguen, sus usuarios usan recurrencia `declarada`: el sistema avisa, pero la fecha la pone el usuario.

**Y hay un límite de calendario:** solo existe el año 2026. El calendario de 2027 se publicará hacia diciembre de 2026 —el de 2026 se expidió el 9 de diciembre de 2025—, así que **este sistema se queda sin fechas en enero** salvo que alguien las recargue. El costo recurrente es de diez cargas anuales, no de una.

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
