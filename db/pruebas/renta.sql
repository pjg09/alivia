-- Verificacion del calendario de renta (deuda D2).
--
--   psql "$DATABASE_URL" -f db/pruebas/renta.sql
--
-- Fechas contrastadas contra el calendario tributario oficial de la DIAN 2026.
-- La renta no depende del municipio ni de una fecha base: depende de los dos
-- ultimos digitos del NIT.

\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on

-- --- Los cien digitos estan cubiertos --------------------------------------
SELECT CASE WHEN count(DISTINCT segmento) = 100 AND count(*) = 100
            THEN 'ok    los 100 digitos del NIT tienen fecha'
            ELSE 'FALLA hay ' || count(DISTINCT segmento) || ' digitos cubiertos de 100' END
FROM vencimiento_calendario v JOIN calendario_tributario c ON c.id = v.calendario_id
WHERE c.obligacion_codigo = 'finanzas.renta';

-- --- Los extremos del calendario -------------------------------------------
SELECT CASE WHEN (SELECT fecha FROM app.proximo_vencimiento_calendario(
                    NULL,'finanzas.renta','anual','01',DATE '2026-01-01')) = DATE '2026-08-12'
            THEN 'ok    NIT terminado en 01 vence el 12-ago-26'
            ELSE 'FALLA el primer vencimiento no coincide con la DIAN' END;

SELECT CASE WHEN (SELECT fecha FROM app.proximo_vencimiento_calendario(
                    NULL,'finanzas.renta','anual','00',DATE '2026-01-01')) = DATE '2026-10-26'
            THEN 'ok    NIT terminado en 00 vence el 26-oct-26'
            ELSE 'FALLA el ultimo vencimiento no coincide con la DIAN' END;

-- --- Los digitos van en pares ----------------------------------------------
-- 01 y 02 comparten fecha; 02 y 03 no.
SELECT CASE WHEN (SELECT fecha FROM app.proximo_vencimiento_calendario(NULL,'finanzas.renta','anual','01',DATE '2026-01-01'))
              =  (SELECT fecha FROM app.proximo_vencimiento_calendario(NULL,'finanzas.renta','anual','02',DATE '2026-01-01'))
            AND (SELECT fecha FROM app.proximo_vencimiento_calendario(NULL,'finanzas.renta','anual','02',DATE '2026-01-01'))
             <> (SELECT fecha FROM app.proximo_vencimiento_calendario(NULL,'finanzas.renta','anual','03',DATE '2026-01-01'))
            THEN 'ok    los digitos se agrupan de dos en dos'
            ELSE 'FALLA el agrupamiento por pares no se respeta' END;

-- --- Cruce de mes ----------------------------------------------------------
-- 26 cierra agosto el dia 31; 27 abre septiembre el dia 1.
SELECT CASE WHEN (SELECT fecha FROM app.proximo_vencimiento_calendario(
                    NULL,'finanzas.renta','anual','26',DATE '2026-01-01')) = DATE '2026-08-31'
            AND  (SELECT fecha FROM app.proximo_vencimiento_calendario(
                    NULL,'finanzas.renta','anual','27',DATE '2026-01-01')) = DATE '2026-09-01'
            THEN 'ok    el paso de agosto a septiembre coincide'
            ELSE 'FALLA el cruce de mes no coincide con la DIAN' END;

-- --- Ninguna fecha cae en fin de semana o festivo --------------------------
SELECT CASE WHEN count(*) = 0 THEN 'ok    ninguna fecha cae en sabado o domingo'
            ELSE 'FALLA ' || count(*) || ' fecha(s) en fin de semana' END
FROM vencimiento_calendario v JOIN calendario_tributario c ON c.id = v.calendario_id
WHERE c.obligacion_codigo = 'finanzas.renta' AND EXTRACT(isodow FROM v.fecha) > 5;

-- 17 de agosto (Asuncion) y 12 de octubre (Dia de la Raza) son festivos.
SELECT CASE WHEN count(*) = 0 THEN 'ok    no se asigno ningun festivo'
            ELSE 'FALLA hay vencimientos en dia festivo' END
FROM vencimiento_calendario v JOIN calendario_tributario c ON c.id = v.calendario_id
WHERE c.obligacion_codigo = 'finanzas.renta'
  AND v.fecha IN (DATE '2026-08-17', DATE '2026-10-12');

-- --- El ambito nacional no lleva municipio ---------------------------------
SELECT CASE WHEN count(*) = 1 THEN 'ok    el calendario de renta es nacional, sin municipio'
            ELSE 'FALLA el ambito nacional no esta bien declarado' END
FROM calendario_tributario
WHERE obligacion_codigo = 'finanzas.renta' AND ambito = 'nacional' AND municipio_dane IS NULL;

-- --- El predial sigue funcionando ------------------------------------------
-- Generalizar el ambito no debe haber roto los calendarios municipales.
SELECT CASE WHEN (SELECT fecha FROM app.proximo_vencimiento_calendario(
                    '05001','hogar.predial','trimestral','14',DATE '2026-01-01')) = DATE '2026-02-13'
            THEN 'ok    el predial municipal sigue resolviendo igual'
            ELSE 'FALLA generalizar el ambito rompio el predial' END;

-- --- Un calendario nacional no se confunde con uno municipal ---------------
SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM app.proximo_vencimiento_calendario(
                    '05001','finanzas.renta','anual','01',DATE '2026-01-01'))
            THEN 'ok    la renta no se resuelve pidiendola por municipio'
            ELSE 'FALLA un calendario nacional responde a una consulta municipal' END;

-- --- 2027 no existe --------------------------------------------------------
-- El decreto de plazos se expide cada año. Sin el, no hay fecha que dar.
SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM app.proximo_vencimiento_calendario(
                    NULL,'finanzas.renta','anual','01',DATE '2026-12-31'))
            THEN 'ok    2027 no tiene calendario y no se inventa'
            ELSE 'FALLA devuelve fechas de un año sin decreto' END;
