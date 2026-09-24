-- Variantes de la revisión técnico-mecánica.
--
-- Fuente verificada en el texto vigente de la Ley 769 de 2002:
--   art. 52, modificado por el art. 179 de la Ley 2294 de 2023 — primera revisión
--   art. 51, modificado por el art. 201 del Decreto 019 de 2012 — periodicidad anual
--
-- El art. 12 de la Ley 1383 de 2010 decía dos años para todo vehículo nuevo sin
-- distinguir tipo. Está superado por la Ley 2294 de 2023 y no debe usarse.

INSERT INTO variante_obligacion
  (obligacion_codigo, clave, nombre, descripcion, periodicidad, desfase_primera,
   fuente_normativa, fuente_verificada, orden)
VALUES
  ('vehiculo.tecnomecanica', 'particular', 'Vehículo particular',
   'Automóvil, camioneta o campero de servicio particular. Primera revisión a partir del quinto año desde la matrícula.',
   interval '1 year', interval '5 years',
   'Ley 769 de 2002, art. 52, modificado por el art. 179 de la Ley 2294 de 2023', true, 1),

  ('vehiculo.tecnomecanica', 'motocicleta', 'Motocicleta o similar',
   'Motocicleta, motociclo o mototriciclo. Primera revisión al cumplir dos años desde la matrícula.',
   interval '1 year', interval '2 years',
   'Ley 769 de 2002, art. 52, modificado por el art. 179 de la Ley 2294 de 2023', true, 2),

  ('vehiculo.tecnomecanica', 'servicio_publico', 'Vehículo de servicio público',
   'Servicio público, escolar o de turismo. Primera revisión al cumplir dos años desde la matrícula.',
   interval '1 year', interval '2 years',
   'Ley 769 de 2002, art. 52, modificado por el art. 179 de la Ley 2294 de 2023', true, 3)
ON CONFLICT (obligacion_codigo, clave) DO NOTHING;
