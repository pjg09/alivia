# alivia

Plataforma de recordatorios de las obligaciones de la vida adulta en Colombia: llega con el catálogo de vencimientos ya construido y avisa antes de que se cumpla el plazo.

## Criterio único de aceptación

> **El aviso debe llegar antes del vencimiento, no después.**

Todo lo que se construye aquí se mide contra eso.

## Arrancar el ambiente

Requisitos: Docker, Node 20 o superior.

```bash
cp .env.example .env          # ajustar JWT_SECRETO
docker compose up -d          # PostgreSQL + Mailpit
./db/aplicar.sh               # migraciones
./db/aplicar.sh --semillas    # catálogo base y usuarios de prueba
```

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
| `docs/modelo-datos.md` | Las decisiones de modelado y por qué |
| `db/pruebas/rls.sql` | Verificación del aislamiento entre usuarios |
| `CLAUDE.md` | Reglas del dominio que el código debe cumplir |

## Documentación del proyecto

Este repositorio contiene **el código**. El alcance, la formulación y los entregables académicos viven en el repositorio `gestion-de-proyectos`, y `docs/proyecto/alcance-tecnico.md` manda sobre cualquier cosa escrita aquí.
