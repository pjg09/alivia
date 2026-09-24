# alivia

Plataforma de recordatorios de las obligaciones de la vida adulta en Colombia: llega con el catálogo de vencimientos ya construido y avisa antes de que se cumpla el plazo.

## Criterio único de aceptación

> **El aviso debe llegar antes del vencimiento, no después.**

Todo lo que se construye aquí se mide contra eso.

## Arrancar el ambiente

Requisitos: Docker y Node 22 o superior. La integración continua usa Node 24.

```bash
npm run arrancar              # y ya: base de datos, esquema, catálogo y correo
./scripts/verificar-todo.sh   # comprobar que todo quedó bien
```

**En cualquier máquina, sin pasos manuales después.** No hace falta `.env`: los valores por defecto están en el propio compose. Se copia `.env.example` a `.env` solo para apartarse de ellos.

`npm run arrancar` es exactamente esto, y se puede escribir a mano:

```bash
docker compose up -d --wait && docker compose wait migraciones
```

Son dos órdenes porque `up --wait` espera a que los servicios estén *sanos o corriendo*, y a un servicio que corre, termina y sale —como el que aplica las migraciones— le basta con haber arrancado: devuelve antes de que acabe. Está medido, y está explicado en [`docs/ambiente.md`](docs/ambiente.md).

Eso no es una buena intención, es un contrato comprobado: la integración continua arranca con este mismo fichero y `scripts/verificar-arranque.py` se pone rojo si el compose se queda atrás del código.

| Servicio | Dónde | Para qué |
|---|---|---|
| PostgreSQL | `localhost:5434` | Base de datos |
| Mailpit (web) | http://localhost:8025 | Bandeja única: aquí llegan **todos** los correos de **todos** los usuarios |
| Mailpit (SMTP) | `localhost:1025` | Adonde escribe la aplicación |

No hay despliegue. Todo corre en la máquina de cada integrante.

## Estructura

| Ruta | Contenido |
|---|---|
| `db/migraciones/` | Esquema, en orden. Fuente de verdad del modelo de datos |
| `db/semillas/` | Catálogo base y datos de prueba |
| `docs/ambiente.md` | El contrato del arranque con un solo comando |
| `CONTRIBUTING.md` | Flujo de trabajo y convención de commits |
| `docs/backlog.md` | Qué falta por construir, en orden de dependencias |
| `docs/modelo-datos.md` | Las decisiones de modelado y por qué |
| `docs/deuda-conocida.md` | Lo que estuvo mal a sabiendas y cómo se corrigió |
| `db/pruebas/` | Pruebas de base de datos. Se descubren solas: ver `CONTRIBUTING.md` |
| `scripts/` | Verificadores del proyecto y el ejecutor de todas las pruebas |
| `CLAUDE.md` | Reglas del dominio que el código debe cumplir |

## Cómo se contribuye

Se trabaja directamente sobre `main`. Los mensajes de commit siguen [Conventional Commits](https://www.conventionalcommits.org/es/v1.0.0/) y deciden la versión que se publica en cada envío. Todo está en [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Documentación del proyecto

Este repositorio contiene **el código**. El alcance, la formulación y los entregables académicos viven en el repositorio `gestion-de-proyectos`, y `docs/proyecto/alcance-tecnico.md` manda sobre cualquier cosa escrita aquí.
