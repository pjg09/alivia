-- 010 · Calendarios de ámbito nacional. Salda la deuda D2.
--
-- EL PROBLEMA. La declaración de renta de personas naturales no vence en una
-- fecha relativa a nada que el usuario declare, ni depende del municipio:
-- depende de los DOS ULTIMOS DIGITOS DEL NIT, y la fija un decreto nacional
-- que se expide cada año.
--
-- El modelo de calendario de la migración 009 ya servía para esto salvo por un
-- detalle: daba por supuesto que todo calendario es municipal. Aquí se
-- generaliza el ámbito, y el segmento —que en Medellín es el código sectorial
-- del predio— pasa a ser, para la renta, los dos últimos dígitos del NIT.

ALTER TABLE calendario_tributario
  ADD COLUMN ambito text NOT NULL DEFAULT 'municipal'
    CHECK (ambito IN ('nacional', 'municipal'));

ALTER TABLE calendario_tributario ALTER COLUMN municipio_dane DROP NOT NULL;

ALTER TABLE calendario_tributario
  ADD CONSTRAINT ambito_coherente CHECK (
    (ambito = 'municipal' AND municipio_dane IS NOT NULL) OR
    (ambito = 'nacional'  AND municipio_dane IS NULL)
  );

-- La restricción anterior no distinguía dos calendarios nacionales, porque en
-- SQL un NULL no es igual a otro NULL. NULLS NOT DISTINCT lo corrige.
ALTER TABLE calendario_tributario
  DROP CONSTRAINT calendario_tributario_municipio_dane_obligacion_codigo_anio_key;

ALTER TABLE calendario_tributario
  ADD CONSTRAINT calendario_unico
    UNIQUE NULLS NOT DISTINCT (municipio_dane, obligacion_codigo, anio, modalidad);

-- Una obligación de calendario nacional no tiene municipio. La coherencia pasa
-- a exigir lo que de verdad hace falta: saber a qué segmento pertenece el
-- usuario, sea su comuna o sus dos últimos dígitos del NIT.
ALTER TABLE obligacion_usuario DROP CONSTRAINT recurrencia_coherente;

ALTER TABLE obligacion_usuario
  ADD CONSTRAINT recurrencia_coherente CHECK (
    CASE tipo_recurrencia
      WHEN 'relativa'   THEN fecha_base IS NOT NULL AND municipio_dane IS NULL
      WHEN 'calendario' THEN modalidad IS NOT NULL
      WHEN 'declarada'  THEN true
    END
  );

-- p_municipio NULL pasa a significar "calendario nacional". IS NOT DISTINCT
-- FROM compara NULL con NULL como igualdad, que es lo que hace falta aquí.
CREATE OR REPLACE FUNCTION app.proximo_vencimiento_calendario(
  p_municipio  text,
  p_obligacion text,
  p_modalidad  text,
  p_segmento   text,
  p_desde      date
) RETURNS TABLE (
  fecha         date,
  etiqueta      text,
  tipo          text,
  descuento_pct numeric,
  norma         text,
  verificado    boolean
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, app AS $$
  SELECT v.fecha, v.etiqueta, v.tipo, v.descuento_pct, c.norma, c.verificado
  FROM calendario_tributario c
  JOIN vencimiento_calendario v ON v.calendario_id = c.id
  WHERE c.municipio_dane IS NOT DISTINCT FROM p_municipio
    AND c.obligacion_codigo = p_obligacion
    AND c.modalidad = p_modalidad
    AND (v.segmento IS NULL OR v.segmento = p_segmento)
    AND v.tipo IN ('ordinario', 'con_descuento')
    AND v.fecha > p_desde
  ORDER BY v.fecha
  LIMIT 1;
$$;

-- La renta pasa a ser obligación de calendario: ese UPDATE vive en
-- db/semillas/021_ajustes_catalogo.sql. Ver la nota de la migración 009.
