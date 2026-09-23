-- 006 · Pasarela de pagos en modo de pruebas.
--
-- No mueve dinero y no habla con ningun proveedor: sin despliegue no hay
-- direccion publica a la que una pasarela real pueda notificar el resultado.
-- Reproduce los estados del flujo para demostrar la conversion completa.

CREATE TABLE pago_simulado (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id     uuid NOT NULL REFERENCES usuario(id),
  modulo_codigo  text NOT NULL REFERENCES modulo(codigo),
  suscripcion_id uuid REFERENCES suscripcion(id),

  referencia     text NOT NULL UNIQUE,
  monto          numeric(12,2) NOT NULL CHECK (monto > 0),
  moneda         text NOT NULL DEFAULT 'COP' CHECK (moneda IN ('COP', 'USD')),

  estado         text NOT NULL DEFAULT 'iniciado'
                 CHECK (estado IN ('iniciado', 'aprobado', 'rechazado', 'expirado')),
  motivo_rechazo text,

  creado_en      timestamptz NOT NULL DEFAULT now(),
  cerrado_en     timestamptz,

  -- Un pago aprobado tiene que haber creado la suscripcion que lo justifica.
  CONSTRAINT aprobado_tiene_suscripcion
    CHECK (estado <> 'aprobado' OR suscripcion_id IS NOT NULL)
);

CREATE INDEX ON pago_simulado (usuario_id);

GRANT SELECT, INSERT, UPDATE ON pago_simulado TO alivia_app;
