# El ambiente

## La regla

> **`npm run arrancar` deja Alivia utilizable en una máquina recién clonada.**
> Todo lo que corre está en `docker-compose.yml`, y se añade ahí en el mismo cambio que lo crea.

Sin pasos manuales después y sin `.env`. Si hace falta algo más, el ambiente está roto, aunque funcione en la máquina de quien lo escribió.

```bash
git clone … && cd alivia
npm run arrancar
./scripts/verificar-todo.sh
```

Lo que deja hecho hoy: PostgreSQL con las trece migraciones aplicadas, el catálogo y los usuarios de prueba sembrados, y Mailpit escuchando.

## Cómo se espera a un servicio efímero, y por qué cuesta

```bash
docker compose up -d --wait --build
```

`up --wait` espera a que los servicios estén **sanos o corriendo**. A un servicio efímero —uno que corre, termina y sale, como `migraciones`— le basta con haber arrancado, así que `--wait` devuelve con el contenedor todavía dentro. Medido: con un efímero de 12 segundos, devolvió 0 a los 6. Las pruebas corrían entonces contra una base a medio poblar y fallaban de forma intermitente, que es la peor clase de fallo porque parece mala suerte.

### Y `--build`, que no es opcional

`up` construye una imagen **solo si no existe**. Sin `--build`, cambiar código del servidor y arrancar levanta el binario anterior: el síntoma es «no se aplicó mi cambio» y se persigue durante media hora antes de sospechar del contenedor. Con la caché de capas, reconstruir sin cambios cuesta un par de segundos.

`scripts/verificar-arranque.py` lo deriva: si algún servicio tiene `build`, el arranque documentado lleva `--build`.

Hay **dos formas** de esperar a un efímero de verdad, y no son intercambiables:

**(a) Por dependencia, que es la que usamos.** Un servicio con `healthcheck` declara `depends_on` sobre el efímero con `condition: service_completed_successfully`. El dependiente no arranca hasta que el efímero acaba **bien**, y `--wait` espera a que el dependiente esté sano. Así, esperar a que `api` esté sano implica que el esquema está aplicado:

```yaml
  api:
    depends_on:
      migraciones:
        condition: service_completed_successfully
    healthcheck: …
```

**(b) Con `docker compose wait <servicio>`**, añadido al arranque. Sirve cuando ningún servicio depende del efímero.

**(b) deja de funcionar en cuanto existe (a)**, y este proyecto ya se tropezó con eso: `docker compose wait` responde `no containers for project` y sale con **1** cuando el contenedor ya terminó, que es justo lo que ocurre si un dependiente lo esperó primero. El arranque fallaba con todo bien. Por eso `scripts/verificar-arranque.py` **deriva el arranque del compose**: mira qué efímeros hay, cuáles están cubiertos por (a), y exige esa línea exacta en el README, `CLAUDE.md`, este documento, `CONTRIBUTING.md`, la CI y `package.json` — y que no quede un `compose wait` de más.

### Lo que este arranque no cubre

Una migración nueva sobre una pila **ya levantada**. Compose vuelve a ejecutar el efímero, pero no recrea `api`, así que `--wait` devuelve al instante y el servidor sigue corriendo con el esquema viejo. Para eso:

```bash
npm run actualizar     # docker compose up -d --wait --build --force-recreate
```

Recrea los contenedores, con lo que el efímero se vuelve a ejecutar **y** `api` vuelve a esperarlo. Los datos no se tocan: viven en el volumen.

## El contrato: qué debe declarar un servicio

Al añadir una pieza que corre —el servidor, la interfaz, el proceso de avisos— el servicio va en `docker-compose.yml` con:

| Qué | Por qué |
|---|---|
| `healthcheck` | `--wait` necesita saber cuándo está listo. Sin él, las pruebas corren contra un servicio a medio arrancar y fallan de forma intermitente, que es la peor clase de fallo. **Y que no mienta:** `pg_isready` sin `-h` pasa contra el servidor temporal de la inicialización de postgres, que escucha solo en el socket unix, y declara la base lista antes de que acepte conexiones TCP |
| `labels: alivia.rol-bd` | Con qué rol de base de datos corre: `app`, `avisos`, `propietario` o `motor`. Sostiene la regla 1 de `CLAUDE.md` |
| `labels: alivia.efimero: "true"` | Solo si corre, termina y sale, como `migraciones`. Exime del `healthcheck` y exige `restart: "no"` |
| `build` con `context` | Si la pieza se construye del repositorio. Un directorio de primer nivel con `package.json` o `Dockerfile` tiene que tener su servicio, o el verificador se pone rojo |
| Puertos como `"${PUERTO_X:-N}:N"` | Un puerto fijo hace que `up` falle en una máquina donde ya esté ocupado, sin forma de moverlo. La variable se documenta en `.env.example` |
| `depends_on` con `condition` | El orden de arranque no se deja al azar |

**Lo que el verificador impide, no solo recomienda:**

- Un servicio que se construye del repositorio **no puede** correr como `propietario` ni `motor`. Esos roles ignoran RLS por completo, en silencio y sin un solo error, y dejan a un usuario viendo los datos de otro. Es la regla 1 de `CLAUDE.md` aplicada al ambiente: el día que el servicio `api` exista, conectarlo como propietario deja de ser un descuido invisible y pasa a ser una prueba en rojo.
- Un `Dockerfile` que ningún servicio construye. Una imagen que nadie levanta no es parte del ambiente.
- Un puerto `localhost:N` en cualquier fichero del proyecto que el compose no publique. Es exactamente la deriva que ya pasó.

## Un servicio declara sus variables. No se le pasa el `.env`

La forma obvia es un error, y no por comodidad:

```yaml
# MAL, dos veces.
env_file: .env
```

**Primero**, `.env` está en `.gitignore`, así que no existe en un clon limpio ni en la integración continua, y `docker compose up` falla antes de arrancar nada. Eso ya rompe la regla 7.

**Y segundo, que es lo grave:** el `.env` es del **proyecto entero** y lleva las URLs de los tres roles. Pasárselo a un servicio le entrega también la del propietario, que ignora RLS por completo, y la de avisos, que ve los datos de todos los usuarios. Es la decisión 2 de `docs/arquitectura.md` rota por la puerta de atrás, sin un solo error y sin que ninguna prueba de RLS se entere.

No es hipotético. Al añadir el servicio `api` con `env_file: .env`, el contenedor recibía:

```
DATABASE_URL_MIGRACIONES = postgres://alivia_propietario:…    <- ignora RLS
DATABASE_URL_AVISOS      = postgres://alivia_avisos:…         <- ve todos los usuarios
JWT_SECRETO              = cambiar-en-cada-maquina            <- la tarea 2 mata el proceso
```

Lo atrapó `scripts/verificar-arranque.py`, y desde entonces lo comprueba de forma determinista: **ningún servicio usa `env_file`**. Se mira la clave en el texto y no la configuración resuelta, porque docker mete el contenido de `env_file` dentro de `environment`: en una máquina sin `.env` el rastro desaparece y la fuga se volvería invisible justo donde nadie la mira.

**La forma correcta:** el servicio declara lo que necesita, una variable a una, y lo que deba poder ajustarse entra por sustitución con su nombre.

```yaml
    environment:
      PUERTO: 3001
      TZ: America/Bogota
      DATABASE_URL: postgres://alivia_app:${POSTGRES_CONTRASENA:-desarrollo}@postgres:5432/alivia
```

Dos detalles de esa misma lista:

- **Las URLs de dentro de la red van escritas aquí**, porque el anfitrión es el nombre del servicio y no `localhost`. Las del `.env` apuntan a `localhost` y sirven para lo que corre en la máquina: `psql`, los verificadores, `npm run dev`.
- **`TZ: America/Bogota`**, como ya lo lleva postgres. Sin eso, una fecha civil puede desplazarse un día al serializarse — decisión 3 de `docs/arquitectura.md`.

El `.env` sí lo lee el compose, pero para **sustituir** `${...}`, no para metérselo a nadie dentro.

## Dónde vive cada valor

Un valor, un sitio. Los demás lo leen del entorno.

| Valor | Fuente de verdad | Lo leen |
|---|---|---|
| Puertos publicados | `docker-compose.yml` | `.env.example`, los scripts y la CI, vigilados por `verificar-arranque.py` |
| URLs de conexión | `.env.example` como valores por defecto | `db/aplicar.sh`, `scripts/verificar-todo.sh` |
| Esquema y catálogo | `db/migraciones/` y `db/semillas/` | el servicio `migraciones` |

**El entorno gana sobre el `.env`.** Los scripts rellenan del `.env` solo lo que no venga ya exportado. Sin eso, un `.env` con `localhost:5434` montado dentro de un contenedor pisa la URL que le pasa compose —cuyo anfitrión es `postgres`, no `localhost`— y la conexión falla. Es la razón de que `migraciones` monte solo `./db` y no el repositorio entero.

## Cuando la integración continua empiece a tardar

Hoy el trabajo de verificación tarda alrededor de un minuto, porque los tres servicios son imágenes que se descargan. En cuanto `api/` y `web/` tengan su `Dockerfile`, cada ejecución construye dos imágenes de Node sin caché, y eso son varios minutos.

**Lo que no se hace para arreglarlo:** quitar el `build` de la CI, o volver a montar los servicios con `services:` de GitHub Actions, o levantar solo la base de datos y correr el servidor con `npm`. Cualquiera de esas tres deshace la única garantía fuerte que tenemos de que el compose funciona: que la CI arranca con él y con nada más. Y las tres son tentadoras justo cuando alguien tiene prisa.

**Lo que sí se hace,** el día que moleste de verdad: caché de capas de buildx entre ejecuciones (`cache-from`/`cache-to` con el almacén de GitHub Actions). No cambia lo que se construye ni cómo, solo lo reutiliza.

## Correr una segunda pila en paralelo

Para probar el arranque desde cero sin destruir la base de trabajo:

```bash
export PUERTO_POSTGRES=5499 PUERTO_SMTP=1099 PUERTO_MAILPIT=8099 PUERTO=3099
docker compose -p aliviaprueba up -d --wait --build
```

Choca con los `container_name` fijos. Hay que anularlos con un fichero de superposición, o quitarlos del compose si alguna vez estorban más de lo que ayudan.

## Reiniciar

```bash
docker compose down            # para los contenedores, conserva los datos
docker compose down -v         # DESTRUYE el volumen de PostgreSQL
npm run arrancar               # vuelve a aplicar todo desde cero
```

`./db/aplicar.sh --reiniciar` hace lo mismo con el esquema sin tocar el volumen, y pide confirmación porque destruye datos (regla 6 de `CLAUDE.md`).
