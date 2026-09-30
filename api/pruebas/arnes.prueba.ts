// Pruebas del arnés. Si esto falla, nada de lo que diga el resto es de fiar.

import { strict as assert } from "node:assert";
import { after, before, describe, test } from "node:test";
import { conUsuario, sinContextoDeUsuario } from "../src/datos/contexto.js";
import {
  abrirBaseEfimera,
  type BaseEfimera,
  comoPropietario,
  usuariosDePrueba,
} from "./arnes/base.js";
import { nombreDeLaBaseDeTrabajo, PREFIJO_EFIMERA } from "./arnes/nombres.js";

describe("el arnés de pruebas", () => {
  let base: BaseEfimera;

  before(async () => {
    base = await abrirBaseEfimera();
  });
  after(async () => {
    await base.cerrar();
  });

  test("corre contra una base propia, no contra la de trabajo", () => {
    assert.notEqual(base.nombre, nombreDeLaBaseDeTrabajo());
    assert.ok(
      base.nombre.startsWith(PREFIJO_EFIMERA),
      `la base «${base.nombre}» no lleva el prefijo del arnés`,
    );
  });

  test("la base efímera trae el esquema entero", async () => {
    const tablas = await sinContextoDeUsuario(async (tx) =>
      tx.consultar<{ nombre: string }>(
        "SELECT table_name AS nombre FROM information_schema.tables WHERE table_schema = 'public'",
      ),
    );
    const nombres = tablas.map((t) => t.nombre);
    for (const esperada of ["usuario", "obligacion_usuario", "ocurrencia", "aviso", "modulo"]) {
      assert.ok(nombres.includes(esperada), `falta la tabla ${esperada}`);
    }
  });

  test("las migraciones quedaron registradas, no adivinadas", async () => {
    // Se lee como fixture: app.migracion_aplicada no está concedida a
    // alivia_app, y no debería estarlo. El servidor no tiene nada que hacer
    // leyendo el control de migraciones.
    const [fila] = await comoPropietario<{ cuantas: string }>(
      base,
      "SELECT count(*)::text AS cuantas FROM app.migracion_aplicada",
    );
    // Trece migraciones y diez semillas, y crecerá. Lo que importa es que se
    // aplicaron y se anotaron, no el número exacto.
    assert.ok(Number(fila?.cuantas) >= 23, `solo se aplicaron ${fila?.cuantas} ficheros`);
  });

  test("el catálogo está sembrado y alivia_app lo puede leer", async () => {
    // El catálogo es información compartida, no datos de nadie: la aplicación
    // sí lo lee, y por eso esta sí va por conUsuario/sinContexto.
    const [fila] = await sinContextoDeUsuario(async (tx) =>
      tx.consultar<{ cuantas: string }>(
        "SELECT count(*)::text AS cuantas FROM obligacion_catalogo",
      ),
    );
    assert.ok(Number(fila?.cuantas) >= 40, `el catálogo trae ${fila?.cuantas} entradas`);
  });

  test("los dos usuarios de prueba están sembrados", async () => {
    const { ana, beto } = await usuariosDePrueba(base);
    assert.notEqual(ana, beto);
  });

  test("sin contexto, alivia_app no ve NINGÚN usuario", async () => {
    // Esto es RLS funcionando, no un defecto: `usuario` filtra por
    // app.usuario_actual(), que sin contexto es NULL, y una comparación con NULL
    // no es verdadera. Falla cerrado. Que devuelva cero filas es la garantía.
    const filas = await sinContextoDeUsuario(async (tx) =>
      tx.consultar<{ correo: string }>("SELECT correo FROM usuario"),
    );
    assert.deepEqual(filas, []);
  });

  test("las pruebas corren con alivia_app, que SÍ está sujeto a RLS", async () => {
    const [fila] = await sinContextoDeUsuario(async (tx) =>
      tx.consultar<{ rol: string }>("SELECT current_user AS rol"),
    );
    // Con el propietario todas las pruebas de aislamiento pasarían sin
    // comprobar nada, porque el propietario ignora las políticas por completo.
    assert.equal(fila?.rol, "alivia_app");
  });

  test("lo que esta prueba escribe no lo ve ninguna otra", async () => {
    const { ana: id } = await usuariosDePrueba(base);

    const marca = `SOLO EN ESTA BASE ${base.nombre}`;
    await conUsuario(id, async (tx) => {
      await tx.consultar(
        `INSERT INTO obligacion_usuario
           (usuario_id, modulo_codigo, origen, nombre, tipo_exigibilidad, fecha_base)
         VALUES ($1, 'vehiculo', 'libre', $2, 'recomendada', DATE '2026-06-01')`,
        [id, marca],
      );
    });

    const [cuenta] = await conUsuario(id, async (tx) =>
      tx.consultar<{ cuantas: string }>(
        "SELECT count(*)::text AS cuantas FROM obligacion_usuario WHERE nombre = $1",
        [marca],
      ),
    );
    assert.equal(cuenta?.cuantas, "1");
    // La fila queda. Nadie la limpia: la base entera se borra al terminar el
    // fichero, que es justo por lo que no hace falta limpiar nada.
  });
});
