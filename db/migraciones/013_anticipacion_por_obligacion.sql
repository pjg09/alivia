-- 013 · Ventana de anticipación propia por obligación. Salda la deuda D5.
--
-- EL PROBLEMA. La anticipación era una sola por usuario: los mismos días para
-- todo. Pero las urgencias no se parecen. El SOAT conviene avisarlo con un mes
-- porque hay que cotizar y comprarlo; el pago de una tarjeta de crédito con
-- tres días, porque avisar un mes antes de algo que se paga cada mes es ruido.
--
-- Y el ruido no es un inconveniente menor en este producto: un usuario que
-- silencia los avisos por pesados deja de recibir el que sí importaba. El
-- criterio de aceptación se pierde igual que si el aviso no se hubiera enviado.

-- El usuario puede fijar una anticipación para una obligación concreta.
-- NULL = usar la preferencia general de su cuenta.
ALTER TABLE obligacion_usuario
  ADD COLUMN dias_anticipacion smallint
    CHECK (dias_anticipacion IS NULL OR dias_anticipacion BETWEEN 1 AND 180);

COMMENT ON COLUMN obligacion_usuario.dias_anticipacion IS
  'Anticipación para esta obligación. NULL = usar la preferencia general del usuario.';

-- El catálogo puede sugerir una anticipación sensata por obligación.
-- Es una SUGERENCIA para la interfaz al crear, no un valor de respaldo: si el
-- usuario no la fija, manda su preferencia general. Quién decide tiene que ser
-- inequívoco, y decide el usuario.
ALTER TABLE obligacion_catalogo
  ADD COLUMN dias_anticipacion_sugeridos smallint
    CHECK (dias_anticipacion_sugeridos IS NULL OR dias_anticipacion_sugeridos BETWEEN 1 AND 180);

COMMENT ON COLUMN obligacion_catalogo.dias_anticipacion_sugeridos IS
  'Sugerencia que la interfaz propone al crear la obligación. No es un valor de respaldo: si el usuario no fija nada, manda su preferencia general.';

-- ---------------------------------------------------------------------------
-- La anticipación que realmente aplica
-- ---------------------------------------------------------------------------
-- Un solo sitio donde se decide, para que el proceso de avisos y la interfaz
-- no puedan discrepar. Si cada uno resolviera la precedencia por su cuenta, el
-- usuario vería en pantalla una cosa y recibiría el correo en otra fecha.

CREATE OR REPLACE FUNCTION app.anticipacion_efectiva(p_obligacion uuid)
RETURNS smallint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, app AS $$
  SELECT COALESCE(o.dias_anticipacion, u.dias_anticipacion)
  FROM obligacion_usuario o
  JOIN usuario u ON u.id = o.usuario_id
  WHERE o.id = p_obligacion;
$$;

COMMENT ON FUNCTION app.anticipacion_efectiva(uuid) IS
  'Días de anticipación que aplican: los de la obligación si los tiene, si no los del usuario. Único sitio donde se decide.';

REVOKE ALL ON FUNCTION app.anticipacion_efectiva(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.anticipacion_efectiva(uuid) TO alivia_app, alivia_avisos;
