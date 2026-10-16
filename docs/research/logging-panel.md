# Logs de universal-logger sin romper el panel

> Spike del 15/10/2026 (issue #9, épica #3). Responde a la pregunta abierta «Logs y panel» de la [spec](../specs/autonomous-orchestrator.md). Todo se corrió en una terminal real (pty) en una carpeta temporal bajo `/tmp`, sin GitHub ni agentes. Los scripts son descartables: [`spike-logging-panel/panel.mjs`](spike-logging-panel/panel.mjs) y [`spike-logging-panel/run-pty.py`](spike-logging-panel/run-pty.py).

## Resultado

| Criterio de la Definition of done | Resultado |
|---|---|
| 1. `docs/research/logging-panel.md` con la versión probada | pasa (`@ashulab/universal-logger` **0.1.1**) |
| 2. Script descartable: INFO, info/warn/error a archivo, panel ANSI sin líneas mezcladas | pasa |
| 3. Con `SIGINT` el archivo tiene todos los logs emitidos | pasa |
| 4. `logError` con `Error` conserva el stack en el archivo | pasa |
| 5. Mecanismo de integración concreto con snippet | pasa (ver [Recomendación](#recomendación)); la biblioteca no necesita cambios |

Conclusión: la biblioteca no necesita un transport. Llama a `console.info/warn/error/log` en cada llamada (lo leí en `dist/index.js`, no hay estado capturado al importar), así que reemplazar esos métodos por escrituras síncronas a un archivo alcanza. Con eso el panel es el único que escribe en la terminal.

## Entorno

- macOS 27.0, Node v26.12.0 (nvm), pnpm 12.11.2, Python 3.9.6 (solo para el pty).
- `@ashulab/universal-logger` **0.1.1** (la última publicada, `pnpm view @ashulab/universal-logger version` → `0.1.1`; es la del `pnpm-lock.yaml`).
- Pty real: `run-pty.py` hace `pty.fork()`, guarda los bytes crudos que recibe la terminal y a los N segundos escribe `0x03` (lo que manda Ctrl+C), por lo que el `SIGINT` lo genera la disciplina de línea de la terminal, no un `kill`.

## Qué hace la biblioteca (leído en el código)

- Escribe con `console.log` (debug), `console.info`, `console.warn` y `console.error`. No hay transport ni destino configurable.
- `configureUniversalLogger({ minLevel })` filtra; el default sale de `LOG_LEVEL` o de `NODE_ENV`.
- Con `NODE_ENV=development` emite `console.x(message, objeto)` (varias líneas, vía `util.inspect`); sin eso, una línea JSON `{message, timestamp, ...context}`. **El nivel no aparece en el JSON**: solo se sabe por el método de `console` usado.
- `logError(msg, err)` pone `error` (mensaje) y `stack` (string) en el contexto.
- `createScopedLogger(...).info/.warn` con un `Error` guarda solo `error: err.message`: **pierde el stack**. `scoped.error` sí lo conserva (llama a `logError`).

## Experimento

`panel.mjs` configura INFO, reemplaza los métodos de `console` por `writeSync(fd, "[nivel] " + util.format(...))` sobre un fd abierto en modo append, emite un log cada 37 ms (info, warn, `scoped.warn` con `Error` y `logError` con `Error`, más un `logDebug` que no debe aparecer) y redibuja un panel de 4 líneas cada 50 ms con `ESC[4A` + `ESC[2K`. Los marcadores de log (`LOGLINE`, `DEBUGLINE`) nunca están en el texto del panel.

Comandos (desde una carpeta temporal `$T`, `S` = carpeta del spike):

```sh
python3 -I $S/run-pty.py 3 $T/a.tty node $S/panel.mjs --log=$T/a.log --redirect=yes --sigint=handler --count-file=$T/a.count
```

### A. Redirigido, `SIGINT` con handler (criterios 2 y 3)

```
exit status 33280 exited 130
tty bytes:     6011; LOGLINE in tty: 0; seq= in tty: 0; DEBUGLINE in file: 0
emitted(count-file)=80  lines in file=      80  nonmatching lines=0
seq gaps:
last seq 79
```

- La terminal recibió 6011 bytes y ninguno contiene un log (`grep -c LOGLINE a.tty` → 0). Cola de lo que ve la terminal, con el `^C` y el cursor restaurado:

  ```
  ^[[2Klogs emitidos: 79
  ^[[2K===================
  ^C^[[?25h
  ```
- Después de `Ctrl+C`, el archivo tiene 80 líneas = 79 logs numerados + `shutdown` = el contador de emitidos que el handler escribió (80), sin huecos en `seq` y sin líneas fuera del formato `[nivel] ...`.
- `logDebug` con `minLevel` INFO no llegó al archivo (`DEBUGLINE in file: 0`).
- Muestra del archivo:

  ```
  [info] {"message":"LOGLINE seq=1 info","timestamp":"2026-10-15T23:54:35.471Z","epic":"x"}
  [warn] {"message":"LOGLINE seq=3 warn","timestamp":"2026-10-15T23:54:35.547Z","epic":"x"}
  [info] {"message":"LOGLINE shutdown","timestamp":"2026-10-15T23:54:38.430Z"}
  ```

### Control: sin redirigir (`--redirect=no`)

```
LOGLINE in tty: 53
^[[?25l{"message":"LOGLINE seq=1 info","timestamp":"2026-10-15T23:54:45.239Z","epic":"x"}
^[[2K== carrier panel ==
...
^[[2K===================
{"message":"LOGLINE seq=2 info",...}
^[[4A^[[2K== carrier panel ==
```

Sin la redirección los logs se intercalan con el panel (53 apariciones en 2 s), que es el problema que hay que evitar. El resto del experimento es válido porque el panel solo cambia en eso.

### B. `SIGINT` sin handler (el proceso muere por la señal)

```
exit status 2 signaled 2
last panel count=77; file lines=      78; LOGLINE in tty=0
last seq 78
```

Sin handler el proceso muere por la señal 2 y igual no se pierde nada: el archivo llega a 78 (≥ 77, el último contador dibujado), sin huecos. Es la ventaja de `writeSync`: cuando la llamada vuelve el dato ya está en el kernel. **No probé** un `WriteStream` asíncrono; es la razón teórica para no usarlo (lo pendiente en su buffer se pierde con `process.exit`).

### C. `logError` con `Error` conserva el stack (criterio 4)

Salida JSON (default, sin `NODE_ENV=development`), `seq=5`:

```
[error] {"message":"LOGLINE seq=5 error","timestamp":"2026-10-15T23:54:35.624Z","epic":"x","error":"kaboom-5","stack":"Error: kaboom-5\n    at Timeout.emit [as _onTimeout] (file:///.../docs/research/spike-logging-panel/panel.mjs:31:55)\n    at listOnTimeout (node:internal/timers:685:17)\n    at process.processTimers (node:internal/timers:618:7)"}
```

El stack completo está en el campo `stack`, en una sola línea (con `\n` escapados), así que el archivo sigue siendo una línea por log. Con `NODE_ENV=development` el mismo stack sale en varias líneas (objeto formateado por `util.inspect`):

```
[error] LOGLINE seq=5 error {
  timestamp: '2026-10-15T23:54:55.725Z',
  epic: 'x',
  error: 'kaboom-5',
  stack: 'Error: kaboom-5\n' +
    '    at Timeout.emit [as _onTimeout] (file:///...panel.mjs:31:55)\n' +
    ...
}
```

También sin interferir con el panel (`LOGLINE in tty: 0`), pero rompe «una línea por log» (40 líneas de continuación en 1 s). Por eso la app debe correr con `NODE_ENV` distinto de `development`, o fijarlo antes de importar la biblioteca.

Con `scoped.warn(msg, new Error(...))` el archivo solo trae `"error":"scoped-4"`, sin stack (ver arriba). Para errores con stack usar `logError` o `scoped.error`.

## Recomendación

Un módulo `logging/` que, al arrancar y antes de dibujar el panel, abre `orchestrator/logs/orchestrator.log` en append y reemplaza los métodos de `console`. Todo `console.*` del proceso (incluido el de dependencias) queda fuera de la terminal; el panel escribe a `fd 1` sin pasar por `console`.

```ts
import { openSync, writeSync } from 'node:fs';
import { format } from 'node:util';
import { LogLevel, configureUniversalLogger } from '@ashulab/universal-logger';

export function installFileLogging(logFile: string, minLevel = LogLevel.INFO): void {
  process.env.NODE_ENV ??= 'production'; // 'development' emite varias líneas por log
  const fd = openSync(logFile, 'a');
  for (const level of ['log', 'info', 'warn', 'error', 'debug'] as const) {
    // el nivel no está en el JSON de la biblioteca: lo agrega el método de console usado
    console[level] = (...args: unknown[]) => writeSync(fd, `[${level}] ${format(...args)}\n`);
  }
  configureUniversalLogger({ enabled: true, minLevel });
}
```

Es la misma lógica que corrió el spike (en `.mjs`), no se compiló ni se probó como TypeScript. Decisiones:

- **`writeSync` sobre un fd en append**: es lo que hace que `SIGINT` (con o sin handler) no pierda nada y que no haga falta vaciar buffers al cerrar. Costo: bloquea el hilo durante cada escritura; para el volumen de logs del orquestador (eventos de etapa, no el stream de los agentes) es irrelevante. Si algún día se mide un problema, pasar a un buffer con vaciado en `SIGINT`.
- **`console` y no `process.stdout.write`**: es el punto de extensión que la biblioteca ya usa en cada llamada; interceptar `process.stdout` también atraparía al panel.
- **Contexto de repo, épica, ejecución, rol y etapa**: la biblioteca no tiene contexto asíncrono; se pasa en el objeto `context` o en el scope (`createScopedLogger('epic-12/author')`). Esa capa va sobre este módulo y no se probó aquí.
- **Fuera de alcance del módulo**: la salida completa de cada agente (`executions/<id>/`) la escribe el runner directo a sus archivos, no pasa por la biblioteca; la retención de 30 días es otra pieza (historia 24).
- **No probado**: excepciones no capturadas y escrituras nativas a `stderr` (no pasan por `console`); el módulo de arranque debería enganchar `uncaughtException`, registrar y restaurar el cursor antes de salir.

## Impacto en la spec y los ADR

Ningún resultado contradice la spec ni los ADR (ninguno trata logging). Confirma lo que dice la spec («escribe por consola y no ofrece un transport general», «reutilizar la biblioteca») y agrega dos restricciones de integración que quedaron anotadas en la spec: `NODE_ENV` no puede ser `development` y el nivel hay que agregarlo desde el método de `console`.

## Limitaciones

- Un solo run por caso, 2 a 3 segundos cada uno, macOS y Node 26.12 únicamente.
- `Ctrl+C` se probó en un pty propio, no en Terminal.app/iTerm; no se probó redimensionar ni una terminal que sea más angosta que el panel.
- El panel es de juguete (4 líneas, redibujado in situ); no prueba el panel real ni el modo sin terminal interactiva.
- Carga baja (unos 27 logs/s); no se midió el costo de las escrituras síncronas.
