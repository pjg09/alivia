-- Catalogo base, rescatado del prototipo descartado.
--
-- ADVERTENCIA: este contenido NO esta validado. Ninguna fuente normativa esta
-- comprobada contra la norma, por eso todas entran con fuente_verificada=false.
-- Curarlo es trabajo pendiente y es lo que le da valor al producto.
-- Fuente: ../gestion-de-proyectos/docs/proyecto/catalogo-obligaciones.md
--
-- No se siembran "lavado y aspirado" (14 d) ni "revisar pico y placa" (7 d):
-- el propio catalogo las marca como candidatas a eliminar. La segunda no es
-- siquiera un vencimiento, sino una restriccion rotativa.

-- ---------------------------------------------------------------------------
-- Obligaciones con consecuencia legal o economica. Son el producto.
-- ---------------------------------------------------------------------------
INSERT INTO obligacion_catalogo
  (codigo, nombre, modulo_codigo, periodicidad, desfase_primera, tipo_exigibilidad, fuente_normativa, fuente_verificada, descripcion)
VALUES
  ('vehiculo.soat', 'Renovar SOAT', 'vehiculo', interval '1 year', NULL, 'sancionable',
   'Ley 769 de 2002 — artículo sin verificar', false,
   'Comparendo de 30 SMDLV, inmovilización y bloqueo del RUNT'),

  -- Desfase real: la primera revision se exige al quinto año en carros
  -- particulares. Las motocicletas son al segundo, caso que este catalogo
  -- todavia no distingue.
  ('vehiculo.tecnomecanica', 'Revisión técnico-mecánica', 'vehiculo', interval '1 year', interval '5 years', 'sancionable',
   'Ley 769 de 2002 — artículo sin verificar', false,
   'Comparendo de 15 SMDLV e inmovilización. Primera revisión al quinto año en carros particulares'),

  ('hogar.predial', 'Impuesto predial', 'hogar', interval '1 year', NULL, 'sancionable',
   'Acuerdo municipal aplicable — pendiente de determinar', false,
   'Intereses de mora. Plazo y descuento por pronto pago varían por municipio'),

  ('finanzas.renta', 'Declaración de renta', 'finanzas', interval '1 year', NULL, 'sancionable',
   'Estatuto Tributario y calendario DIAN — pendiente', false,
   'Sanción por extemporaneidad e intereses de mora. El plazo depende del NIT'),

  ('finanzas.tarjeta_credito', 'Pago de tarjeta de crédito', 'finanzas', interval '1 month', NULL, 'sancionable',
   'Contrato con la entidad financiera', false,
   'Intereses de mora y reporte a centrales de riesgo'),

  ('finanzas.servicios_publicos', 'Pago de servicios públicos', 'finanzas', interval '1 month', NULL, 'sancionable',
   'Ley 142 de 1994 — artículo sin verificar', false,
   'Suspensión del servicio y costo de reconexión'),

  ('familia.matricula_escolar', 'Matrícula escolar', 'familia', interval '1 year', NULL, 'sancionable',
   'Calendario de cada institución educativa', false,
   'Pérdida del cupo'),

  ('mascotas.antirrabica', 'Vacunación antirrábica', 'mascotas', interval '1 year', NULL, 'sancionable',
   'Norma nacional y distrital — sin verificar', false,
   'Obligatoria en Colombia')
ON CONFLICT (codigo) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Tareas recomendadas. Acompañan al producto, no lo sostienen.
-- ---------------------------------------------------------------------------
INSERT INTO obligacion_catalogo
  (codigo, nombre, modulo_codigo, periodicidad, tipo_exigibilidad)
VALUES
  ('vehiculo.aceite',        'Cambio de aceite y filtro',        'vehiculo', interval '180 days',  'recomendada'),
  ('vehiculo.frenos',        'Revisión de frenos',               'vehiculo', interval '180 days',  'recomendada'),
  ('vehiculo.rotacion',      'Rotación de llantas',              'vehiculo', interval '180 days',  'recomendada'),
  ('vehiculo.llantas',       'Cambio de llantas',                'vehiculo', interval '730 days',  'recomendada'),
  ('vehiculo.luces',         'Revisión de luces',                'vehiculo', interval '90 days',   'recomendada'),
  ('vehiculo.bateria',       'Cambio de batería',                'vehiculo', interval '1095 days', 'recomendada'),

  ('hogar.refrigeradora',    'Revisar refrigeradora',            'hogar',    interval '180 days',  'recomendada'),
  ('hogar.calentador',       'Revisión del calentador',          'hogar',    interval '180 days',  'recomendada'),
  ('hogar.focos',            'Cambio de focos',                  'hogar',    interval '1 year',    'recomendada'),
  ('hogar.baterias',         'Cambio de baterías de dispositivos','hogar',   interval '1 year',    'recomendada'),
  ('hogar.mantenimiento',    'Mantenimiento general',            'hogar',    interval '180 days',  'recomendada'),
  ('hogar.tanque_agua',      'Limpieza del tanque de agua',      'hogar',    interval '1 year',    'recomendada'),
  -- Posible obligacion: verificar si la revision periodica de gas es exigible.
  ('hogar.instalacion_gas',  'Revisión de instalación de gas',   'hogar',    interval '1 year',    'recomendada'),

  ('salud.chequeo_general',  'Chequeo médico general',           'salud',    interval '1 year',    'recomendada'),
  ('salud.odontologia',      'Consulta odontológica',            'salud',    interval '180 days',  'recomendada'),
  ('salud.vista',            'Examen de vista',                  'salud',    interval '1 year',    'recomendada'),
  ('salud.laboratorio',      'Exámenes de laboratorio de control','salud',   interval '180 days',  'recomendada'),
  ('salud.vacunacion',       'Vacunación anual',                 'salud',    interval '1 year',    'recomendada'),
  ('salud.donacion_sangre',  'Donación de sangre',               'salud',    interval '90 days',   'recomendada'),

  ('finanzas.extractos',     'Revisar extractos bancarios',      'finanzas', interval '1 month',   'recomendada'),
  ('finanzas.ahorro',        'Ahorro mensual',                   'finanzas', interval '1 month',   'recomendada'),

  ('familia.cumpleanos',     'Cumpleaños familiar',              'familia',  interval '1 year',    'recomendada'),
  ('familia.aniversario',    'Aniversario',                      'familia',  interval '1 year',    'recomendada'),
  ('familia.reunion_padres', 'Reunión de padres',                'familia',  interval '90 days',   'recomendada'),
  ('familia.dia_padres',     'Día del padre / de la madre',      'familia',  interval '1 year',    'recomendada'),
  ('familia.navidad',        'Navidad y fin de año',             'familia',  interval '1 year',    'recomendada'),
  ('familia.semana_santa',   'Semana Santa',                     'familia',  interval '1 year',    'recomendada'),

  ('mascotas.polivalente',   'Vacuna polivalente',               'mascotas', interval '1 year',    'recomendada'),
  ('mascotas.desparasitacion','Desparasitación',                 'mascotas', interval '90 days',   'recomendada'),
  ('mascotas.chequeo',       'Chequeo veterinario',              'mascotas', interval '180 days',  'recomendada'),
  ('mascotas.alimento',      'Compra de alimento',               'mascotas', interval '1 month',   'recomendada'),
  ('mascotas.peluqueria',    'Baño y peluquería',                'mascotas', interval '45 days',   'recomendada')
ON CONFLICT (codigo) DO NOTHING;
