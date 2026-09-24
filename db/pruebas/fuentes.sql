-- Verificacion de la curaduria de fuentes (deuda D4).
--
--   psql "$DATABASE_URL" -f db/pruebas/fuentes.sql
--
-- El alcance pide que cada obligacion declare la fuente normativa que respalda
-- su periodicidad. Al verificarlas una por una resulta que, para varias, esa
-- fuente no existe: el plazo lo fija un contrato, una factura o un lineamiento.
-- Estas comprobaciones vigilan que el catalogo lo diga en vez de fingirlo.

\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on

-- --- Toda obligacion con consecuencia declara cual es ----------------------
SELECT CASE WHEN count(*) = 0 THEN 'ok    toda sancionable declara su consecuencia'
            ELSE 'FALLA ' || count(*) || ' sancionable(s) sin fuente ni sancion' END
FROM obligacion_catalogo
WHERE tipo_exigibilidad = 'sancionable'
  AND fuente_normativa IS NULL AND fuente_sancion IS NULL;

-- --- Las ocho sancionables estan verificadas -------------------------------
SELECT CASE WHEN count(*) = 8 THEN 'ok    las 8 sancionables tienen fuente verificada'
            ELSE 'FALLA solo ' || count(*) || ' de 8 sancionables verificadas' END
FROM obligacion_catalogo WHERE tipo_exigibilidad = 'sancionable' AND fuente_verificada;

-- --- Si el plazo lo fija una norma, la norma esta escrita -------------------
SELECT CASE WHEN count(*) = 0 THEN 'ok    todo plazo de origen normativo cita su norma'
            ELSE 'FALLA ' || count(*) || ' obligacion(es) dicen norma y no la citan' END
FROM obligacion_catalogo WHERE origen_plazo = 'norma' AND fuente_normativa IS NULL;

-- --- Lo que NO sale de una norma no finge salir de una ---------------------
-- El SOAT es obligatorio por ley, pero su vigencia de un año la fija la poliza.
SELECT CASE WHEN (SELECT origen_plazo FROM obligacion_catalogo WHERE codigo='vehiculo.soat') = 'contrato'
            THEN 'ok    el plazo del SOAT se declara contractual, no legal'
            ELSE 'FALLA el SOAT presenta su vigencia anual como si fuera legal' END;

-- La Ley 142 dice cuando pueden cortar, no cuando hay que pagar.
SELECT CASE WHEN (SELECT origen_plazo FROM obligacion_catalogo WHERE codigo='finanzas.servicios_publicos') = 'factura'
            THEN 'ok    el plazo de los servicios publicos lo fija la factura'
            ELSE 'FALLA se presenta la Ley 142 como si fijara la fecha de pago' END;

-- El Decreto 2257 de 1986 delega la periodicidad en los ministerios.
SELECT CASE WHEN (SELECT origen_plazo FROM obligacion_catalogo WHERE codigo='mascotas.antirrabica') = 'practica'
            THEN 'ok    el refuerzo anual antirrabico no se presenta como norma'
            ELSE 'FALLA se atribuye al decreto una periodicidad que el delega' END;

-- La tarjeta de credito no tiene norma, y se dice.
SELECT CASE WHEN (SELECT fuente_normativa FROM obligacion_catalogo WHERE codigo='finanzas.tarjeta_credito') IS NULL
            AND  (SELECT fuente_sancion   FROM obligacion_catalogo WHERE codigo='finanzas.tarjeta_credito') IS NOT NULL
            THEN 'ok    la tarjeta declara consecuencia contractual sin inventar norma'
            ELSE 'FALLA la tarjeta de credito cita una norma que no existe' END;

-- --- La unica cuyo plazo sale integramente de una norma --------------------
SELECT CASE WHEN count(*) = 1 AND bool_and(codigo = 'vehiculo.tecnomecanica')
            THEN 'ok    solo la tecnomecanica tiene plazo de origen normativo'
            ELSE 'FALLA hay ' || count(*) || ' obligacion(es) con plazo normativo' END
FROM obligacion_catalogo WHERE origen_plazo = 'norma';

-- --- Las recomendadas no fingen respaldo normativo -------------------------
SELECT CASE WHEN count(*) = 0 THEN 'ok    ninguna tarea recomendada cita una norma'
            ELSE 'FALLA ' || count(*) || ' recomendada(s) citan norma' END
FROM obligacion_catalogo
WHERE tipo_exigibilidad = 'recomendada' AND fuente_normativa IS NOT NULL;

SELECT CASE WHEN count(*) = 32 THEN 'ok    las 32 recomendadas declaran plazo de practica'
            ELSE 'FALLA ' || count(*) || ' recomendadas con origen practica; se esperaban 32' END
FROM obligacion_catalogo WHERE tipo_exigibilidad = 'recomendada' AND origen_plazo = 'practica';

-- --- Las multas de transito, confirmadas en el texto de la ley -------------
-- Son los dos datos que la revision de la Entrega 1 habia retirado por venir
-- de prensa. El art. 131 los tiene: grupo C son 15 SMLDV, grupo D son 30.
SELECT CASE WHEN (SELECT fuente_sancion FROM obligacion_catalogo WHERE codigo='vehiculo.soat') LIKE '%D.2%'
            AND  (SELECT fuente_sancion FROM obligacion_catalogo WHERE codigo='vehiculo.tecnomecanica') LIKE '%C.35%'
            THEN 'ok    los literales D.2 y C.35 quedan citados'
            ELSE 'FALLA faltan los literales del art. 131' END;

-- --- Una sancionable no puede quedarse sin ninguna declaracion -------------
DO $$
BEGIN
  INSERT INTO obligacion_catalogo (codigo, nombre, modulo_codigo, tipo_exigibilidad)
  VALUES ('prueba.invalida', 'Sin respaldo', 'hogar', 'sancionable');
  RAISE NOTICE 'FALLA se creo una sancionable sin declarar consecuencia';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'ok    no se puede crear una sancionable sin consecuencia declarada';
END $$;
