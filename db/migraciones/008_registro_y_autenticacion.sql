-- 008 · Las dos unicas operaciones que ocurren antes de que exista contexto
-- de usuario: registrarse e iniciar sesion.
--
-- Con RLS activo no hay forma de que funcionen por la via normal. Un usuario
-- nuevo no puede insertarse a si mismo, porque la politica exige que la fila
-- sea suya y todavia no tiene identidad. Y el inicio de sesion necesita buscar
-- por correo sin saber aun quien es.
--
-- La salida NO es aflojar las politicas ni conectar la API con el propietario:
-- es dar exactamente dos puertas, acotadas y auditables, en lugar de un
-- boquete. Todo lo demas sigue pasando por RLS.

-- Registro. Deja el usuario creado y devuelve su identificador, que la API usa
-- inmediatamente como contexto. La autorizacion de tratamiento de datos se
-- registra en la misma transaccion: es requisito, no un paso posterior.
CREATE OR REPLACE FUNCTION app.registrar_usuario(
  p_correo            text,
  p_contrasena_hash   text,
  p_nombre            text,
  p_version_politica  text,
  p_dias_anticipacion smallint DEFAULT 15,
  p_origen_ip         inet DEFAULT NULL,
  p_agente_usuario    text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, app AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO usuario (correo, contrasena_hash, nombre, dias_anticipacion)
  VALUES (lower(trim(p_correo)), p_contrasena_hash, p_nombre, p_dias_anticipacion)
  RETURNING id INTO v_id;

  -- Autorizacion general. La de datos de salud va aparte y es opcional: el
  -- titular puede negarse a entregarlos sin perder el resto del servicio.
  INSERT INTO autorizacion_tratamiento
    (usuario_id, finalidad, version_politica, origen_ip, agente_usuario)
  VALUES (v_id, 'general', p_version_politica, p_origen_ip, p_agente_usuario);

  -- Los tres modulos gratuitos quedan activos de entrada: el valor del producto
  -- esta en que el usuario vea obligaciones reales desde el primer minuto.
  INSERT INTO modulo_usuario (usuario_id, modulo_codigo)
  SELECT v_id, codigo FROM modulo WHERE plan = 'gratuito';

  RETURN v_id;
END
$$;

-- Inicio de sesion. Devuelve el hash para que la verificacion de la contraseña
-- ocurra en la aplicacion, nunca en la base de datos.
CREATE OR REPLACE FUNCTION app.credenciales_por_correo(p_correo text)
RETURNS TABLE (id uuid, contrasena_hash text, estado text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, app AS $$
  SELECT u.id, u.contrasena_hash, u.estado
  FROM usuario u
  WHERE u.correo = lower(trim(p_correo));
$$;

COMMENT ON FUNCTION app.credenciales_por_correo(text) IS
  'Unica via para leer un usuario sin contexto. Expone el hash: solo alivia_app puede ejecutarla.';

REVOKE ALL ON FUNCTION app.registrar_usuario(text, text, text, text, smallint, inet, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION app.credenciales_por_correo(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.registrar_usuario(text, text, text, text, smallint, inet, text) TO alivia_app;
GRANT EXECUTE ON FUNCTION app.credenciales_por_correo(text) TO alivia_app;
