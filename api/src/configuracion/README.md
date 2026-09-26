# `api/src/configuracion/`

Lectura y validación del entorno **al arrancar**. Si falta una variable obligatoria, el proceso muere con un mensaje que dice cuál y qué hacer, en lugar de fallar más tarde y en otro sitio.

| Fichero | Qué es |
|---|---|
| `entorno.ts` | Primitivas: lectura del `.env`, precedencia, acumulación de problemas |
| `servidor.ts` | El esquema del proceso que atiende peticiones |
| `avisos.ts` | El esquema del proceso de avisos |
| `comprobar.ts` | `npm run configuracion` — valida y sale, sin arrancar nada |

## Cuatro decisiones que no son obvias

**Dos esquemas, no uno.** El del servidor **no declara `DATABASE_URL_AVISOS`**, y el de avisos no declara `DATABASE_URL` ni `JWT_SECRETO`. El rol `alivia_avisos` tiene `SELECT` sobre las obligaciones de todos los usuarios; si el servidor pudiera construir ese pool, el aislamiento entre usuarios quedaría anulado por la puerta de atrás, sin un solo error y sin que ninguna prueba de RLS se enterara. Decisión 2 de `docs/arquitectura.md`, comprobada por `scripts/verificar-arquitectura.py`.

**Del `.env` se leen solo las variables que el esquema declara.** El `.env` es del proyecto entero y lleva las URLs de los tres roles. Cargarlo completo mete en el proceso la del propietario, que ignora RLS: es la misma fuga que `docker-compose.yml` tiene prohibida con `env_file`, ocurriendo dentro del proceso.

**Se informan todos los problemas de una vez.** Morir en el primero obliga a arrancar, leer, corregir y repetir tantas veces como variables falten, que es exactamente lo que hace que nadie configure bien nada.

**`JWT_SECRETO` distingue ausente de inválido, y es el único que lo hace.** Ausente se genera uno aleatorio con aviso de que las sesiones no sobreviven a un reinicio; con el valor de plantilla de `.env.example`, el proceso muere. Es lo único que deja convivir la regla 7 —arranca sin `.env`—, el rechazo del valor de plantilla y la prohibición de secretos en el repositorio. Una URL de base de datos ausente no se inventa.

## El rol también se valida

Una URL que conecta con el rol equivocado no da ningún error: simplemente deja de aislar. Aquí se comprueba que la del servidor use `alivia_app` y la de avisos `alivia_avisos`, así que el descuido se nota al arrancar. Regla 1 de `CLAUDE.md`.
