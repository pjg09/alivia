-- Verificacion del aislamiento entre usuarios. Se ejecuta como alivia_app,
-- que es el rol con el que se conecta la API.
--
--   psql "$DATABASE_URL" -f db/pruebas/rls.sql
--
-- Toda linea que diga FALLA es un defecto.
--
-- ATENCION al patron: cada bloque va dentro de BEGIN/COMMIT. El contexto de
-- usuario se fija con set_config(..., true), que es LOCAL A LA TRANSACCION.
-- Una API en autocommit pierde el contexto entre la sentencia que lo fija y la
-- que consulta, y no ve absolutamente nada. Esto no es una peculiaridad de la
-- prueba: es como hay que escribir el acceso a datos en la aplicacion.

\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on

-- --- 1. Sin contexto de usuario no se ve nada -------------------------------
BEGIN;
  SELECT CASE WHEN count(*) = 0 THEN 'ok    sin contexto no hay usuarios visibles'
              ELSE 'FALLA sin contexto se ven ' || count(*) || ' usuarios' END FROM usuario;
  SELECT CASE WHEN count(*) = 0 THEN 'ok    sin contexto no hay obligaciones visibles'
              ELSE 'FALLA sin contexto se ven ' || count(*) || ' obligaciones' END FROM obligacion_usuario;
COMMIT;

-- --- 2. Con contexto se ve solo lo propio -----------------------------------
BEGIN;
  SELECT set_config('alivia.usuario_id',
    (SELECT id::text FROM app.credenciales_por_correo('ana@prueba.local')), true) \gset ctx_
  SELECT CASE WHEN count(*) = 1 THEN 'ok    ana ve exactamente una cuenta: la suya'
              ELSE 'FALLA ana ve ' || count(*) || ' cuentas' END FROM usuario;
  SELECT CASE WHEN count(*) > 0 AND bool_and(nombre LIKE 'ANA%')
              THEN 'ok    ana ve ' || count(*) || ' obligaciones, todas suyas'
              ELSE 'FALLA ana ve obligaciones ajenas o ninguna' END FROM obligacion_usuario;
COMMIT;

-- --- 3. Cambiar de usuario cambia lo que se ve ------------------------------
BEGIN;
  SELECT set_config('alivia.usuario_id',
    (SELECT id::text FROM app.credenciales_por_correo('beto@prueba.local')), true) \gset ctx_
  SELECT CASE WHEN count(*) > 0 AND bool_and(nombre LIKE 'BETO%')
              THEN 'ok    beto ve ' || count(*) || ' obligaciones, todas suyas'
              ELSE 'FALLA beto ve obligaciones ajenas o ninguna' END FROM obligacion_usuario;
COMMIT;

-- --- 4. No se puede escribir en nombre de otro ------------------------------
BEGIN;
  SELECT set_config('alivia.usuario_id',
    (SELECT id::text FROM app.credenciales_por_correo('beto@prueba.local')), true) \gset ctx_
  DO $$
  BEGIN
    INSERT INTO obligacion_usuario (usuario_id, modulo_codigo, origen, nombre, tipo_exigibilidad, fecha_base)
    SELECT id, 'hogar', 'libre', 'ROBADA', 'recomendada', DATE '2026-01-01'
    FROM app.credenciales_por_correo('ana@prueba.local');
    RAISE NOTICE 'FALLA beto escribio una obligacion a nombre de ana';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'ok    beto no puede escribir a nombre de ana';
  END $$;
ROLLBACK;

-- --- 5. Modulo de pago sin suscripcion vigente ------------------------------
BEGIN;
  SELECT set_config('alivia.usuario_id',
    (SELECT id::text FROM app.credenciales_por_correo('beto@prueba.local')), true) \gset ctx_
  DO $$
  BEGIN
    INSERT INTO obligacion_usuario (usuario_id, modulo_codigo, origen, nombre, tipo_exigibilidad, fecha_base)
    VALUES (app.usuario_actual(), 'salud', 'libre', 'SIN PAGAR', 'recomendada', DATE '2026-01-01');
    RAISE NOTICE 'FALLA beto creo una obligacion de pago sin suscripcion';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'ok    modulo de pago bloqueado sin suscripcion vigente';
  END $$;
ROLLBACK;

-- --- 6. El reloj inyectable mueve la vigencia -------------------------------
-- Ana tiene suscripcion a salud del 2026-01-01 al 2027-01-01.
BEGIN;
  SELECT set_config('alivia.usuario_id',
    (SELECT id::text FROM app.credenciales_por_correo('ana@prueba.local')), true) \gset ctx_
  SELECT set_config('alivia.fecha_referencia', '2026-06-15', true) \gset f_
  SELECT CASE WHEN app.tiene_acceso(app.usuario_actual(), 'salud')
              THEN 'ok    dentro de vigencia hay acceso a salud'
              ELSE 'FALLA dentro de vigencia no hay acceso' END;
  SELECT CASE WHEN count(*) > 0 THEN 'ok    dentro de vigencia ve ' || count(*) || ' obligacion de salud'
              ELSE 'FALLA dentro de vigencia no ve salud' END
  FROM obligacion_usuario WHERE modulo_codigo = 'salud';
COMMIT;

BEGIN;
  SELECT set_config('alivia.usuario_id',
    (SELECT id::text FROM app.credenciales_por_correo('ana@prueba.local')), true) \gset ctx_
  SELECT set_config('alivia.fecha_referencia', '2027-06-15', true) \gset f_
  SELECT CASE WHEN NOT app.tiene_acceso(app.usuario_actual(), 'salud')
              THEN 'ok    fuera de vigencia no hay acceso a salud'
              ELSE 'FALLA suscripcion expirada sigue dando acceso' END;
  -- El alcance exige que expirar suspenda el acceso, no que borre el dato.
  SELECT CASE WHEN count(*) = 0 THEN 'ok    expirada, ana deja de ver salud'
              ELSE 'FALLA expirada y sigue viendo salud' END
  FROM obligacion_usuario WHERE modulo_codigo = 'salud';
COMMIT;

-- --- 7. Los datos sobreviven a la expiracion --------------------------------
BEGIN;
  SELECT set_config('alivia.usuario_id',
    (SELECT id::text FROM app.credenciales_por_correo('ana@prueba.local')), true) \gset ctx_
  SELECT set_config('alivia.fecha_referencia', '2026-06-15', true) \gset f_
  SELECT CASE WHEN count(*) > 0 THEN 'ok    renovada, las obligaciones de salud reaparecen intactas'
              ELSE 'FALLA los datos se perdieron al expirar' END
  FROM obligacion_usuario WHERE modulo_codigo = 'salud';
COMMIT;

-- --- 8. El propietario NO debe usarse como rol de la API --------------------
-- Comprobacion de que alivia_app no tiene por donde saltarse las politicas.
BEGIN;
  SELECT CASE WHEN NOT rolbypassrls AND NOT rolsuper
              THEN 'ok    alivia_app no tiene BYPASSRLS ni es superusuario'
              ELSE 'FALLA alivia_app puede ignorar las politicas' END
  FROM pg_roles WHERE rolname = current_user;
COMMIT;
