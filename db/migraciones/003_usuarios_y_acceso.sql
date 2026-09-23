-- 003 · Usuarios, consentimiento, activacion de modulos y suscripciones.

CREATE TABLE usuario (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  correo             text NOT NULL UNIQUE CHECK (correo = lower(correo)),
  contrasena_hash    text NOT NULL,
  nombre             text,

  -- Ventana de anticipacion: cuantos dias antes del vencimiento quiere el aviso.
  -- De aqui parte el calculo del aviso. El prototipo la guardaba y no la usaba.
  dias_anticipacion  smallint NOT NULL DEFAULT 15
                     CHECK (dias_anticipacion BETWEEN 1 AND 180),

  -- Frecuencia de contacto configurable, exigida por la Ley 2300 de 2023.
  avisos_activos     boolean NOT NULL DEFAULT true,

  estado             text NOT NULL DEFAULT 'activo'
                     CHECK (estado IN ('activo', 'suspendido')),
  creado_en          timestamptz NOT NULL DEFAULT now()
);

-- Evidencia del consentimiento. La autorizacion de datos de salud va separada:
-- son categoria especial bajo la Ley 1581 de 2012, y el titular debe poder
-- negarse a entregarlos sin perder acceso al resto del servicio.
CREATE TABLE autorizacion_tratamiento (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id       uuid NOT NULL REFERENCES usuario(id),
  finalidad        text NOT NULL CHECK (finalidad IN ('general', 'datos_salud')),
  version_politica text NOT NULL,
  otorgada_en      timestamptz NOT NULL DEFAULT now(),
  revocada_en      timestamptz,
  origen_ip        inet,
  agente_usuario   text
);

CREATE INDEX ON autorizacion_tratamiento (usuario_id);

-- Activacion de modulos. Desactivar NO borra: solo suspende el acceso.
CREATE TABLE modulo_usuario (
  usuario_id     uuid NOT NULL REFERENCES usuario(id),
  modulo_codigo  text NOT NULL REFERENCES modulo(codigo),
  activado_en    timestamptz NOT NULL DEFAULT now(),
  desactivado_en timestamptz,
  PRIMARY KEY (usuario_id, modulo_codigo)
);

-- Suscripcion con vigencia. El prototipo solo sabia si un modulo estaba activo
-- o no, nunca hasta cuando, y el modelo de negocio es de ingreso recurrente.
CREATE TABLE suscripcion (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id    uuid NOT NULL REFERENCES usuario(id),
  modulo_codigo text NOT NULL REFERENCES modulo(codigo),
  inicio        date NOT NULL,
  fin           date NOT NULL,
  creada_en     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT vigencia_coherente CHECK (fin > inicio),

  -- Dos suscripciones del mismo usuario al mismo modulo no pueden solaparse.
  -- Lo impide el motor, no el codigo.
  CONSTRAINT sin_solape_de_vigencias
    EXCLUDE USING gist (
      usuario_id WITH =,
      modulo_codigo WITH =,
      daterange(inicio, fin, '[)') WITH &&
    )
);

CREATE INDEX ON suscripcion (usuario_id, modulo_codigo);

-- ---------------------------------------------------------------------------
-- Verificacion de acceso a modulos de pago
-- ---------------------------------------------------------------------------
-- En el prototipo la restriccion existia solo en la interfaz: cualquier usuario
-- podia activar un modulo de pago sin pagarlo. Aqui la verificacion ocurre en
-- la base de datos y las politicas RLS la aplican, de modo que no hay camino
-- que la eluda.
--
-- SECURITY DEFINER porque la funcion consulta suscripcion y modulo en nombre
-- del propietario: si dependiera de las politicas del llamante, se haria
-- recursiva.

CREATE OR REPLACE FUNCTION app.tiene_acceso(p_usuario uuid, p_modulo text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, app AS $$
  SELECT
    CASE
      WHEN (SELECT plan FROM modulo WHERE codigo = p_modulo) = 'gratuito' THEN true
      ELSE EXISTS (
        SELECT 1 FROM suscripcion s
        WHERE s.usuario_id = p_usuario
          AND s.modulo_codigo = p_modulo
          AND app.hoy() >= s.inicio
          AND app.hoy() <  s.fin
      )
    END;
$$;

COMMENT ON FUNCTION app.tiene_acceso(uuid, text) IS
  'Modulo gratuito: siempre. Modulo de pago: solo con suscripcion vigente a la fecha de referencia.';

REVOKE ALL ON FUNCTION app.tiene_acceso(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.tiene_acceso(uuid, text) TO alivia_app, alivia_avisos;
GRANT EXECUTE ON FUNCTION app.hoy(), app.usuario_actual() TO alivia_app, alivia_avisos;

GRANT SELECT, INSERT, UPDATE ON usuario, autorizacion_tratamiento, modulo_usuario, suscripcion TO alivia_app;
GRANT SELECT ON usuario TO alivia_avisos;
