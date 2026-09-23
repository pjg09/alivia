-- 002 · Catalogo de obligaciones. El diferenciador del producto.
--
-- Es informacion administrable del sistema, NO constantes en el codigo del
-- cliente. Debe poder corregirse y ampliarse sin volver a publicar la
-- aplicacion, y es el mismo catalogo para todos los usuarios.

CREATE TABLE modulo (
  codigo      text PRIMARY KEY,
  nombre      text NOT NULL,
  descripcion text,
  plan        text NOT NULL CHECK (plan IN ('gratuito', 'pago')),
  orden       smallint NOT NULL
);

COMMENT ON TABLE modulo IS
  'Los siete modulos. Vehiculo y hogar son gratuitos a proposito: es donde esta la multa evitable.';

CREATE TABLE categoria (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  modulo_codigo text NOT NULL REFERENCES modulo(codigo),
  nombre        text NOT NULL,
  orden         smallint NOT NULL DEFAULT 0,
  UNIQUE (modulo_codigo, nombre)
);

CREATE TABLE obligacion_catalogo (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo            text NOT NULL UNIQUE,
  nombre            text NOT NULL,
  descripcion       text,
  modulo_codigo     text NOT NULL REFERENCES modulo(codigo),
  categoria_id      uuid REFERENCES categoria(id),

  -- Periodicidad como intervalo, no como numero de dias. Ver docs/modelo-datos.md:
  -- el SOAT vence el mismo dia del año siguiente, y 365 dias se desfasan en bisiestos.
  -- NULL = obligacion de una sola vez, no recurrente.
  periodicidad      interval,

  -- El primer vencimiento no siempre cae a una periodicidad de la fecha base.
  -- Caso real: la revision tecnico-mecanica se exige por primera vez al quinto
  -- año en carros particulares y al segundo en motocicletas, y desde ahi es
  -- anual. Sin este campo el sistema avisaria de una tecnomecanica que todavia
  -- no es exigible, que es el error de dominio que arruina la credibilidad.
  -- NULL = el primer vencimiento cae a una periodicidad de la fecha base.
  desfase_primera   interval,

  -- El campo que sostiene el argumento de valor del producto: separa la
  -- obligacion con consecuencia legal o economica de la tarea recomendada.
  tipo_exigibilidad text NOT NULL CHECK (tipo_exigibilidad IN ('sancionable', 'recomendada')),
  fuente_normativa  text,
  fuente_url        text,

  -- El catalogo heredado NO esta validado: ninguna de sus entradas tiene
  -- todavia la fuente comprobada contra la norma. Declararlo en el dato evita
  -- que el sistema presente como verificado lo que solo esta declarado.
  fuente_verificada boolean NOT NULL DEFAULT false,

  activa            boolean NOT NULL DEFAULT true,
  creada_en         timestamptz NOT NULL DEFAULT now(),
  actualizada_en    timestamptz NOT NULL DEFAULT now(),

  -- Una obligacion sancionable sin fuente normativa no entra. Esto impide por
  -- construccion que se cuelen tareas domesticas ("lavar el carro") como si
  -- tuvieran consecuencia legal, que es el defecto que hoy tiene el catalogo.
  CONSTRAINT sancionable_exige_fuente
    CHECK (tipo_exigibilidad <> 'sancionable' OR fuente_normativa IS NOT NULL),

  CONSTRAINT periodicidad_positiva
    CHECK (periodicidad IS NULL OR periodicidad > interval '0'),

  CONSTRAINT desfase_positivo
    CHECK (desfase_primera IS NULL OR desfase_primera > interval '0'),

  -- Un desfase sin periodicidad no significa nada.
  CONSTRAINT desfase_exige_periodicidad
    CHECK (desfase_primera IS NULL OR periodicidad IS NOT NULL)
);

CREATE INDEX ON obligacion_catalogo (modulo_codigo) WHERE activa;

-- El catalogo es de lectura para la aplicacion. Administrarlo es tarea del
-- propietario: no hay interfaz de administracion en este alcance.
GRANT SELECT ON modulo, categoria, obligacion_catalogo TO alivia_app, alivia_avisos;
