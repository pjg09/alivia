# `api/pruebas/`

Lo que ejecuta `npm test`. Y definir ese guion en `package.json` es **todo** lo que hace falta para que la integración continua las corra: `scripts/verificar-todo.sh` lo descubre solo.

```bash
npm test
```

| Ruta | Qué es |
|---|---|
| `arnes/ejecutar.ts` | Lo que corre `npm test`: prepara, lanza y limpia |
| `arnes/nombres.ts` | De dónde sale cada URL, y por qué la base de trabajo no aparece en ninguna |
| `arnes/base.ts` | La base efímera de cada fichero, y las fixtures con privilegios |
| `arnes/mantenimiento.ts` | La conexión de administración, con diagnóstico de puertos ajenos |
| `*.prueba.ts` | Las pruebas. Se descubren por el patrón: no hay lista que mantener |

## «Deja la base como la encontró»: no tocándola

Hay dos formas de cumplirlo: limpiar después, o no tocarla nunca. La segunda es la única que sobrevive a que una prueba se caiga a mitad, y es la que se usa. **El arnés no se conecta a la base de trabajo en ningún momento.**

1. Crea `alivia_plantilla_pruebas` y le aplica migraciones y semillas con el **mismo `db/aplicar.sh`** que usa todo el mundo. Una sola implementación: si se aplican mal aquí, se aplican mal en todas partes.
2. Lanza el ejecutor de Node. **Cada fichero se copia su propia base de la plantilla**, en su propio proceso: `CREATE DATABASE … TEMPLATE …` copia ficheros en lugar de ejecutar veintitrés `.sql`, así que sale casi gratis.
3. Borra la plantilla y cualquier base suelta, pase lo que pase. Y si algo quedó, **falla**: la siguiente ejecución arrancaría sobre restos y «desde cero» dejaría de ser verdad.

Por eso «cada prueba corre contra una base limpia» no es una aspiración: lo que un fichero escribe **no existe** para los demás, porque están en bases distintas. Nadie limpia nada — la base entera se borra.

Comprobado midiendo antes y después: los datos de la base de trabajo no cambian y no queda ninguna base de prueba.

## Las pruebas corren con `alivia_app`, no con el propietario

A propósito, y es la decisión que hace que valgan algo. `alivia_app` **está sujeto a RLS**; el propietario la ignora por completo, así que con él cualquier prueba de aislamiento pasaría sin comprobar nada.

De ahí que una prueba **no pueda abrir su propia conexión**: `scripts/verificar-arquitectura.py` falla si un `*.prueba.ts` importa `pg`. Las consultas van por `conUsuario()` y `sinContextoDeUsuario()`.

Cuando una fixture necesita privilegios —leer el identificador de un usuario sembrado, contar migraciones aplicadas— usa `comoPropietario()`, que vive en `arnes/` justamente para que la excepción esté en un sitio y no repartida. Una fixture puede tener privilegios que el servidor no tiene; lo que no puede es **afirmar** con ellos.

## Un puerto publicado no es una identidad

`arnes/mantenimiento.ts` lo comprueba antes de crear nada, y existe por media hora perdida: con el contenedor de Alivia parado, otro proyecto de la misma máquina se quedó con el puerto, y todo devolvía `password authentication failed for user "alivia_propietario"`. El mensaje era correcto y no servía de nada — la causa no era la contraseña.

Ahora el arnés distingue tres casos y dice qué hacer en cada uno: nadie contesta, contesta otro postgres, o contesta el correcto sin el esquema aplicado.

## Las trece de RLS, y por qué están dos veces

`rls.prueba.ts` porta las trece comprobaciones de `db/pruebas/rls.sql`. **No es una copia por gusto:** las de SQL demuestran que las *políticas* aíslan; estas demuestran que `conUsuario()` las *respeta*. Entre una cosa y la otra está todo lo que puede ir mal en la aplicación — conectar con el rol equivocado, perder el contexto, abrir la transacción donde no toca — y es justo lo que las de SQL no pueden ver.

Los nombres siguen los de `rls.sql` para poder cruzarlas.

El criterio de la tarea 5 es que `npm test` falle si alguien conecta con el rol equivocado o pierde el contexto. Se comprobó provocando las dos cosas:

| Sabotaje | Resultado |
|---|---|
| La URL de la aplicación cambiada a `alivia_propietario` | 8 pruebas en rojo |
| `conUsuario()` dejando de fijar `alivia.usuario_id` | 7 pruebas en rojo |

La primera es la que importa entender: **con el rol propietario todas las pruebas de aislamiento pasarían**, porque ignora las políticas. La que lo delata es la que afirma `current_user = 'alivia_app'` y que no tiene `BYPASSRLS`. Sin ella, el resto del fichero daría una falsa tranquilidad.

## Añadir una prueba

Un fichero `*.prueba.ts` bajo `api/pruebas/`, con `before`/`after` abriendo y cerrando su base:

```ts
let base: BaseEfimera;
before(async () => { base = await abrirBaseEfimera(); });
after(async () => { await base.cerrar(); });
```

Si necesita **otra fecha de referencia**, va en su propio fichero: `abrirBaseEfimera({ fechaReferencia: '2026-03-15' })`. Dos fechas distintas en el mismo fichero compartirían base y una de las dos vería la de la otra.
