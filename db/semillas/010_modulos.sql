-- Los siete modulos. Vehiculo y hogar son gratuitos a proposito: es donde esta
-- la multa evitable, y no debe quedar detras de un pago.

INSERT INTO modulo (codigo, nombre, descripcion, plan, orden) VALUES
  ('hogar',    'Hogar',    'Impuesto predial, servicios, mantenimientos del inmueble', 'gratuito', 1),
  ('vehiculo', 'Vehículo', 'SOAT, revisión tecnomecánica, mantenimientos',             'gratuito', 2),
  ('familia',  'Familia',  'Fechas familiares, matrículas escolares',                  'gratuito', 3),
  ('salud',    'Salud',    'Controles médicos, exámenes periódicos, vacunación',       'pago',     4),
  ('finanzas', 'Finanzas', 'Declaración de renta, tarjetas, obligaciones tributarias', 'pago',     5),
  ('mascotas', 'Mascotas', 'Vacunación, desparasitación, controles veterinarios',      'pago',     6),
  ('general',  'General',  'Recordatorios personalizados del usuario',                 'pago',     7)
ON CONFLICT (codigo) DO NOTHING;
