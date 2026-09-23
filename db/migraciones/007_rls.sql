-- 007 · Seguridad a nivel de fila.
--
-- Esta migracion es la que sostiene el requisito de aislamiento: "garantizado
-- por diseño del sistema, no por disciplina de quien escribe cada consulta".
--
-- Como funciona: la API abre transaccion, fija alivia.usuario_id, consulta.
-- Las politicas filtran por app.usuario_actual(). Si no se fijo el contexto,
-- la funcion devuelve NULL, la comparacion no es verdadera y no salen filas.
--
-- CONDICION CRITICA: alivia_app no es dueño de las tablas y no tiene BYPASSRLS.
-- Si la API se conectara con alivia_propietario, todo esto se ignoraria en
-- silencio y el aislamiento desapareceria sin un solo mensaje de error.

ALTER TABLE usuario                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE autorizacion_tratamiento ENABLE ROW LEVEL SECURITY;
ALTER TABLE modulo_usuario           ENABLE ROW LEVEL SECURITY;
ALTER TABLE suscripcion              ENABLE ROW LEVEL SECURITY;
ALTER TABLE obligacion_usuario       ENABLE ROW LEVEL SECURITY;
ALTER TABLE ocurrencia               ENABLE ROW LEVEL SECURITY;
ALTER TABLE aviso                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE pago_simulado            ENABLE ROW LEVEL SECURITY;

-- --- Usuario: solo su propia fila ------------------------------------------
CREATE POLICY usuario_propio ON usuario
  FOR ALL TO alivia_app
  USING (id = app.usuario_actual())
  WITH CHECK (id = app.usuario_actual());

-- --- Tablas con dueño directo ----------------------------------------------
CREATE POLICY autorizacion_propia ON autorizacion_tratamiento
  FOR ALL TO alivia_app
  USING (usuario_id = app.usuario_actual())
  WITH CHECK (usuario_id = app.usuario_actual());

CREATE POLICY modulo_usuario_propio ON modulo_usuario
  FOR ALL TO alivia_app
  USING (usuario_id = app.usuario_actual())
  WITH CHECK (usuario_id = app.usuario_actual());

CREATE POLICY suscripcion_propia ON suscripcion
  FOR ALL TO alivia_app
  USING (usuario_id = app.usuario_actual())
  WITH CHECK (usuario_id = app.usuario_actual());

CREATE POLICY pago_propio ON pago_simulado
  FOR ALL TO alivia_app
  USING (usuario_id = app.usuario_actual())
  WITH CHECK (usuario_id = app.usuario_actual());

CREATE POLICY aviso_propio ON aviso
  FOR SELECT TO alivia_app
  USING (usuario_id = app.usuario_actual());

-- --- Obligaciones y ocurrencias: dueño Y acceso vigente al modulo ----------
-- Aqui la verificacion de la suscripcion deja de ser una comprobacion que el
-- codigo puede olvidar y pasa a ser parte del filtro del motor. Un usuario sin
-- suscripcion vigente a un modulo de pago no puede crear ni leer obligaciones
-- de ese modulo, por ninguna ruta.
--
-- Consecuencia aceptada: al expirar la suscripcion el usuario deja de ver esas
-- obligaciones. No se borran y reaparecen al renovar. Es lo que pide el alcance:
-- la desactivacion conserva la informacion y solo suspende el acceso.

CREATE POLICY obligacion_propia_con_acceso ON obligacion_usuario
  FOR ALL TO alivia_app
  USING (
    usuario_id = app.usuario_actual()
    AND app.tiene_acceso(usuario_id, modulo_codigo)
  )
  WITH CHECK (
    usuario_id = app.usuario_actual()
    AND app.tiene_acceso(usuario_id, modulo_codigo)
  );

CREATE POLICY ocurrencia_propia ON ocurrencia
  FOR ALL TO alivia_app
  USING (usuario_id = app.usuario_actual())
  WITH CHECK (usuario_id = app.usuario_actual());

-- --- Proceso de avisos ------------------------------------------------------
-- Necesita leer obligaciones de todos los usuarios: es su trabajo. En lugar de
-- darle BYPASSRLS, que lo dejaria sin restriccion alguna, se le da una politica
-- explicita y acotada sobre las tablas que necesita. No atiende peticiones web.

CREATE POLICY avisos_lee_todo ON usuario
  FOR SELECT TO alivia_avisos USING (true);

CREATE POLICY avisos_lee_obligaciones ON obligacion_usuario
  FOR SELECT TO alivia_avisos USING (true);

CREATE POLICY avisos_lee_ocurrencias ON ocurrencia
  FOR SELECT TO alivia_avisos USING (true);

CREATE POLICY avisos_gestiona_avisos ON aviso
  FOR ALL TO alivia_avisos USING (true) WITH CHECK (true);
