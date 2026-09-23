-- 005 · Registro de avisos. Es el entregable de evidencia del criterio de
-- aceptacion: con esta tabla se demuestra que el aviso salio ANTES del
-- vencimiento, y no despues.

CREATE TABLE aviso (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id       uuid NOT NULL REFERENCES usuario(id),
  ocurrencia_id    uuid NOT NULL REFERENCES ocurrencia(id),

  tipo             text NOT NULL DEFAULT 'anticipacion'
                   CHECK (tipo IN ('anticipacion', 'vencimiento')),

  -- Con cuantos dias de anticipacion salio, y contra que fecha se evaluo.
  -- Guardar ambos permite auditar el criterio de aceptacion sin recalcular.
  dias_antes       integer NOT NULL,
  evaluado_para    date NOT NULL,

  -- Estado REAL del envio. El prototipo escribia el aviso en la consola del
  -- servidor y lo registraba como enviado: la base de datos afirmaba que habia
  -- salido algo que nunca salio. 'entregado' solo si el servidor SMTP acepto.
  estado           text NOT NULL DEFAULT 'pendiente'
                   CHECK (estado IN ('pendiente', 'entregado', 'fallido')),
  intentos         smallint NOT NULL DEFAULT 0,
  error            text,

  -- Message-ID que devuelve el servidor SMTP. Permite cruzar cada fila con el
  -- mensaje concreto en Mailpit, que es como se verifica la entrega.
  mensaje_id       text,

  creado_en        timestamptz NOT NULL DEFAULT now(),
  enviado_en       timestamptz,

  CONSTRAINT entregado_tiene_fecha
    CHECK ((estado = 'entregado') = (enviado_en IS NOT NULL)),

  CONSTRAINT anticipacion_es_anticipada
    CHECK (tipo <> 'anticipacion' OR dias_antes > 0)
);

-- Idempotencia en el motor, no en el codigo: un mismo vencimiento no genera dos
-- veces el mismo tipo de aviso, pase lo que pase con los reintentos.
CREATE UNIQUE INDEX un_aviso_por_ocurrencia_y_tipo
  ON aviso (ocurrencia_id, tipo);

CREATE INDEX ON aviso (usuario_id);
CREATE INDEX ON aviso (estado) WHERE estado <> 'entregado';

GRANT SELECT ON aviso TO alivia_app;
GRANT SELECT, INSERT, UPDATE ON aviso TO alivia_avisos;
