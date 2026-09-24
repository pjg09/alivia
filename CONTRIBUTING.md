# Cómo se trabaja en este repositorio

## Flujo

**Se trabaja directamente sobre `main`.** Sin ramas, sin solicitudes de fusión, sin revisión previa a la integración.

Es una decisión consciente para un equipo de cuatro personas con dedicación parcial y un plazo corto: el coste de coordinar ramas supera aquí al de integrarlas. Lo que sí es obligatorio:

- **Actualizar antes de subir.** `git pull --rebase` antes de cada `git push`. La publicación automática escribe en `main` (ver más abajo), así que quien no actualice se encontrará el envío rechazado.
- **Subir trabajo que aplica desde cero.** Verificar con `./db/aplicar.sh --reiniciar && ./db/aplicar.sh --semillas`, nunca de forma incremental. Ya ha pasado dos veces que algo funcionaba en una base ya sembrada y fallaba en una instalación limpia.
- **No subir nada que deje las comprobaciones en rojo.** Si hace falta subirlo igualmente, decirlo en el mensaje del commit.

## Convención de mensajes de commit

Se usa [Conventional Commits](https://www.conventionalcommits.org/es/v1.0.0/). No es una preferencia de estilo: **el mensaje decide la versión que se publica**, y un mensaje mal escrito publica una versión equivocada o ninguna.

```
<tipo>(<ámbito opcional>): <descripción en imperativo>

<cuerpo opcional, explicando el porqué>

<pie opcional: BREAKING CHANGE, Refs, Closes>
```

**Los tipos van en inglés** aunque todo lo demás del repositorio esté en español: son identificadores que leen las herramientas, igual que `CREATE TABLE`. La descripción y el cuerpo van en español.

### Tipos, y qué versión publica cada uno

| Tipo | Para qué | Versión |
|---|---|---|
| `feat` | Funcionalidad nueva para el usuario | **minor** — 0.3.1 → 0.4.0 |
| `fix` | Corrección de un defecto | **patch** — 0.3.1 → 0.3.2 |
| `perf` | Mejora de rendimiento | **patch** |
| `refactor` | Cambio interno sin alterar el comportamiento | **patch** |
| `docs` | Solo documentación | ninguna |
| `test` | Solo pruebas | ninguna |
| `build` | Dependencias, empaquetado, contenedores | ninguna |
| `ci` | Flujos de integración continua | ninguna |
| `chore` | Tareas de mantenimiento que no encajan arriba | ninguna |
| `style` | Formato, espacios, punto y coma | ninguna |
| `revert` | Revierte un commit anterior | **patch** |

### Cambios que rompen compatibilidad

Un `!` después del tipo, o un pie `BREAKING CHANGE:`, publican una versión **major**:

```
feat(db)!: la obligación exige declarar el tipo de vehículo

BREAKING CHANGE: las obligaciones de tecnomecánica creadas antes de este
cambio no tienen variante y hay que migrarlas.
```

En un proyecto que aún no ha llegado a 1.0.0, un cambio que rompe compatibilidad sube la *minor*, no la *major*.

### Ámbitos

Opcionales, pero conviene usarlos. Los de este proyecto:

| Ámbito | Qué toca |
|---|---|
| `db` | Esquema, migraciones, políticas de seguridad a nivel de fila |
| `catalogo` | Catálogo de obligaciones, variantes, fuentes |
| `calendario` | Calendarios territoriales: predial, renta |
| `auth` | Registro, ingreso, sesión |
| `avisos` | Evaluación diaria, correo, registro de envíos |
| `pagos` | Suscripciones y pasarela simulada |
| `api` | Servidor y sus rutas |
| `web` | Interfaz |
| `infra` | Contenedores, entorno, scripts |

### Ejemplos

```
feat(avisos): envía el aviso de anticipación por correo

fix(db): el contexto de usuario se pierde fuera de la transacción

La API abría la transacción después de fijar alivia.usuario_id, así que las
consultas no veían ninguna fila en lugar de dar error.

docs: corrige el alcance sobre la fuente normativa de la periodicidad

feat(catalogo)!: separa obligatoriedad, sanción y origen del plazo

BREAKING CHANGE: fuente_normativa deja de significar "lo que fija la fecha".
```

### Reglas de redacción

- **Descripción en imperativo y en presente**: «añade», no «añadido» ni «añadiendo».
- **Sin punto final** en la descripción.
- **Máximo 72 caracteres** en la primera línea.
- **El cuerpo explica el porqué**, no el qué: el qué ya está en el diff.
- **Un commit, un cambio.** Si el mensaje necesita una «y», probablemente son dos commits.

### Lo que no se pone en los commits

**Nada de coautoría ni enlaces de sesión de herramientas de IA.** Ni `Co-Authored-By:`, ni referencias a la sesión que generó el cambio. El historial registra qué cambió y por qué, no con qué se escribió.

## El ambiente se actualiza en el mismo cambio

**Si el cambio añade una pieza que corre, el cambio añade su servicio a `docker-compose.yml`.** No en un envío posterior, no «cuando esté más estable»: en el mismo. El contrato es que `npm run arrancar` deje el proyecto utilizable en una máquina recién clonada, y una pieza que no está ahí es una pieza que los otros tres no tienen.

No hace falta acordarse. `scripts/verificar-arranque.py` se pone rojo en cuanto exista un directorio con `package.json` o `Dockerfile` que ningún servicio construya, y la integración continua arranca con ese mismo compose, así que un compose incompleto no publica versión.

Qué tiene que declarar un servicio nuevo —healthcheck, rol de base de datos, puerto movible— está en [`docs/ambiente.md`](docs/ambiente.md). Es la regla 7 de `CLAUDE.md`.

## Pruebas

**Todas las pruebas se corren en cada envío a `main`, y ninguna versión se publica si alguna falla.** El trabajo de publicación depende del de verificación y no hay forma de saltárselo.

En local, lo mismo con un comando:

```bash
./scripts/verificar-todo.sh              # contra el ambiente que ya tienes
./scripts/verificar-todo.sh --reiniciar  # recreando el esquema desde cero
```

### Dónde va una prueba nueva

**No hay una lista de pruebas que mantener.** Se descubren por dónde están, así que una prueba nueva entra en la integración continua sola, sin tocar el flujo de trabajo ni ningún registro:

| Dónde | Qué | Cómo se ejecuta |
|---|---|---|
| `db/pruebas/*.sql` | Pruebas de base de datos: esquema, políticas, datos | `psql`, una por fichero |
| `scripts/verificar-*.py` | Verificadores del proyecto: orden del backlog, camino del aviso | `python3`, y su código de salida decide |
| `npm test` | Pruebas de la aplicación: unitarias y de integración | En cuanto `package.json` defina el script |

Poner una prueba en otro sitio equivale a que nadie la corra. Si hace falta una categoría nueva, se añade al descubrimiento en `scripts/verificar-todo.sh`, no al flujo de trabajo.

### Cómo se escribe una prueba de base de datos

Imprimen `ok` o `FALLA` por comprobación; **no devuelven código de error**, así que el ejecutor busca la palabra `FALLA` en la salida. Tres cosas cuentan como fallo:

- Alguna línea dice `FALLA`.
- `psql` termina con error, por ejemplo por sintaxis inválida.
- El fichero **no produjo ninguna comprobación**. Una prueba que no comprueba nada suele ser una prueba rota, no una prueba que pasa.

Corren con el rol `alivia_app`, que es con el que se conecta la API y el que está sujeto a las políticas de seguridad. Si una prueba necesita otro rol, lo declara en sus primeras líneas:

```sql
-- @rol: propietario
```

Usar el propietario salta las políticas de aislamiento, así que sólo se justifica para pruebas que administran el catálogo.

## Publicación de versiones

Cada envío a `main` dispara el flujo de `.github/workflows/release.yml`, que ejecuta [semantic-release](https://semantic-release.gitbook.io/):

1. Lee los commits desde la última etiqueta publicada.
2. Decide la versión según la tabla de arriba.
3. Genera `CHANGELOG.md` y actualiza la versión en `package.json`.
4. Crea la etiqueta y la publicación en GitHub con las notas.
5. Sube ese commit a `main` con `[skip ci]`, para no dispararse a sí mismo.

**Antes de publicar se verifica.** El flujo levanta PostgreSQL y Mailpit, aplica el esquema desde cero y corre todas las pruebas. Si algo falla, no se publica: el trabajo de publicación declara `needs: verificar`.

**Si ningún commit del envío es `feat`, `fix`, `perf`, `refactor` o `revert`, no se publica nada.** Es lo normal y no es un error: un envío de solo documentación no cambia la versión.

**No se publica a npm.** Este no es un paquete: la versión sirve para tener un historial legible y poder señalar en la sustentación qué había construido en cada momento.

### Verificar antes de subir

```bash
./scripts/verificar-todo.sh                        # ¿está todo en verde?
npx commitlint --from HEAD~1 --to HEAD --verbose   # ¿el mensaje cumple?
npx semantic-release --dry-run                     # ¿qué versión saldría?
```

Y si el cambio tocó el ambiente, desde cero, que es lo que verá la CI:

```bash
docker compose down -v && docker compose up -d --wait && docker compose wait migraciones && ./scripts/verificar-todo.sh
```

## Historia anterior a la convención

Los diez primeros commits del repositorio son anteriores a esta convención y no la cumplen. **No se reescriben**: sus mensajes son descriptivos y el formato no vale perder ese contenido.

El punto de partida está marcado con la etiqueta **`v0.1.0`** sobre el último de ellos, para que semantic-release analice sólo lo que viene después. Sin esa etiqueta, el primer `feat` publicaría `1.0.0`, que prometería una estabilidad que el proyecto no tiene; con ella, sube por `0.x` mientras se construye.

**La etiqueta se envía junto con `main`, o antes.** Enviar `main` sin ella dispara el flujo, no encuentra etiqueta previa y publica `1.0.0`:

```bash
git push origin main --follow-tags
```

**`--follow-tags` hace falta solo en ese primer envío.** Envía las etiquetas anotadas creadas en local, y `v0.1.0` es la única que se crea a mano: todas las siguientes las crea semantic-release dentro del flujo de trabajo, así que ya nacen en el remoto y viajan en sentido contrario — las recibes al actualizar. Usarlo siempre no molesta: si no hay etiquetas locales nuevas, no hace nada. Quien no quiera acordarse:

```bash
git config push.followTags true   # una vez, en cada máquina
```

### El ritmo del día a día

Lo que sí ocurre en cada envío no son las etiquetas, sino esto: **cuando se publica una versión, el remoto queda con un commit que tú no tienes** — el `chore(release)` con el `CHANGELOG.md` y la versión de `package.json`. Sin actualizar antes, el siguiente envío se rechaza.

```bash
git pull --rebase && git push
```

Trabajando cuatro personas directamente sobre `main`, pasa a menudo. No es un problema: es la consecuencia de que la versión salga del historial.
