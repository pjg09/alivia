-- Ajustes al catálogo base que dependen de las estructuras añadidas en las
-- migraciones 009, 010 y 011.
--
-- POR QUE ESTAN AQUI Y NO EN LA MIGRACION QUE LOS INTRODUJO: aplicar.sh corre
-- todas las migraciones antes que las semillas. Un UPDATE sobre el catálogo
-- puesto dentro de una migración se ejecuta contra una tabla vacía y no hace
-- nada, en silencio. Funciona en la máquina de quien fue añadiendo migraciones
-- sobre una base ya sembrada, y falla en una instalación desde cero — que es
-- precisamente la que tendrán los demás integrantes.
--
-- Las migraciones son estructura. El contenido del catálogo vive en semillas.

-- --- D1 · el predial lo fija el calendario de cada municipio ---------------
UPDATE obligacion_catalogo
   SET tipo_recurrencia = 'calendario',
       periodicidad     = NULL,
       descripcion      = 'Lo fija el acuerdo o la resolución de cada municipio. '
                          'Sin calendario cargado, la fecha la declara el usuario.'
 WHERE codigo = 'hogar.predial';

-- --- D2 · la renta la fija el calendario nacional de la DIAN ---------------
UPDATE obligacion_catalogo
   SET tipo_recurrencia = 'calendario',
       periodicidad     = NULL,
       descripcion      = 'El plazo depende de los dos últimos dígitos del NIT y lo fija '
                          'un decreto nacional que se expide cada año. Sin calendario '
                          'cargado, la fecha la declara el usuario.'
 WHERE codigo = 'finanzas.renta';

-- NOTA: la curaduría de fuentes continúa en 022_fuentes_verificadas.sql.

-- --- D3 · la tecnomecánica depende del tipo de vehículo --------------------
UPDATE obligacion_catalogo
   SET atributo_variante = 'tipo_vehiculo',
       desfase_primera   = NULL,   -- lo aporta cada variante
       periodicidad      = interval '1 year',
       fuente_normativa  = 'Ley 769 de 2002, arts. 51 y 52 — art. 51 modificado por el art. 201 '
                           'del Decreto 019 de 2012; art. 52 modificado por el art. 179 de la Ley 2294 de 2023',
       fuente_verificada = true,
       descripcion       = 'Comparendo de 15 SMDLV e inmovilización. La primera revisión depende '
                           'del tipo de vehículo; después es anual para todos.'
 WHERE codigo = 'vehiculo.tecnomecanica';
