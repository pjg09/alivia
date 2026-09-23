-- 001 · Esquema de apoyo, roles de conexion y reloj inyectable.
--
-- Tres roles con separacion de privilegios:
--   alivia_propietario  dueño de las tablas, aplica migraciones. NUNCA lo usa la aplicacion.
--   alivia_app          la API. SUJETO a RLS. Es el rol del que depende todo el aislamiento.
--   alivia_avisos       el proceso de avisos. Lee obligaciones de todos los usuarios,
--                       con permisos acotados y sin atender peticiones web.
--
-- Ninguno tiene BYPASSRLS. El aislamiento no debe depender de que nadie recuerde nada.

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS btree_gist; -- restricciones de no solapamiento de vigencias

CREATE SCHEMA IF NOT EXISTS app;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'alivia_app') THEN
    CREATE ROLE alivia_app LOGIN PASSWORD 'desarrollo';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'alivia_avisos') THEN
    CREATE ROLE alivia_avisos LOGIN PASSWORD 'desarrollo';
  END IF;
END
$$;

GRANT USAGE ON SCHEMA public, app TO alivia_app, alivia_avisos;

-- ---------------------------------------------------------------------------
-- Reloj inyectable
-- ---------------------------------------------------------------------------
-- Todo el producto es aritmetica de fechas. Si la logica consulta la fecha del
-- sistema, no hay forma de probar una ventana de anticipacion de 30 dias sin
-- cambiarle la hora al computador, ni de demostrarla en una sustentacion.
--
-- La fecha de referencia se inyecta por transaccion:
--   SELECT set_config('alivia.fecha_referencia', '2026-12-01', true);
--
-- Sin inyeccion devuelve el dia civil colombiano, que es lo correcto en
-- operacion normal: los vencimientos son fechas de calendario en Colombia,
-- no instantes.

CREATE OR REPLACE FUNCTION app.hoy() RETURNS date
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    NULLIF(current_setting('alivia.fecha_referencia', true), '')::date,
    (now() AT TIME ZONE 'America/Bogota')::date
  );
$$;

COMMENT ON FUNCTION app.hoy() IS
  'Fecha de referencia del sistema. Inyectable con alivia.fecha_referencia. Nunca usar CURRENT_DATE en logica de vencimientos.';

-- ---------------------------------------------------------------------------
-- Identidad del usuario dentro de la transaccion
-- ---------------------------------------------------------------------------
-- La API fija esto al abrir cada transaccion, antes de cualquier consulta:
--   SELECT set_config('alivia.usuario_id', $1, true);
--
-- Devuelve NULL si no se fijo. Las politicas comparan contra este valor, y una
-- comparacion con NULL no es verdadera: una consulta sin contexto no devuelve
-- filas en lugar de devolverlas todas. Falla cerrado, que es como debe fallar.

CREATE OR REPLACE FUNCTION app.usuario_actual() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('alivia.usuario_id', true), '')::uuid;
$$;

COMMENT ON FUNCTION app.usuario_actual() IS
  'Usuario de la transaccion en curso. NULL si no se fijo: las politicas RLS entonces no devuelven filas.';

-- Control de migraciones aplicadas.
CREATE TABLE IF NOT EXISTS app.migracion_aplicada (
  nombre      text PRIMARY KEY,
  aplicada_en timestamptz NOT NULL DEFAULT now()
);
