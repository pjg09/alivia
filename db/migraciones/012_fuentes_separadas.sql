-- 012 · Separar tres cosas que el catálogo confundía en un solo campo.
--       Salda la deuda D4.
--
-- EL PROBLEMA, que resultó ser de modelo y no de datos. El alcance pide que
-- cada obligación declare "la fuente normativa que respalda esa periodicidad".
-- Al ir a verificarlas una por una aparece que eso, para varias obligaciones,
-- NO EXISTE. Son tres cosas distintas:
--
--   1. Qué norma hace la obligación obligatoria.
--   2. Qué norma fija la sanción por incumplirla.
--   3. Qué fija la FECHA. Y esto último muchas veces no es una norma.
--
-- Ejemplos verificados en el texto de cada norma:
--
--   SOAT           obligatorio por el art. 42 de la Ley 769 de 2002; la sanción
--                  es el art. 131 literal D.2, 30 SMLDV. Pero la vigencia anual
--                  la fija la póliza, no el código de tránsito.
--   Antirrábica    obligatoria por el art. 33 del Decreto 2257 de 1986, que
--                  dice literalmente que la periodicidad la señalan los
--                  Ministerios de Salud y Agricultura. El decreto NO dice
--                  "cada año".
--   Servicios      la Ley 142 de 1994, art. 140, dice cuándo pueden suspender
--                  el servicio, no cuándo hay que pagar. La fecha la trae la
--                  factura de cada empresa.
--   Tarjeta        no hay norma: la fecha de corte la fija el contrato.
--   Matrícula      la fija el calendario de cada institución educativa.
--
-- Guardar todo eso en un solo campo llamado "fuente_normativa" obliga o a
-- mentir o a dejarlo vacío. El catálogo pasa a decir de dónde sale cada cosa.

ALTER TABLE obligacion_catalogo
  ADD COLUMN fuente_sancion text,
  ADD COLUMN origen_plazo text NOT NULL DEFAULT 'practica'
    CHECK (origen_plazo IN ('norma', 'calendario', 'contrato', 'factura', 'institucion', 'practica'));

COMMENT ON COLUMN obligacion_catalogo.fuente_normativa IS
  'Norma que hace la obligación obligatoria. No necesariamente la que fija su plazo.';
COMMENT ON COLUMN obligacion_catalogo.fuente_sancion IS
  'Norma que fija la consecuencia de incumplir, cuando es distinta de la anterior.';
COMMENT ON COLUMN obligacion_catalogo.origen_plazo IS
  'De dónde sale la FECHA: norma, calendario territorial, contrato, factura, institución educativa o práctica recomendada.';

-- Si el plazo lo fija una norma, esa norma tiene que estar escrita. Si lo fija
-- un contrato o una factura, exigir una norma seria inventarla.
ALTER TABLE obligacion_catalogo
  ADD CONSTRAINT plazo_normativo_exige_norma
    CHECK (origen_plazo <> 'norma' OR fuente_normativa IS NOT NULL);

-- Y el usuario debe poder ver esa distinción, no solo el sistema.
ALTER TABLE obligacion_usuario
  ADD COLUMN origen_plazo text;

-- La restricción de la migración 002 exigía fuente normativa a toda obligación
-- sancionable. Ese era el supuesto falso: el pago de una tarjeta de crédito
-- tiene consecuencia económica real —intereses y reporte a centrales de
-- riesgo— y no hay norma que fije su fecha, porque la fija el contrato.
--
-- Lo que sí hay que exigir es que una obligación con consecuencia declare
-- CUÁL es esa consecuencia y de dónde sale. Eso es lo que impide que se cuele
-- una tarea doméstica presentada como obligación, que era el objetivo.
ALTER TABLE obligacion_catalogo DROP CONSTRAINT sancionable_exige_fuente;

ALTER TABLE obligacion_catalogo
  ADD CONSTRAINT sancionable_declara_su_consecuencia
    CHECK (tipo_exigibilidad <> 'sancionable'
           OR fuente_normativa IS NOT NULL
           OR fuente_sancion IS NOT NULL);
