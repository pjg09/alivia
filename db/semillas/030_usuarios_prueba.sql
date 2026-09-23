-- Usuarios de prueba. Los hashes son marcadores, no contraseñas reales: la
-- autenticacion todavia no existe. Ningun secreto vive en el repositorio.
--
-- Ana tiene suscripcion vigente a salud durante 2026. Beto no tiene ninguna.
-- Esa asimetria es la que verifica db/pruebas/rls.sql.

INSERT INTO usuario (correo, contrasena_hash, nombre, dias_anticipacion) VALUES
  ('ana@prueba.local',  'marcador-no-es-un-hash-real', 'Ana',  15),
  ('beto@prueba.local', 'marcador-no-es-un-hash-real', 'Beto', 30)
ON CONFLICT (correo) DO NOTHING;

INSERT INTO modulo_usuario (usuario_id, modulo_codigo)
SELECT u.id, m.codigo FROM usuario u CROSS JOIN modulo m
WHERE u.correo IN ('ana@prueba.local','beto@prueba.local') AND m.plan = 'gratuito'
ON CONFLICT DO NOTHING;

INSERT INTO suscripcion (usuario_id, modulo_codigo, inicio, fin)
SELECT id, 'salud', DATE '2026-01-01', DATE '2027-01-01'
FROM usuario WHERE correo = 'ana@prueba.local'
ON CONFLICT DO NOTHING;

INSERT INTO modulo_usuario (usuario_id, modulo_codigo)
SELECT id, 'salud' FROM usuario WHERE correo = 'ana@prueba.local'
ON CONFLICT DO NOTHING;

INSERT INTO obligacion_usuario
  (usuario_id, modulo_codigo, origen, obligacion_catalogo_id, nombre, periodicidad, desfase_primera, tipo_exigibilidad, fuente_normativa, fecha_base)
SELECT u.id, c.modulo_codigo, 'catalogo', c.id, 'ANA ' || c.nombre,
       c.periodicidad, c.desfase_primera, c.tipo_exigibilidad, c.fuente_normativa, DATE '2026-03-10'
FROM usuario u, obligacion_catalogo c
WHERE u.correo = 'ana@prueba.local' AND c.codigo IN ('vehiculo.soat', 'salud.chequeo_general');

INSERT INTO obligacion_usuario
  (usuario_id, modulo_codigo, origen, obligacion_catalogo_id, nombre, periodicidad, desfase_primera, tipo_exigibilidad, fuente_normativa, fecha_base)
SELECT u.id, c.modulo_codigo, 'catalogo', c.id, 'BETO ' || c.nombre,
       c.periodicidad, c.desfase_primera, c.tipo_exigibilidad, c.fuente_normativa, DATE '2026-05-20'
FROM usuario u, obligacion_catalogo c
WHERE u.correo = 'beto@prueba.local' AND c.codigo = 'hogar.predial';
