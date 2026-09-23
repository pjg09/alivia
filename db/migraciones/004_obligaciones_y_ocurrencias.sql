-- 004 · Lo que el usuario tiene, y cada vencimiento concreto de eso.
--
-- Separacion deliberada en dos tablas:
--   obligacion_usuario  el compromiso permanente: "tengo un carro y su SOAT".
--   ocurrencia          cada vencimiento concreto: "el SOAT vence el 2026-11-04".
--
-- El prototipo tenia una sola tabla: al marcar cumplido, el recordatorio se
-- cerraba y no volvia. Con dos tablas la reprogramacion es crear una fila, el
-- historial se conserva y el aviso puede apuntar al vencimiento exacto.

CREATE TABLE obligacion_usuario (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id             uuid NOT NULL REFERENCES usuario(id),
  modulo_codigo          text NOT NULL REFERENCES modulo(codigo),

  origen                 text NOT NULL CHECK (origen IN ('catalogo', 'libre')),
  obligacion_catalogo_id uuid REFERENCES obligacion_catalogo(id),

  -- Copia del catalogo en el momento de crearla, no referencia viva.
  -- Corregir el catalogo no debe mover hacia atras los vencimientos que un
  -- usuario ya tiene calculados. Ver docs/modelo-datos.md.
  nombre                 text NOT NULL,
  descripcion            text,
  periodicidad           interval,
  desfase_primera        interval,
  tipo_exigibilidad      text NOT NULL CHECK (tipo_exigibilidad IN ('sancionable', 'recomendada')),
  fuente_normativa       text,

  -- El dato que solo el usuario conoce: cuando compro el carro, cuando fue su
  -- ultimo control medico. De aqui sale el primer vencimiento.
  fecha_base             date NOT NULL,

  archivada_en           timestamptz,
  creada_en              timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT origen_catalogo_exige_referencia
    CHECK (origen <> 'catalogo' OR obligacion_catalogo_id IS NOT NULL),

  -- Necesario para que ocurrencia pueda apuntar al par (id, usuario_id) y sea
  -- imposible que una ocurrencia declare un dueño distinto al de su obligacion.
  UNIQUE (id, usuario_id)
);

CREATE INDEX ON obligacion_usuario (usuario_id) WHERE archivada_en IS NULL;

CREATE TABLE ocurrencia (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  obligacion_usuario_id uuid NOT NULL,
  -- Desnormalizado a proposito: las politicas RLS filtran por esta columna sin
  -- necesidad de join. La clave foranea compuesta garantiza que no pueda mentir.
  usuario_id            uuid NOT NULL,

  numero                integer NOT NULL CHECK (numero >= 1),
  fecha_vencimiento     date NOT NULL,
  estado                text NOT NULL DEFAULT 'pendiente'
                        CHECK (estado IN ('pendiente', 'cumplida', 'omitida')),
  cumplida_en           timestamptz,
  creada_en             timestamptz NOT NULL DEFAULT now(),

  FOREIGN KEY (obligacion_usuario_id, usuario_id)
    REFERENCES obligacion_usuario (id, usuario_id),

  UNIQUE (obligacion_usuario_id, numero),

  CONSTRAINT cumplida_tiene_fecha
    CHECK ((estado = 'cumplida') = (cumplida_en IS NOT NULL))
);

-- Una obligacion no puede tener dos vencimientos pendientes a la vez: impide
-- que un fallo en la reprogramacion duplique la siguiente ocurrencia.
CREATE UNIQUE INDEX una_ocurrencia_pendiente_por_obligacion
  ON ocurrencia (obligacion_usuario_id) WHERE estado = 'pendiente';

-- El indice que usa la evaluacion diaria: vencimientos pendientes por fecha.
CREATE INDEX ocurrencias_pendientes_por_vencimiento
  ON ocurrencia (fecha_vencimiento) WHERE estado = 'pendiente';

CREATE INDEX ON ocurrencia (usuario_id);

GRANT SELECT, INSERT, UPDATE ON obligacion_usuario, ocurrencia TO alivia_app;
GRANT SELECT ON obligacion_usuario, ocurrencia TO alivia_avisos;
