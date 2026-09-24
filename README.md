# alivia

Plataforma de recordatorios de las obligaciones de la vida adulta en Colombia: llega con el catálogo de vencimientos ya construido y avisa antes de que se cumpla el plazo.

## Criterio único de aceptación

> **El aviso debe llegar antes del vencimiento, no después.**

Todo lo que se construye aquí se mide contra eso.

## Arrancar el ambiente

Requisitos: Docker y Node 22 o superior. La integración continua usa Node 24.

```bash
cp .env.example .env          # ajustar JWT_SECRETO
docker compose up -d          # PostgreSQL + Mailpit
./db/aplicar.sh               # migraciones
./db/aplicar.sh --semillas    # catálogo base y usuarios de prueba
./scripts/verificar-todo.sh   # comprobar que todo quedó bien
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
