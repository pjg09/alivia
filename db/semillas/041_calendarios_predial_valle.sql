-- Calendarios del predial 2026, segunda tanda. Todos leidos de su resolucion.
--
-- Confirman que no hay patron comun: Sabaneta y Barbosa van por trimestres con
-- fechas distintas entre si, y Girardota va por semestres con dos niveles de
-- descuento. Ninguno se parece a Medellin.
--
-- NOTA sobre los codigos DANE: se usan los del Valle de Aburra segun la
-- codificacion estandar. No se verificaron contra la publicacion del DANE.

INSERT INTO municipio (codigo_dane, nombre, departamento) VALUES
  ('05631', 'Sabaneta',  'Antioquia'),
  ('05308', 'Girardota', 'Antioquia'),
  ('05079', 'Barbosa',   'Antioquia')
ON CONFLICT (codigo_dane) DO NOTHING;

-- ===========================================================================
-- SABANETA · Resolución 2025015914 del 29 de diciembre de 2025, artículo 1
-- ===========================================================================
-- Trimestral, fecha unica. Los dias de la semana que declara la norma
-- (jueves, martes, miercoles, miercoles) coinciden con el calendario de 2026.
WITH cal AS (
  INSERT INTO calendario_tributario
    (municipio_dane, obligacion_codigo, anio, modalidad, norma, norma_url, verificado)
  VALUES ('05631', 'hogar.predial', 2026, 'trimestral',
          'Resolución 2025015914 del 29 de diciembre de 2025, artículo 1 — Municipio de Sabaneta',
          'https://sabaneta.gov.co/files/normas/2026-01-07-03-20-24.pdf', true)
  RETURNING id
)
INSERT INTO vencimiento_calendario
  (calendario_id, segmento, segmento_nombre, etiqueta, orden, fecha, tipo)
SELECT cal.id, NULL, NULL, v.etiqueta, v.orden, v.fecha::date, 'ordinario'
FROM cal, (VALUES
  ('Trimestre I',   1, '2026-04-30'),
  ('Trimestre II',  2, '2026-06-30'),
  ('Trimestre III', 3, '2026-09-30'),
  ('Trimestre IV',  4, '2026-12-23')
) AS v(etiqueta, orden, fecha);

-- ===========================================================================
-- BARBOSA · Resolución 3271 del 23 de diciembre de 2025
-- ===========================================================================
-- Trimestral, con fecha sin recargo y fecha con recargo por trimestre.
WITH cal AS (
  INSERT INTO calendario_tributario
    (municipio_dane, obligacion_codigo, anio, modalidad, norma, norma_url, verificado)
  VALUES ('05079', 'hogar.predial', 2026, 'trimestral',
          'Resolución 3271 del 23 de diciembre de 2025 — Municipio de Barbosa',
          'https://www.barbosa.gov.co/Transparencia/Calendarios%20Tributarios/CALENDARIO%20TRIBUTARIO%202026.pdf',
          true)
  RETURNING id
)
INSERT INTO vencimiento_calendario
  (calendario_id, segmento, segmento_nombre, etiqueta, orden, fecha, tipo)
SELECT cal.id, NULL, NULL, v.etiqueta, v.orden, v.fecha::date, v.tipo
FROM cal, (VALUES
  ('Trimestre I',   1, '2026-04-15', 'ordinario'),
  ('Trimestre II',  2, '2026-06-16', 'ordinario'),
  ('Trimestre III', 3, '2026-09-15', 'ordinario'),
  ('Trimestre IV',  4, '2026-12-15', 'ordinario'),
  ('Trimestre I',   1, '2026-04-30', 'con_recargo'),
  ('Trimestre II',  2, '2026-06-30', 'con_recargo'),
  ('Trimestre III', 3, '2026-09-30', 'con_recargo'),
  ('Trimestre IV',  4, '2026-12-30', 'con_recargo')
) AS v(etiqueta, orden, fecha, tipo);

-- ===========================================================================
-- GIRARDOTA · Resolución 4666 de 2025
-- ===========================================================================
-- Semestral con dos niveles de descuento sobre el primer semestre: 10% hasta
-- el 24 de abril y 5% hasta el 19 de junio. El segundo semestre vence el 14
-- de diciembre. Cada nivel va como etiqueta propia porque son oportunidades
-- distintas de pago, no la misma fecha con dos nombres.
WITH cal AS (
  INSERT INTO calendario_tributario
    (municipio_dane, obligacion_codigo, anio, modalidad, norma, norma_url, verificado)
  VALUES ('05308', 'hogar.predial', 2026, 'semestral',
          'Resolución 4666 de 2025 — Municipio de Girardota',
          'https://www.girardota.gov.co/Documents/12.1-Calendario%20Tributario%202026-Mpio%20de%20Girardota.pdf',
          true)
  RETURNING id
)
INSERT INTO vencimiento_calendario
  (calendario_id, segmento, segmento_nombre, etiqueta, orden, fecha, tipo, descuento_pct)
SELECT cal.id, NULL, NULL, v.etiqueta, v.orden, v.fecha::date, v.tipo, v.pct
FROM cal, (VALUES
  ('Semestre I · descuento 10%', 1, '2026-04-24', 'con_descuento', 10.00),
  ('Semestre I · descuento 5%',  2, '2026-06-19', 'con_descuento',  5.00),
  ('Semestre I',                 3, '2026-06-26', 'con_recargo',    NULL),
  ('Semestre II',                4, '2026-12-14', 'ordinario',      NULL),
  ('Semestre II',                5, '2026-12-18', 'con_recargo',    NULL)
) AS v(etiqueta, orden, fecha, tipo, pct);
