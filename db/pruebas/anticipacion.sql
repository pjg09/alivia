-- Verificacion de la ventana de anticipacion (deuda D5).
--
--   psql "$DATABASE_URL" -f db/pruebas/anticipacion.sql
--
-- La precedencia tiene que ser inequivoca: manda lo que el usuario fijo para
-- esa obligacion; si no fijo nada, manda su preferencia general. La sugerencia
-- del catalogo es solo eso, una sugerencia para la interfaz.

\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on

BEGIN;
  SELECT set_config('alivia.usuario_id',
    (SELECT id::text FROM app.credenciales_por_correo('ana@prueba.local')), true) \gset ctx_

  -- Ana tiene 15 dias de anticipacion general.
  SELECT CASE WHEN (SELECT dias_anticipacion FROM usuario WHERE id = app.usuario_actual()) = 15
              THEN 'ok    ana tiene 15 dias de anticipacion general'
              ELSE 'FALLA la semilla de ana cambio' END;

  -- Sin anticipacion propia, la obligacion hereda la del usuario.
  SELECT CASE WHEN app.anticipacion_efectiva(
                   (SELECT id FROM obligacion_usuario WHERE usuario_id = app.usuario_actual()
                    AND dias_anticipacion IS NULL LIMIT 1)) = 15
              THEN 'ok    sin anticipacion propia se hereda la del usuario'
              ELSE 'FALLA no esta heredando la preferencia general' END;
COMMIT;

-- --- La anticipacion propia manda sobre la general -------------------------
BEGIN;
  SELECT set_config('alivia.usuario_id',
    (SELECT id::text FROM app.credenciales_por_correo('ana@prueba.local')), true) \gset ctx_

  UPDATE obligacion_usuario SET dias_anticipacion = 45
  WHERE id = (SELECT id FROM obligacion_usuario WHERE usuario_id = app.usuario_actual() LIMIT 1);

  SELECT CASE WHEN app.anticipacion_efectiva(
                   (SELECT id FROM obligacion_usuario WHERE usuario_id = app.usuario_actual()
                    AND dias_anticipacion = 45 LIMIT 1)) = 45
              THEN 'ok    la anticipacion de la obligacion manda sobre la general'
              ELSE 'FALLA la anticipacion propia no tiene precedencia' END;
ROLLBACK;

-- --- Cambiar la preferencia general no pisa lo que el usuario fijo ---------
BEGIN;
  SELECT set_config('alivia.usuario_id',
    (SELECT id::text FROM app.credenciales_por_correo('ana@prueba.local')), true) \gset ctx_

  UPDATE obligacion_usuario SET dias_anticipacion = 3
  WHERE id = (SELECT id FROM obligacion_usuario WHERE usuario_id = app.usuario_actual() LIMIT 1);
  UPDATE usuario SET dias_anticipacion = 60 WHERE id = app.usuario_actual();

  SELECT CASE WHEN app.anticipacion_efectiva(
                   (SELECT id FROM obligacion_usuario WHERE usuario_id = app.usuario_actual()
                    AND dias_anticipacion = 3 LIMIT 1)) = 3
              THEN 'ok    cambiar la general no pisa la de una obligacion'
              ELSE 'FALLA la preferencia general sobrescribe la especifica' END;
ROLLBACK;

-- --- La sugerencia del catalogo NO es un valor de respaldo -----------------
-- Si lo fuera, quien decide seria ambiguo. Decide el usuario, siempre.
BEGIN;
  SELECT set_config('alivia.usuario_id',
    (SELECT id::text FROM app.credenciales_por_correo('ana@prueba.local')), true) \gset ctx_

  SELECT CASE WHEN (SELECT dias_anticipacion_sugeridos FROM obligacion_catalogo
                    WHERE codigo='vehiculo.soat') = 30
              THEN 'ok    el catalogo sugiere 30 dias para el SOAT'
              ELSE 'FALLA la sugerencia del SOAT no esta sembrada' END;

  -- El SOAT de ana no tiene anticipacion propia: debe dar 15, no 30.
  SELECT CASE WHEN app.anticipacion_efectiva(
                   (SELECT o.id FROM obligacion_usuario o
                    JOIN obligacion_catalogo c ON c.id = o.obligacion_catalogo_id
                    WHERE o.usuario_id = app.usuario_actual() AND c.codigo='vehiculo.soat'
                      AND o.dias_anticipacion IS NULL LIMIT 1)) = 15
              THEN 'ok    la sugerencia del catalogo no se aplica sola'
              ELSE 'FALLA la sugerencia esta actuando como valor de respaldo' END;
COMMIT;

-- --- El caso que motiva la deuda -------------------------------------------
-- 30 dias para el SOAT y 5 para la tarjeta: avisar con un mes de algo mensual
-- es ruido, y el ruido hace que el usuario silencie los avisos que si importan.
SELECT CASE WHEN (SELECT dias_anticipacion_sugeridos FROM obligacion_catalogo WHERE codigo='vehiculo.soat')
              >  (SELECT dias_anticipacion_sugeridos FROM obligacion_catalogo WHERE codigo='finanzas.tarjeta_credito')
            THEN 'ok    el SOAT se avisa con mas antelacion que la tarjeta'
            ELSE 'FALLA las urgencias distintas no se distinguen' END;

-- --- Las 8 sancionables tienen sugerencia ----------------------------------
SELECT CASE WHEN count(*) = 8 THEN 'ok    las 8 sancionables traen anticipacion sugerida'
            ELSE 'FALLA solo ' || count(*) || ' de 8 tienen sugerencia' END
FROM obligacion_catalogo
WHERE tipo_exigibilidad='sancionable' AND dias_anticipacion_sugeridos IS NOT NULL;

-- --- Limites --------------------------------------------------------------
BEGIN;
  SELECT set_config('alivia.usuario_id',
    (SELECT id::text FROM app.credenciales_por_correo('ana@prueba.local')), true) \gset ctx_
  DO $$
  BEGIN
    UPDATE obligacion_usuario SET dias_anticipacion = 0
    WHERE id = (SELECT id FROM obligacion_usuario WHERE usuario_id = app.usuario_actual() LIMIT 1);
    RAISE NOTICE 'FALLA acepto una anticipacion de cero dias';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'ok    rechaza una anticipacion de cero dias';
  END $$;
ROLLBACK;
