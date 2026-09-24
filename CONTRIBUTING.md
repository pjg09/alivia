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

## Publicación de versiones

Cada envío a `main` dispara el flujo de `.github/workflows/release.yml`, que ejecuta [semantic-release](https://semantic-release.gitbook.io/):

1. Lee los commits desde la última etiqueta publicada.
2. Decide la versión según la tabla de arriba.
3. Genera `CHANGELOG.md` y actualiza la versión en `package.json`.
4. Crea la etiqueta y la publicación en GitHub con las notas.
5. Sube ese commit a `main` con `[skip ci]`, para no dispararse a sí mismo.

**Si ningún commit del envío es `feat`, `fix`, `perf`, `refactor` o `revert`, no se publica nada.** Es lo normal y no es un error: un envío de solo documentación no cambia la versión.

**No se publica a npm.** Este no es un paquete: la versión sirve para tener un historial legible y poder señalar en la sustentación qué había construido en cada momento.

### Verificar antes de subir

```bash
npx commitlint --from HEAD~1 --to HEAD --verbose   # ¿el mensaje cumple?
npx semantic-release --dry-run                     # ¿qué versión saldría?
```

## Historia anterior a la convención

Los diez primeros commits del repositorio son anteriores a esta convención y no la cumplen. **No se reescriben**: sus mensajes son descriptivos y el formato no vale perder ese contenido.

El punto de partida se marca con una etiqueta `v0.1.0` puesta a mano sobre el último de ellos, para que semantic-release analice solo lo que viene después:

```bash
git tag -a v0.1.0 <sha> -m "Punto de partida: esquema, calendarios y deuda saldada"
git push origin v0.1.0
```
