-- 011 · Variantes de una obligación. Salda la deuda D3.
--
-- EL PROBLEMA. La revisión técnico-mecánica no vence igual para todos: depende
-- de qué vehículo sea. El catálogo guardaba un solo desfase, el de carros
-- particulares, así que a un motociclista se le habría avisado tres años tarde.
--
-- LO QUE DICE LA NORMA, verificada en el texto vigente:
--
--   Art. 51 (periodicidad), según el art. 201 del Decreto 019 de 2012:
--     "todos los vehículos automotores deben someterse anualmente a revisión
--      técnico-mecánica y de emisiones contaminantes"
--
--   Art. 52 (primera revisión), según el art. 179 de la Ley 2294 de 2023:
--     particular distinto de motocicleta  -> a partir del quinto (5) año
--     servicio público y motocicletas     -> al cumplir dos (2) años
--
-- OJO al leer estas normas: el art. 12 de la Ley 1383 de 2010 decía dos años
-- para todos los vehículos nuevos, sin distinguir. Está superado. Quien
-- consulte esa ley sin mirar las modificaciones posteriores sembrará mal el
-- dato.

CREATE TABLE variante_obligacion (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  obligacion_codigo text NOT NULL REFERENCES obligacion_catalogo(codigo),

  clave             text NOT NULL,
  nombre            text NOT NULL,
  descripcion       text,

  -- Cada variante trae su propio calendario. NULL hereda el del catálogo.
  periodicidad      interval,
  desfase_primera   interval,

  fuente_normativa  text,
  fuente_verificada boolean NOT NULL DEFAULT false,
  orden             smallint NOT NULL DEFAULT 0,

  UNIQUE (obligacion_codigo, clave),

  CONSTRAINT periodicidad_variante_positiva
    CHECK (periodicidad IS NULL OR periodicidad > interval '0'),
  CONSTRAINT desfase_variante_positivo
    CHECK (desfase_primera IS NULL OR desfase_primera > interval '0')
);

COMMENT ON TABLE variante_obligacion IS
  'Una misma obligación con plazos distintos según un atributo del bien: el tipo de vehículo, por ahora.';

-- Qué tiene que declarar el usuario para saber qué variante le toca.
-- NULL = la obligación no tiene variantes.
ALTER TABLE obligacion_catalogo
  ADD COLUMN atributo_variante text;

COMMENT ON COLUMN obligacion_catalogo.atributo_variante IS
  'Dato que el usuario debe declarar para elegir variante. NULL si la obligación no las tiene.';

ALTER TABLE obligacion_usuario
  ADD COLUMN variante_id uuid REFERENCES variante_obligacion(id);

-- ---------------------------------------------------------------------------
-- Una obligación con variantes no puede crearse sin elegir una
-- ---------------------------------------------------------------------------
-- No se puede expresar con CHECK porque cruza tablas. Va como disparador, que
-- es lo que corresponde: es una regla del dominio, no una preferencia de la
-- aplicación. Si se dejara a la aplicación, se olvidaría una vez y el usuario
-- recibiría el aviso del vehículo equivocado.

CREATE OR REPLACE FUNCTION app.exigir_variante() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_atributo text;
BEGIN
  IF NEW.origen <> 'catalogo' THEN
    RETURN NEW;
  END IF;

  SELECT atributo_variante INTO v_atributo
  FROM obligacion_catalogo WHERE id = NEW.obligacion_catalogo_id;

  IF v_atributo IS NOT NULL AND NEW.variante_id IS NULL THEN
    RAISE EXCEPTION
      'La obligación exige declarar % y no se eligió variante', v_atributo
      USING ERRCODE = 'check_violation';
  END IF;

  -- Y la variante elegida tiene que ser de esta obligación, no de otra.
  IF NEW.variante_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM variante_obligacion v
       JOIN obligacion_catalogo c ON c.codigo = v.obligacion_codigo
       WHERE v.id = NEW.variante_id AND c.id = NEW.obligacion_catalogo_id) THEN
    RAISE EXCEPTION 'La variante elegida no pertenece a esta obligación'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END
$$;

CREATE TRIGGER exigir_variante
  BEFORE INSERT OR UPDATE ON obligacion_usuario
  FOR EACH ROW EXECUTE FUNCTION app.exigir_variante();

GRANT SELECT ON variante_obligacion TO alivia_app, alivia_avisos;

-- La tecnomecánica pasa a tener variantes: ese UPDATE vive en
-- db/semillas/021_ajustes_catalogo.sql. Ver la nota de la migración 009.
