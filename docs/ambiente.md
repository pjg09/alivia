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

## Por qué el arranque son dos órdenes

```bash
docker compose up -d --wait && docker compose wait migraciones
```

`up --wait` espera a que los servicios estén **sanos o corriendo**. A un servicio efímero —uno que corre, termina y sale, como `migraciones`— le basta con haber arrancado, así que `--wait` devuelve con el contenedor todavía dentro. Medido: con un efímero de 12 segundos, `up --wait` devolvió 0 a los 6. Las pruebas corrían entonces contra una base a medio poblar y fallaban de forma intermitente, que es la peor clase de fallo porque parece mala suerte.

`docker compose wait migraciones` bloquea hasta que el contenedor termina y devuelve su código de salida. Lo que sí hace `up --wait` es detectar que un efímero salió con error: devuelve 1. Lo único que no hace es esperar al éxito.

Y un `up` posterior vuelve a ejecutar el efímero ya terminado, así que una migración nueva sobre una pila ya levantada se aplica con el mismo arranque.

`scripts/verificar-arranque.py` **deriva ese comando del compose**: cuenta los servicios etiquetados `alivia.efimero` y exige que el arranque espere a cada uno, en el README, en `CLAUDE.md`, en este documento, en la CI y en `package.json`. Añadir un efímero sin esperarlo pone las cinco comprobaciones en rojo.

## Por qué no basta con escribirla

Esta regla ya se rompió una vez en este repositorio, y sin que nadie hiciera nada mal a propósito: la integración continua montaba su propio ambiente con `services:` de GitHub Actions, en el puerto 5432, mientras `.env.example` declaraba 5434. Dos copias de la misma verdad, divergiendo en silencio. Nada estaba en rojo.

Por eso la regla se sostiene sobre tres cosas, y solo la tercera es un documento:

1. **La integración continua arranca con este compose y no con otra cosa.** No hay un segundo ambiente que pueda derivar. Si el compose está roto, la CI está roja y no se publica versión.
2. **`scripts/verificar-arranque.py` comprueba el contrato de abajo.** Entra solo en `verificar-todo.sh` por estar en `scripts/` y llamarse `verificar-*.py`. No hay ninguna lista que actualizar.
3. **Este documento**, que explica el porqué. No comprueba nada.

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

## La trampa de `env_file`: cómo se rompe el arranque sin `.env`

Un servicio que se construye del repositorio necesita sus variables. La forma obvia rompe el contrato:

```yaml
# MAL. Si no hay .env --y no lo hay en un clon limpio ni en la CI--
# `docker compose up` falla antes de arrancar nada.
env_file: .env
```

`.env` está en `.gitignore`, así que **no existe en una máquina recién clonada**, que es justo el caso que la regla 7 promete. La forma correcta lo declara opcional:

```yaml
    env_file:
      - path: .env
        required: false     # sin él, valen los valores de abajo
    environment:
      DATABASE_URL: postgres://alivia_app:${POSTGRES_CONTRASENA:-desarrollo}@postgres:5432/alivia
      TZ: America/Bogota
```

Dos cosas más de esa misma lista:

- **`environment` gana sobre `env_file`.** Las URLs de dentro de la red de contenedores van en `environment`, porque el anfitrión es el nombre del servicio y no `localhost`. Si vinieran del `.env` de la máquina, apuntarían a `localhost` y no resolverían.
- **`TZ: America/Bogota`**, como ya lo lleva postgres. Sin eso, una fecha civil puede desplazarse un día al serializarse — decisión 3 de `docs/arquitectura.md`.

## Dónde vive cada valor

Un valor, un sitio. Los demás lo leen del entorno.

| Valor | Fuente de verdad | Lo leen |
|---|---|---|
| Puertos publicados | `docker-compose.yml` | `.env.example`, los scripts y la CI, vigilados por `verificar-arranque.py` |
| URLs de conexión | `.env.example` como valores por defecto | `db/aplicar.sh`, `scripts/verificar-todo.sh` |
| Esquema y catálogo | `db/migraciones/` y `db/semillas/` | el servicio `migraciones` |

**El entorno gana sobre el `.env`.** Los scripts rellenan del `.env` solo lo que no venga ya exportado. Sin eso, un `.env` con `localhost:5434` montado dentro de un contenedor pisa la URL que le pasa compose —cuyo anfitrión es `postgres`, no `localhost`— y la conexión falla. Es la razón de que `migraciones` monte solo `./db` y no el repositorio entero.

## Correr una segunda pila en paralelo

Para probar el arranque desde cero sin destruir la base de trabajo:

```bash
export PUERTO_POSTGRES=5499 PUERTO_SMTP=1099 PUERTO_MAILPIT=8099
docker compose -p aliviaprueba up -d --wait && docker compose -p aliviaprueba wait migraciones
```

Choca con los `container_name` fijos. Hay que anularlos con un fichero de superposición, o quitarlos del compose si alguna vez estorban más de lo que ayudan.

## Reiniciar

```bash
docker compose down            # para los contenedores, conserva los datos
docker compose down -v         # DESTRUYE el volumen de PostgreSQL
npm run arrancar               # vuelve a aplicar todo desde cero
```

`./db/aplicar.sh --reiniciar` hace lo mismo con el esquema sin tocar el volumen, y pide confirmación porque destruye datos (regla 6 de `CLAUDE.md`).
