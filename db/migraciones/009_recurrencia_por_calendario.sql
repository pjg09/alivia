-- 009 · Recurrencia por calendario. Salda la deuda D1.
--
-- EL PROBLEMA. El modelo anterior calculaba todo vencimiento como
-- fecha_base + periodicidad, donde fecha_base la declara el usuario. El
-- impuesto predial no funciona asi: vence en fechas que fija cada municipio
-- por norma, iguales para todos sus contribuyentes.
--
-- LO QUE SE ENCONTRO AL INVESTIGAR. No hay un patron comun entre municipios,
-- ni siquiera dentro del Valle de Aburra:
--
--   Medellin     trimestral, con fecha distinta por codigo sectorial (21
--                sectores) y dos fechas por trimestre: sin recargo y con
--                recargo. 168 fechas al año.
--   Copacabana   trimestral, una sola fecha por trimestre.
--   Bello        trimestral, una sola fecha por trimestre, otras fechas.
--   Envigado     semestral, con descuento por pronto pago.
--   Sabaneta     anual con descuento, mas un sistema opcional de cuotas.
--
-- Cualquier esquema que suponga "una fecha por municipio y año" se rompe con
-- el primero. Por eso el modelo es una lista de vencimientos con segmento,
-- etiqueta y tipo, y cada municipio la llena como le corresponda.

-- ---------------------------------------------------------------------------
-- Municipios
-- ---------------------------------------------------------------------------
CREATE TABLE municipio (
  codigo_dane  text PRIMARY KEY,
  nombre       text NOT NULL,
  departamento text NOT NULL,
  UNIQUE (nombre, departamento)
);

COMMENT ON TABLE municipio IS
  'Solo los municipios con calendario cargado. Estar aqui no implica tener fechas verificadas.';

-- ---------------------------------------------------------------------------
-- Un calendario publicado, por municipio, obligacion y año
-- ---------------------------------------------------------------------------
CREATE TABLE calendario_tributario (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  municipio_dane     text NOT NULL REFERENCES municipio(codigo_dane),
  obligacion_codigo  text NOT NULL REFERENCES obligacion_catalogo(codigo),
  anio               integer NOT NULL CHECK (anio BETWEEN 2020 AND 2100),

  -- Como paga ese municipio. Un mismo municipio puede ofrecer varias.
  modalidad          text NOT NULL
                     CHECK (modalidad IN ('anual', 'semestral', 'trimestral', 'cuotas')),

  -- De donde salio. Sin norma no se carga un calendario.
  norma              text NOT NULL,
  norma_url          text,

  -- false mientras no se haya leido la norma misma. La prensa no cuenta:
  -- varios agregadores repiten las mismas fechas para municipios distintos.
  verificado         boolean NOT NULL DEFAULT false,

  cargado_en         timestamptz NOT NULL DEFAULT now(),

  UNIQUE (municipio_dane, obligacion_codigo, anio, modalidad)
);

-- ---------------------------------------------------------------------------
-- Cada fecha concreta de ese calendario
-- ---------------------------------------------------------------------------
CREATE TABLE vencimiento_calendario (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  calendario_id   uuid NOT NULL REFERENCES calendario_tributario(id) ON DELETE CASCADE,

  -- El codigo sectorial de Medellin. NULL en los municipios cuya fecha no
  -- depende de donde este el predio, que son la mayoria.
  segmento        text,
  segmento_nombre text,

  -- "Trimestre I", "Cuota 2", "Pago anual".
  etiqueta        text NOT NULL,
  orden           smallint NOT NULL,

  fecha           date NOT NULL,

  -- ordinario      la fecha limite normal
  -- con_recargo    se puede pagar hasta aqui, ya con recargo
  -- con_descuento  pagando hasta aqui hay descuento por pronto pago
  tipo            text NOT NULL DEFAULT 'ordinario'
                  CHECK (tipo IN ('ordinario', 'con_recargo', 'con_descuento')),

  descuento_pct   numeric(5,2) CHECK (descuento_pct IS NULL OR descuento_pct > 0),

  CONSTRAINT descuento_solo_si_aplica
    CHECK ((tipo = 'con_descuento') = (descuento_pct IS NOT NULL)),

  UNIQUE (calendario_id, segmento, etiqueta, tipo)
);

CREATE INDEX ON vencimiento_calendario (calendario_id, fecha);

GRANT SELECT ON municipio, calendario_tributario, vencimiento_calendario
  TO alivia_app, alivia_avisos;

-- ---------------------------------------------------------------------------
-- Tres formas de saber cuando vence algo
-- ---------------------------------------------------------------------------
--   relativa    fecha_base del usuario + periodicidad.   SOAT, tecnomecanica.
--   calendario  lo dice la norma del municipio.          Predial.
--   declarada   lo dice el usuario, porque el sistema no tiene el calendario
--               de su municipio. Es el camino honesto: avisa igual, sin
--               fingir que conoce una fecha que no conoce.

ALTER TABLE obligacion_catalogo
  ADD COLUMN tipo_recurrencia text NOT NULL DEFAULT 'relativa'
    CHECK (tipo_recurrencia IN ('relativa', 'calendario'));

COMMENT ON COLUMN obligacion_catalogo.tipo_recurrencia IS
  'calendario: el vencimiento lo fija una norma territorial, no la fecha base del usuario.';

ALTER TABLE obligacion_usuario
  ADD COLUMN tipo_recurrencia text NOT NULL DEFAULT 'relativa'
    CHECK (tipo_recurrencia IN ('relativa', 'calendario', 'declarada')),
  ADD COLUMN municipio_dane text REFERENCES municipio(codigo_dane),
  ADD COLUMN segmento text,
  ADD COLUMN modalidad text CHECK (modalidad IN ('anual', 'semestral', 'trimestral', 'cuotas'));

-- La fecha base solo tiene sentido en la recurrencia relativa: nadie declara
-- "desde cuando" tiene que pagar el predial.
ALTER TABLE obligacion_usuario ALTER COLUMN fecha_base DROP NOT NULL;

ALTER TABLE obligacion_usuario
  ADD CONSTRAINT recurrencia_coherente CHECK (
    CASE tipo_recurrencia
      WHEN 'relativa'   THEN fecha_base IS NOT NULL AND municipio_dane IS NULL
      WHEN 'calendario' THEN municipio_dane IS NOT NULL AND modalidad IS NOT NULL
      WHEN 'declarada'  THEN true
    END
  );

-- ---------------------------------------------------------------------------
-- Resolver el proximo vencimiento de una obligacion de calendario
-- ---------------------------------------------------------------------------
-- Devuelve la siguiente fecha estrictamente posterior a p_desde, junto con su
-- etiqueta y el descuento si lo hay. Si el municipio no tiene calendario
-- cargado para ese año, no devuelve nada: quien llame debe tratarlo como
-- "no se sabe" y caer a recurrencia declarada, nunca inventar una fecha.
--
-- Para los municipios cuyas fechas dependen del sector, p_segmento elige la
-- fila; donde el segmento es NULL en el calendario, la fecha aplica a todos.

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
  WHERE c.municipio_dane = p_municipio
    AND c.obligacion_codigo = p_obligacion
    AND c.modalidad = p_modalidad
    AND (v.segmento IS NULL OR v.segmento = p_segmento)
    -- El vencimiento que importa es el ordinario. Las fechas con recargo son
    -- informativas: avisar de ellas seria avisar de que ya se pago de mas.
    AND v.tipo IN ('ordinario', 'con_descuento')
    AND v.fecha > p_desde
  ORDER BY v.fecha
  LIMIT 1;
$$;

COMMENT ON FUNCTION app.proximo_vencimiento_calendario(text, text, text, text, date) IS
  'Proxima fecha segun la norma del municipio. Sin filas = calendario no cargado: caer a recurrencia declarada.';

REVOKE ALL ON FUNCTION app.proximo_vencimiento_calendario(text, text, text, text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.proximo_vencimiento_calendario(text, text, text, text, date)
  TO alivia_app, alivia_avisos;

-- El predial pasa a ser obligacion de calendario: ese UPDATE vive en
-- db/semillas/021_ajustes_catalogo.sql, porque es contenido y no estructura.
-- Puesto aqui correria contra una tabla vacia: las semillas se aplican despues.
