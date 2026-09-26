# `api/src/datos/`

**El único sitio del proyecto que conoce el pool de conexiones.** Decisión 1 de `docs/arquitectura.md` y regla 1 de `CLAUDE.md`.

| Fichero | Qué es |
|---|---|
| `contexto.ts` | El pool, el tipo `Tx` y `conUsuario()` |
| `comprobar.ts` | `npm run datos` — ejercita el contrato contra la base real |

## Cómo se usa

```ts
const obligaciones = await conUsuario(usuarioId, async (tx) => {
  return tx.consultar<Obligacion>('SELECT * FROM obligacion_usuario ORDER BY fecha_base');
});
```

Un repositorio recibe el `tx` como primer parámetro y no lo pide: `listarObligaciones(tx, filtros)`. La transacción la abre el caso de uso, no el repositorio.

## Por qué está hecho así

`conUsuario()` abre la transacción, fija `alivia.usuario_id` y `alivia.fecha_referencia` **dentro** de ella, y cierra. `set_config(…, true)` es local a la transacción: si se fijara fuera, se perdería entre sentencia y sentencia y las consultas devolverían **cero filas sin dar ningún error**. No es hipotético — la primera versión de `db/pruebas/rls.sql` fallaba exactamente así.

**«Imposible por construcción» son dos mitades, y hacen falta las dos:**

1. **El tipo.** `Tx` lleva una marca con un símbolo que no sale de `contexto.ts`, así que el compilador rechaza fabricar uno. Comprobado: `verificar-datos.py` escribe un fichero que lo intenta y exige que `tsc` falle.
2. **El pool.** El tipo se puede forzar con una conversión, pero una **conexión** no: importar `pg` fuera de esta carpeta lo prohíbe `verificar-arquitectura.py`. Un `Tx` falsificado no llega a la base de datos.

## Cuatro decisiones que no son obvias

**El contexto se pasa como parámetro, no por `AsyncLocalStorage`.** Es más verboso y se prefiere por eso: un contexto implícito se pierde con un `await` mal colocado, en silencio, y vuelve a devolver cero filas. Sería reconstruir en TypeScript el problema que ya se resolvió en SQL.

**`AsyncLocalStorage` sí se usa, pero solo para detectar anidamiento.** Anidar `conUsuario()` abriría una segunda transacción en otra conexión, y lo que pasara en una no sería atómico con la otra — justo lo contrario de lo que exige la tarea 11. Ahora lanza con un mensaje que dice qué hacer: pasar el `tx` que ya se tiene.

**Un `Tx` guardado no sirve después.** Si sobrevive a la transacción y alguien lo usa, la consulta correría en la siguiente transacción que tomara ese cliente del pool, **con el contexto de otro usuario**. El `Tx` se invalida al cerrar y lanza.

**`sinContextoDeUsuario()` se llama así para que dé reparo.** Existe para dos funciones `SECURITY DEFINER` del esquema que por definición corren antes de que haya sesión: `app.registrar_usuario()` y `app.credenciales_por_correo()`. Para cualquier otra cosa es un error.

## Fechas

`contexto.ts` registra el parseador del tipo `date` (OID 1082) para que vuelva como **cadena `AAAA-MM-DD`**. Sin eso, node-postgres lo convierte en un `Date` a medianoche local y a partir de ahí toda aritmética desfasa el día. Decisión 3.
