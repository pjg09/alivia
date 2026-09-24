-- Curaduría de fuentes. Solo se marca verificado lo leído en el texto de la
-- norma, en el Gestor Normativo de Función Pública, no en resúmenes.
--
-- Lo verificado el 24 de septiembre de 2026:
--
--   Ley 769 de 2002, art. 42        obligatoriedad del SOAT
--   Ley 769 de 2002, art. 131 D     30 SMLDV, literal D.2 "conducir sin portar
--                                   los seguros ordenados por la ley"
--   Ley 769 de 2002, art. 131 C     15 SMLDV, literal C.35 "no realizar la
--                                   revisión técnico-mecánica en el plazo legal"
--   Ley 769 de 2002, art. 51        revisión anual, según art. 201 del Decreto 019 de 2012
--   Ley 769 de 2002, art. 52        primera revisión, según art. 179 de la Ley 2294 de 2023
--   Decreto 2257 de 1986, art. 33   obligatoriedad de vacunar animales domésticos
--   Decreto 2257 de 1986, art. 55   deber de exhibir certificado vigente
--   Ley 142 de 1994, art. 140       suspensión del servicio por falta de pago
--
-- Los literales D.2 y C.35 son los que la revisión de la Entrega 1 había
-- retirado del documento por venir de prensa. Quedan confirmados en el texto.

-- --- SOAT -------------------------------------------------------------------
-- Obligatoriedad y sanción verificadas. La vigencia anual NO: la fija la
-- póliza, y el código de tránsito no la menciona.
UPDATE obligacion_catalogo SET
  fuente_normativa  = 'Ley 769 de 2002, art. 42 — todo vehículo debe estar amparado por un seguro obligatorio vigente',
  fuente_sancion    = 'Ley 769 de 2002, art. 131 literal D.2 — 30 SMLDV e inmovilización (art. 131 modificado por el art. 21 de la Ley 1383 de 2010)',
  origen_plazo      = 'contrato',
  fuente_verificada = true,
  descripcion       = 'Comparendo de 30 SMLDV e inmovilización. La vigencia de un año la fija la póliza, no la ley.'
WHERE codigo = 'vehiculo.soat';

-- --- Tecnomecánica ----------------------------------------------------------
-- La única cuyo plazo sí lo fija una norma, de punta a punta.
UPDATE obligacion_catalogo SET
  fuente_sancion = 'Ley 769 de 2002, art. 131 literal C.35 — 15 SMLDV e inmovilización',
  origen_plazo   = 'norma'
WHERE codigo = 'vehiculo.tecnomecanica';

-- --- Predial y renta: el plazo lo fija un calendario territorial ------------
UPDATE obligacion_catalogo SET
  fuente_normativa  = 'Acuerdo o resolución de cada municipio. Los calendarios cargados están en calendario_tributario, cada uno con su norma',
  fuente_sancion    = 'Intereses de mora según el estatuto tributario de cada municipio',
  origen_plazo      = 'calendario',
  fuente_verificada = true
WHERE codigo = 'hogar.predial';

UPDATE obligacion_catalogo SET
  fuente_normativa  = 'Estatuto Tributario y decreto anual de plazos. El calendario cargado está en calendario_tributario',
  fuente_sancion    = 'Estatuto Tributario, sanción por extemporaneidad e intereses de mora — sin verificar el artículo',
  origen_plazo      = 'calendario',
  fuente_verificada = true
WHERE codigo = 'finanzas.renta';

-- --- Vacunación antirrábica -------------------------------------------------
-- Obligatoriedad verificada; la periodicidad la delega el propio decreto.
UPDATE obligacion_catalogo SET
  fuente_normativa  = 'Decreto 2257 de 1986, arts. 33 y 55 — obligatoria la vacunación de animales domésticos contra zoonosis inmunoprevenibles, y deber de exhibir certificado vigente',
  fuente_sancion    = 'Multas de la autoridad sanitaria — monto sin verificar',
  origen_plazo      = 'practica',
  fuente_verificada = true,
  descripcion       = 'Obligatoria en Colombia. El Decreto 2257 de 1986 delega la periodicidad en los Ministerios de Salud y Agricultura: el refuerzo anual sale de lineamiento, no del decreto.'
WHERE codigo = 'mascotas.antirrabica';

-- --- Servicios públicos -----------------------------------------------------
-- La ley dice cuándo pueden cortar, no cuándo hay que pagar.
UPDATE obligacion_catalogo SET
  fuente_normativa  = 'Ley 142 de 1994 — régimen de los servicios públicos domiciliarios',
  fuente_sancion    = 'Ley 142 de 1994, art. 140 — suspensión por falta de pago tras dos periodos si la facturación es bimestral, o tres si es mensual',
  origen_plazo      = 'factura',
  fuente_verificada = true,
  descripcion       = 'Suspensión del servicio y costo de reconexión. La fecha de pago la trae la factura de cada empresa, no la ley.'
WHERE codigo = 'finanzas.servicios_publicos';

-- --- Obligaciones de origen contractual o institucional ---------------------
-- No hay norma que verificar. Decirlo es la respuesta correcta.
UPDATE obligacion_catalogo SET
  fuente_normativa  = NULL,
  fuente_sancion    = 'Contrato con la entidad financiera: intereses de mora y reporte a centrales de riesgo',
  origen_plazo      = 'contrato',
  fuente_verificada = true,
  tipo_exigibilidad = 'sancionable',
  descripcion       = 'La fecha de corte y de pago la fija el contrato con la entidad. No hay norma que la establezca.'
WHERE codigo = 'finanzas.tarjeta_credito';

UPDATE obligacion_catalogo SET
  fuente_normativa  = NULL,
  fuente_sancion    = 'Pérdida del cupo, según el reglamento de cada institución',
  origen_plazo      = 'institucion',
  fuente_verificada = true,
  descripcion       = 'La fecha la fija el calendario de cada institución educativa.'
WHERE codigo = 'familia.matricula_escolar';

-- --- Las 32 tareas recomendadas --------------------------------------------
-- No tienen norma porque no hay sanción. Su plazo sale de manuales de
-- fabricante y de recomendación profesional. Marcarlas como "sin verificar"
-- sugeriría que existe algo que verificar, y no lo hay.
UPDATE obligacion_catalogo SET origen_plazo = 'practica'
WHERE tipo_exigibilidad = 'recomendada';
