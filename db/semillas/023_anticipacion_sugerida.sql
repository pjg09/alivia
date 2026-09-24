-- Anticipación sugerida por obligación.
--
-- No sale de ninguna norma: es criterio de producto, y está sin validar con
-- usuarios. El trabajo de campo que lo respaldaría no se ha hecho. Se siembra
-- porque una sugerencia razonada es mejor que ninguna, no porque esté probada.
--
-- El criterio: cuánto tiempo necesita alguien para resolver la obligación, no
-- cuánto falta para que venza. Comprar un SOAT toma minutos pero hay que
-- cotizar; una tecnomecánica exige pedir cita y llevar el carro; pagar una
-- tarjeta es inmediato.

UPDATE obligacion_catalogo SET dias_anticipacion_sugeridos = v.dias
FROM (VALUES
  ('vehiculo.soat',               30),  -- cotizar y comprar
  ('vehiculo.tecnomecanica',      30),  -- pedir cita y llevar el vehículo
  ('hogar.predial',               30),  -- conseguir el dinero; suele ser un monto alto
  ('finanzas.renta',              45),  -- reunir certificados y soportes
  ('finanzas.tarjeta_credito',     5),  -- inmediato, y es mensual: avisar antes es ruido
  ('finanzas.servicios_publicos',  5),  -- igual, mensual
  ('familia.matricula_escolar',   30),
  ('mascotas.antirrabica',        15)
) AS v(codigo, dias)
WHERE obligacion_catalogo.codigo = v.codigo;
