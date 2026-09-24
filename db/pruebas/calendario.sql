-- Verificacion de la recurrencia por calendario (deuda D1).
--
--   psql "$DATABASE_URL" -f db/pruebas/calendario.sql
--
-- Las fechas esperadas estan contrastadas contra la norma citada en cada
-- calendario, no contra lo que el sistema tenga cargado. Si alguien carga mal
-- una fecha, esto lo detecta.

\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on

-- --- Medellin: la fecha depende del sector ---------------------------------
-- Resolucion 202550100057 de 2025, art. 6: El Poblado (14) vence el 13-feb-26
-- en el trimestre I; Popular (01), el 4-mar-26.
SELECT CASE WHEN (SELECT fecha FROM app.proximo_vencimiento_calendario(
                    '05001','hogar.predial','trimestral','14',DATE '2026-01-01')) = DATE '2026-02-13'
            THEN 'ok    Medellin/El Poblado trimestre I = 13-feb-26'
            ELSE 'FALLA Medellin/El Poblado no coincide con la resolucion' END;

SELECT CASE WHEN (SELECT fecha FROM app.proximo_vencimiento_calendario(
                    '05001','hogar.predial','trimestral','01',DATE '2026-01-01')) = DATE '2026-03-04'
            THEN 'ok    Medellin/Popular trimestre I = 4-mar-26'
            ELSE 'FALLA Medellin/Popular no coincide con la resolucion' END;

-- Dos sectores distintos NO pueden tener la misma fecha: si la tuvieran, el
-- segmento se estaria ignorando.
SELECT CASE WHEN (SELECT fecha FROM app.proximo_vencimiento_calendario(
                    '05001','hogar.predial','trimestral','14',DATE '2026-01-01'))
              <> (SELECT fecha FROM app.proximo_vencimiento_calendario(
                    '05001','hogar.predial','trimestral','01',DATE '2026-01-01'))
            THEN 'ok    el sector cambia la fecha'
            ELSE 'FALLA el sector se esta ignorando' END;

-- --- Copacabana: sin sectores ----------------------------------------------
-- Resolucion 2025000SHI2898 de 2025, art. 1: trimestre I vence el 5-abr-26.
SELECT CASE WHEN (SELECT fecha FROM app.proximo_vencimiento_calendario(
                    '05212','hogar.predial','trimestral',NULL,DATE '2026-01-01')) = DATE '2026-04-05'
            THEN 'ok    Copacabana trimestre I = 5-abr-26'
            ELSE 'FALLA Copacabana no coincide con la resolucion' END;

-- --- Avanza a lo largo del año ---------------------------------------------
SELECT CASE WHEN (SELECT etiqueta FROM app.proximo_vencimiento_calendario(
                    '05001','hogar.predial','trimestral','14',DATE '2026-08-01')) = 'Trimestre IV'
            THEN 'ok    despues de agosto toca el trimestre IV'
            ELSE 'FALLA no avanza al siguiente trimestre' END;

-- --- Lo que no se sabe, no se inventa --------------------------------------
-- Caldas (05129) no tiene calendario cargado: no hay fuente primaria leida.
SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM app.proximo_vencimiento_calendario(
                    '05129','hogar.predial','trimestral',NULL,DATE '2026-01-01'))
            THEN 'ok    municipio sin calendario no devuelve fecha inventada'
            ELSE 'FALLA devuelve una fecha para un municipio sin calendario' END;

-- Un año sin calendario tampoco.
SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM app.proximo_vencimiento_calendario(
                    '05001','hogar.predial','trimestral','14',DATE '2027-01-01'))
            THEN 'ok    2027 todavia no tiene calendario y no se finge que si'
            ELSE 'FALLA devuelve fechas de un año no cargado' END;

-- --- Las fechas con recargo no se usan como aviso ---------------------------
-- Avisar de la fecha con recargo es avisar de que ya se pago de mas.
SELECT CASE WHEN NOT EXISTS (
         SELECT 1 FROM app.proximo_vencimiento_calendario(
           '05001','hogar.predial','trimestral','14',DATE '2026-01-01')
         WHERE tipo = 'con_recargo')
       THEN 'ok    no se avisa de fechas con recargo'
       ELSE 'FALLA estaria avisando de una fecha que ya implica recargo' END;

-- --- Todo calendario declara su norma --------------------------------------
SELECT CASE WHEN count(*) = 0 THEN 'ok    todo calendario cargado cita su norma'
            ELSE 'FALLA ' || count(*) || ' calendario(s) sin norma' END
FROM calendario_tributario WHERE norma IS NULL OR btrim(norma) = '';

-- --- Solo se marca verificado lo leido en la norma -------------------------
SELECT CASE WHEN count(*) = 2 THEN 'ok    2 calendarios verificados contra fuente primaria'
            ELSE 'FALLA hay ' || count(*) || ' verificados; se esperaban 2' END
FROM calendario_tributario WHERE verificado;

-- --- Cobertura completa de Medellin ----------------------------------------
-- 20 sectores x 4 trimestres = 80 fechas ordinarias.
SELECT CASE WHEN count(*) = 80 THEN 'ok    Medellin tiene las 80 fechas ordinarias'
            ELSE 'FALLA Medellin tiene ' || count(*) || ' fechas; se esperaban 80' END
FROM vencimiento_calendario v JOIN calendario_tributario c ON c.id = v.calendario_id
WHERE c.municipio_dane = '05001' AND v.tipo = 'ordinario';
