// Arranque del servidor: validar, conectar, escuchar, y apagar bien. Nada más.
//
// La aplicación está en http/servidor.ts, que no escucha: así se puede probar
// levantándola en un puerto efímero sin arrancar el proceso entero.
//
// Lo que falta, y dónde:
//   dominio/   cálculo de vencimientos, selección de avisos   tarea 19 y ss.
//   http/      las rutas de cuentas, catálogo y obligaciones  tarea 11 y ss.

import { ErrorDeConfiguracion } from "./configuracion/entorno.js";
import {
  avisosDeArranque,
  cargarConfiguracionServidor,
  resumir,
} from "./configuracion/servidor.js";
import { cerrarAcceso, iniciarAcceso } from "./datos/contexto.js";
import { crearServidor } from "./http/servidor.js";

// La configuración se valida ANTES de abrir el puerto: si falta una variable
// obligatoria el proceso muere aquí, diciendo cuál, en lugar de arrancar y
// fallar más tarde en otro sitio. Tarea 2.
let configuracion: ReturnType<typeof cargarConfiguracionServidor>;
try {
  configuracion = cargarConfiguracionServidor();
} catch (error) {
  if (error instanceof ErrorDeConfiguracion) {
    console.error(error.informe());
    process.exit(1);
  }
  throw error;
}

for (const linea of resumir(configuracion)) console.log(`[alivia/api] ${linea}`);
for (const aviso of avisosDeArranque(configuracion)) console.warn(`[alivia/api] AVISO: ${aviso}`);

// El pool se crea una vez. Ningún otro fichero puede pedir una conexión: el
// pool no se exporta (decisión 1 de docs/arquitectura.md).
iniciarAcceso({
  url: configuracion.urlBaseDeDatos,
  fechaReferencia: configuracion.fechaReferencia,
});

const servidor = crearServidor(configuracion).listen(configuracion.puerto, () => {
  console.log(`[alivia/api] escuchando en http://localhost:${configuracion.puerto}`);
});

// Un puerto ocupado es el primer tropiezo en una máquina nueva. Que diga qué
// pasa y qué hacer, no una traza de veinte líneas sobre 'error' no manejado.
servidor.on("error", (error: NodeJS.ErrnoException) => {
  if (error.code === "EADDRINUSE") {
    console.error(
      `[alivia/api] el puerto ${configuracion.puerto} está ocupado.\n` +
        `             Poner otro en el .env:  PUERTO=3005\n` +
        `             O parar lo que lo tenga cogido.`,
    );
    process.exit(1);
  }
  console.error(`[alivia/api] no se pudo escuchar en ${configuracion.puerto}: ${error.message}`);
  process.exit(1);
});

for (const senal of ["SIGTERM", "SIGINT"] as const) {
  process.on(senal, () => {
    console.log(`[alivia/api] ${senal}: cerrando`);
    servidor.close(() => {
      // Sin esto, las conexiones abiertas quedan colgando en la base hasta que
      // el motor las expira, y un reinicio rápido agota el límite.
      void cerrarAcceso().then(() => process.exit(0));
    });
  });
}
