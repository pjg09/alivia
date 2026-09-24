-- Verificacion de las variantes de obligacion (deuda D3).
--
--   psql "$DATABASE_URL" -f db/pruebas/variantes.sql
--
-- El caso que motiva todo esto: un motociclista debe recibir su primer aviso
-- de tecnomecanica al segundo año, no al quinto. Con el modelo anterior se le
-- habria avisado tres años tarde, cuando ya llevaba tres de multa posible.

\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on

-- --- La norma, como quedo sembrada ------------------------------------------
SELECT CASE WHEN (SELECT desfase_primera FROM variante_obligacion
                  WHERE obligacion_codigo='vehiculo.tecnomecanica' AND clave='particular')
                 = interval '5 years'
            THEN 'ok    particular: primera revision al quinto año'
            ELSE 'FALLA el desfase del particular no coincide con el art. 52' END;

SELECT CASE WHEN (SELECT desfase_primera FROM variante_obligacion
                  WHERE obligacion_codigo='vehiculo.tecnomecanica' AND clave='motocicleta')
                 = interval '2 years'
            THEN 'ok    motocicleta: primera revision al segundo año'
            ELSE 'FALLA el desfase de la motocicleta no coincide con el art. 52' END;

SELECT CASE WHEN (SELECT desfase_primera FROM variante_obligacion
                  WHERE obligacion_codigo='vehiculo.tecnomecanica' AND clave='servicio_publico')
                 = interval '2 years'
            THEN 'ok    servicio publico: primera revision al segundo año'
            ELSE 'FALLA el desfase del servicio publico no coincide con el art. 52' END;

-- Art. 51: despues de la primera, anual para todos.
SELECT CASE WHEN count(*) = 3 THEN 'ok    las tres variantes se repiten anualmente'
            ELSE 'FALLA la periodicidad no es anual en todas las variantes' END
FROM variante_obligacion
WHERE obligacion_codigo='vehiculo.tecnomecanica' AND periodicidad = interval '1 year';

-- --- El caso que motiva la deuda -------------------------------------------
-- Una moto matriculada el 1-mar-2026 vence el 1-mar-2028, no el 1-mar-2031.
SELECT CASE WHEN (DATE '2026-03-01' + (SELECT desfase_primera FROM variante_obligacion
                   WHERE obligacion_codigo='vehiculo.tecnomecanica' AND clave='motocicleta'))::date
                 = DATE '2028-03-01'
            THEN 'ok    moto matriculada en mar-2026 vence en mar-2028'
            ELSE 'FALLA el motociclista recibiria el aviso tarde' END;

SELECT CASE WHEN (DATE '2026-03-01' + (SELECT desfase_primera FROM variante_obligacion
                   WHERE obligacion_codigo='vehiculo.tecnomecanica' AND clave='particular'))::date
                 = DATE '2031-03-01'
            THEN 'ok    carro matriculado en mar-2026 vence en mar-2031'
            ELSE 'FALLA el desfase del particular esta mal aplicado' END;

-- Y los dos NO pueden coincidir: si coinciden, la variante se esta ignorando.
SELECT CASE WHEN (SELECT desfase_primera FROM variante_obligacion
                  WHERE obligacion_codigo='vehiculo.tecnomecanica' AND clave='motocicleta')
              <> (SELECT desfase_primera FROM variante_obligacion
                  WHERE obligacion_codigo='vehiculo.tecnomecanica' AND clave='particular')
            THEN 'ok    la variante cambia la fecha del primer aviso'
            ELSE 'FALLA la variante no esta teniendo efecto' END;

-- --- No se puede crear la obligacion sin elegir variante --------------------
BEGIN;
  SELECT set_config('alivia.usuario_id',
    (SELECT id::text FROM app.credenciales_por_correo('ana@prueba.local')), true) \gset ctx_
  DO $$
  DECLARE v_cat uuid;
  BEGIN
    SELECT id INTO v_cat FROM obligacion_catalogo WHERE codigo='vehiculo.tecnomecanica';
    INSERT INTO obligacion_usuario
      (usuario_id, modulo_codigo, origen, obligacion_catalogo_id, nombre, tipo_exigibilidad, fecha_base)
    VALUES (app.usuario_actual(), 'vehiculo', 'catalogo', v_cat, 'SIN VARIANTE', 'sancionable', DATE '2026-03-01');
    RAISE NOTICE 'FALLA se creo una tecnomecanica sin declarar el tipo de vehiculo';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'ok    no se puede crear la tecnomecanica sin tipo de vehiculo';
  END $$;
ROLLBACK;

-- --- Ni elegir una variante de otra obligacion ------------------------------
BEGIN;
  SELECT set_config('alivia.usuario_id',
    (SELECT id::text FROM app.credenciales_por_correo('ana@prueba.local')), true) \gset ctx_
  DO $$
  DECLARE v_cat uuid; v_var uuid;
  BEGIN
    SELECT id INTO v_cat FROM obligacion_catalogo WHERE codigo='vehiculo.soat';
    SELECT id INTO v_var FROM variante_obligacion WHERE clave='motocicleta';
    INSERT INTO obligacion_usuario
      (usuario_id, modulo_codigo, origen, obligacion_catalogo_id, variante_id, nombre, tipo_exigibilidad, fecha_base)
    VALUES (app.usuario_actual(), 'vehiculo', 'catalogo', v_cat, v_var, 'VARIANTE AJENA', 'sancionable', DATE '2026-03-01');
    RAISE NOTICE 'FALLA acepto una variante que no es de esa obligacion';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'ok    rechaza una variante de otra obligacion';
  END $$;
ROLLBACK;

-- --- Con variante, se crea sin problema ------------------------------------
BEGIN;
  SELECT set_config('alivia.usuario_id',
    (SELECT id::text FROM app.credenciales_por_correo('ana@prueba.local')), true) \gset ctx_
  DO $$
  DECLARE v_cat uuid; v_var uuid;
  BEGIN
    SELECT id INTO v_cat FROM obligacion_catalogo WHERE codigo='vehiculo.tecnomecanica';
    SELECT id INTO v_var FROM variante_obligacion
      WHERE obligacion_codigo='vehiculo.tecnomecanica' AND clave='motocicleta';
    INSERT INTO obligacion_usuario
      (usuario_id, modulo_codigo, origen, obligacion_catalogo_id, variante_id,
       nombre, periodicidad, desfase_primera, tipo_exigibilidad, fecha_base)
    SELECT app.usuario_actual(), 'vehiculo', 'catalogo', v_cat, v_var,
           'Mi moto', v.periodicidad, v.desfase_primera, 'sancionable', DATE '2026-03-01'
    FROM variante_obligacion v WHERE v.id = v_var;
    RAISE NOTICE 'ok    con variante declarada, la obligacion se crea';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FALLA no deja crear ni con variante: %', SQLERRM;
  END $$;
ROLLBACK;

-- --- Una obligacion sin variantes sigue funcionando igual -------------------
SELECT CASE WHEN (SELECT atributo_variante FROM obligacion_catalogo WHERE codigo='vehiculo.soat') IS NULL
            THEN 'ok    el SOAT no exige variante'
            ELSE 'FALLA se le puso variante a una obligacion que no la tiene' END;

-- --- La fuente quedo verificada --------------------------------------------
SELECT CASE WHEN (SELECT fuente_verificada FROM obligacion_catalogo WHERE codigo='vehiculo.tecnomecanica')
            THEN 'ok    la tecnomecanica ya tiene fuente normativa verificada'
            ELSE 'FALLA la fuente sigue sin verificar' END;

-- --- Los ajustes del catalogo se aplicaron de verdad ------------------------
-- Estas comprobaciones existen porque los UPDATE que introducian estos valores
-- vivian dentro de las migraciones, y ahi corren contra un catalogo vacio: las
-- semillas se aplican despues. Pasaban en la maquina de quien iba añadiendo
-- migraciones sobre una base ya sembrada, y fallaban en una instalacion desde
-- cero. Sin estas lineas, el defecto vuelve en silencio.
SELECT CASE WHEN (SELECT atributo_variante FROM obligacion_catalogo
                  WHERE codigo='vehiculo.tecnomecanica') = 'tipo_vehiculo'
            THEN 'ok    la tecnomecanica exige declarar el tipo de vehiculo'
            ELSE 'FALLA el ajuste del catalogo no se aplico' END;

SELECT CASE WHEN (SELECT tipo_recurrencia FROM obligacion_catalogo
                  WHERE codigo='hogar.predial') = 'calendario'
            THEN 'ok    el predial quedo como obligacion de calendario'
            ELSE 'FALLA el predial sigue siendo de periodicidad relativa' END;

SELECT CASE WHEN (SELECT tipo_recurrencia FROM obligacion_catalogo
                  WHERE codigo='finanzas.renta') = 'calendario'
            THEN 'ok    la renta quedo como obligacion de calendario'
            ELSE 'FALLA la renta sigue siendo de periodicidad relativa' END;

SELECT CASE WHEN (SELECT periodicidad FROM obligacion_catalogo
                  WHERE codigo='hogar.predial') IS NULL
            THEN 'ok    el predial ya no lleva periodicidad relativa'
            ELSE 'FALLA el predial conserva una periodicidad que no le corresponde' END;
