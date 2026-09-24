-- Calendarios del impuesto predial. Vigencia fiscal 2026.
--
-- SOLO SE SIEMBRA LO LEIDO EN LA NORMA. De los diez municipios del Valle de
-- Aburra, dos tienen aqui su calendario porque se leyo la resolucion que lo
-- fija. Los otros ocho NO se siembran: la informacion disponible venia de
-- prensa y de agregadores que repiten las mismas fechas para municipios
-- distintos, lo que es señal de copia y no de fuente.
--
-- Un municipio sin calendario cargado no es un vacio: la obligacion se crea
-- con recurrencia 'declarada' y la fecha la pone el usuario. El sistema avisa
-- igual, sin fingir que conoce una fecha que no conoce.

INSERT INTO municipio (codigo_dane, nombre, departamento) VALUES
  ('05001', 'Medellín',   'Antioquia'),
  ('05212', 'Copacabana', 'Antioquia')
ON CONFLICT (codigo_dane) DO NOTHING;

-- ===========================================================================
-- MEDELLIN · Resolución 202550100057 del 9 de diciembre de 2025, artículo 6
-- ===========================================================================
-- Trimestral, con fecha distinta por código sectorial. Cada trimestre tiene
-- una fecha sin recargo (propia de cada sector) y una con recargo (común).
WITH cal AS (
  INSERT INTO calendario_tributario
    (municipio_dane, obligacion_codigo, anio, modalidad, norma, norma_url, verificado)
  VALUES ('05001', 'hogar.predial', 2026, 'trimestral',
          'Resolución 202550100057 del 9 de diciembre de 2025, artículo 6 — Distrito de Medellín',
          'https://www.medellin.gov.co/es/wp-content/uploads/2025/12/RESOLUCION-202550100057-DE-2025-CALENDARIO-TRIBUTARIO-2026.pdf',
          true)
  RETURNING id
)
INSERT INTO vencimiento_calendario
  (calendario_id, segmento, segmento_nombre, etiqueta, orden, fecha, tipo)
SELECT cal.id, s.codigo, s.nombre, t.etiqueta, t.orden, f.fecha, 'ordinario'
FROM cal
CROSS JOIN (VALUES
  ('14','El Poblado',1),              ('11','Laureles',2),
  ('12','La América',3),              ('10','La Candelaria',4),
  ('15','Guayabal',5),                ('16','Belén',6),
  ('13','San Javier',7),              ('07','Robledo',8),
  ('06','Doce de Octubre',9),         ('05','Castilla',10),
  ('08','Villa Hermosa',11),          ('09','Buenos Aires',12),
  ('04','Aranjuez',13),               ('01','Popular',14),
  ('02','Santa Cruz',15),             ('03','Manrique',16),
  ('17','San Antonio de Prado',17),   ('18','San Cristóbal y Palmitas',18),
  ('19','Santa Elena y Altavista',19),('00','Varios sectores',20)
) AS s(codigo, nombre, fila)
CROSS JOIN (VALUES
  ('Trimestre I',1), ('Trimestre II',2), ('Trimestre III',3), ('Trimestre IV',4)
) AS t(etiqueta, orden)
CROSS JOIN LATERAL (
  SELECT (ARRAY[
    -- Trimestre I: 13-feb a 12-mar
    ARRAY['2026-02-13','2026-02-16','2026-02-17','2026-02-18','2026-02-19','2026-02-20',
          '2026-02-23','2026-02-24','2026-02-25','2026-02-26','2026-02-27','2026-03-02',
          '2026-03-03','2026-03-04','2026-03-05','2026-03-06','2026-03-09','2026-03-10',
          '2026-03-11','2026-03-12'],
    -- Trimestre II: 30-abr a 29-may
    ARRAY['2026-04-30','2026-05-04','2026-05-05','2026-05-06','2026-05-07','2026-05-08',
          '2026-05-11','2026-05-12','2026-05-13','2026-05-14','2026-05-15','2026-05-19',
          '2026-05-20','2026-05-21','2026-05-22','2026-05-25','2026-05-26','2026-05-27',
          '2026-05-28','2026-05-29'],
    -- Trimestre III: 31-jul a 31-ago
    ARRAY['2026-07-31','2026-08-03','2026-08-04','2026-08-05','2026-08-06','2026-08-10',
          '2026-08-11','2026-08-12','2026-08-13','2026-08-14','2026-08-18','2026-08-19',
          '2026-08-20','2026-08-21','2026-08-24','2026-08-25','2026-08-26','2026-08-27',
          '2026-08-28','2026-08-31'],
    -- Trimestre IV: 30-oct a 1-dic
    ARRAY['2026-10-30','2026-11-03','2026-11-04','2026-11-05','2026-11-06','2026-11-09',
          '2026-11-10','2026-11-11','2026-11-12','2026-11-13','2026-11-17','2026-11-18',
          '2026-11-19','2026-11-20','2026-11-23','2026-11-24','2026-11-25','2026-11-26',
          '2026-11-27','2026-12-01']
  ])[t.orden][s.fila]::date AS fecha
) AS f;

-- Fechas con recargo: una por trimestre, común a todos los sectores.
INSERT INTO vencimiento_calendario
  (calendario_id, segmento, segmento_nombre, etiqueta, orden, fecha, tipo)
SELECT c.id, NULL, NULL, v.etiqueta, v.orden, v.fecha::date, 'con_recargo'
FROM calendario_tributario c
CROSS JOIN (VALUES
  ('Trimestre I',   1, '2026-03-27'),
  ('Trimestre II',  2, '2026-06-25'),
  ('Trimestre III', 3, '2026-09-28'),
  ('Trimestre IV',  4, '2026-12-28')
) AS v(etiqueta, orden, fecha)
WHERE c.municipio_dane = '05001' AND c.anio = 2026 AND c.modalidad = 'trimestral';

-- ===========================================================================
-- COPACABANA · Resolución 2025000SHI2898 del 18 de diciembre de 2025, art. 1
-- ===========================================================================
-- Trimestral, una sola fecha por trimestre. Sin sectores y sin descuento.
WITH cal AS (
  INSERT INTO calendario_tributario
    (municipio_dane, obligacion_codigo, anio, modalidad, norma, norma_url, verificado)
  VALUES ('05212', 'hogar.predial', 2026, 'trimestral',
          'Resolución 2025000SHI2898 del 18 de diciembre de 2025, artículo primero — Municipio de Copacabana',
          'https://www.copacabana.gov.co/Transparencia/Normatividad/E-DSG-F-007%20CALENDARIO%20TRIBUTARIO%202026.pdf',
          true)
  RETURNING id
)
INSERT INTO vencimiento_calendario
  (calendario_id, segmento, segmento_nombre, etiqueta, orden, fecha, tipo)
SELECT cal.id, NULL, NULL, v.etiqueta, v.orden, v.fecha::date, 'ordinario'
FROM cal, (VALUES
  ('Trimestre I',   1, '2026-04-05'),
  ('Trimestre II',  2, '2026-06-30'),
  ('Trimestre III', 3, '2026-09-30'),
  ('Trimestre IV',  4, '2026-12-31')
) AS v(etiqueta, orden, fecha);
