# Claude y Codex en modo headless

> Spike del 15/10/2026 (issue #5, épica #3). Responde a la pregunta abierta «Claude y Codex headless» de la [spec](../specs/autonomous-orchestrator.md). Todo se corrió en un repo descartable en `/tmp`, sin remoto, sin credenciales de repos reales y con prompts mínimos. No es una prueba de aislamiento: eso es el spike de contenedores ([ADR 0003](../adr/0003-agentes-en-contenedor.md)).

## Resultado

| Criterio de la Definition of done | Resultado |
|---|---|
| 1. Versiones y comando exacto no interactivo que invoca un skill (Claude y Codex) | pasa |
| 2. Id de sesión, archivos, comando de retomar y evidencia de que recuerda | pasa |
| 3. JSON escrito en una ruta dada y válido contra `CallerResult` | pasa |
| 4. Ejecución cortada con `kill`: qué sobrevive, si retoma, procesos hijos (`ps`) | pasa |
| 5. Delegación en subagentes o hijos y huérfanos al matar al padre | pasa |
| 6. Cada criterio como pasa/falla, opciones y spec/ADR | pasa (ver [Impacto](#impacto-en-la-spec-y-los-adr)) |

Los dos CLI sirven como base del runner. Lo que el runner no puede dar por hecho: matar al CLI no siempre mata a sus hijos (tabla del punto 4 y 5), así que la detención tiene que apoyarse en el contenedor o en matar el grupo de procesos de cada comando, no en la señal al CLI.

## Entorno

- macOS (Darwin 27.0.0), Node v25.6.0, pnpm 12.4.1, `zod` 4.6.7 solo en el script de validación.
- Claude Code **2.1.301**, autenticado con la cuenta claude.ai del operador. Modelo usado: alias `haiku` (`claude-haiku-5-5`). `CLAUDE_CONFIG_DIR=/Users/vemec/.claude-ashu-lab`.
- Codex CLI **0.153.4**, autenticado con ChatGPT. Modelo: el default de `~/.codex/config.toml` (`gpt-5.6-terra`).
- Repo descartable: `git init` en `/tmp/carrier-spike5.XXXXXX/repo` con un único commit, sin remoto. El skill de prueba es un `SKILL.md` en `.claude/skills/spike-skill/` y en `.agents/skills/spike-skill/` que escribe `skill-ran.txt` con `SKILL-OK <argumentos>`. No se corrió `ship` ni ningún skill de Solve real (necesitaría GitHub).
- Trampa de entorno: en esta máquina `claude` y `codex` del `PATH` resuelven a wrappers de Superset (`~/.superset/bin/`). El de Codex es un script bash que agrega `--enable hooks --dangerously-bypass-hook-trust` (de ahí el aviso `--dangerously-bypass-hook-trust is enabled` en el JSONL) e intercepta señales. Los experimentos de kill usan el binario real `~/.local/bin/codex`. El runner debe invocar el binario real, no un wrapper.
- Trampa de configuración: los CLI cargan la configuración del usuario (hooks de sesión de Claude, plugins de Codex como Slack o Calendar, `CLAUDE.md`). Un runner debe aislar `CLAUDE_CONFIG_DIR` y `CODEX_HOME` por ejecución; esto no se probó aquí.

## 1. Comando no interactivo que invoca un skill

Claude (el skill se invoca con `/nombre argumentos` como prompt):

```sh
cd <repo> && claude -p "/spike-skill alpha-42" --permission-mode bypassPermissions --output-format json --model haiku </dev/null
```

Salida observada (recortada): `"is_error":false`, `"result":"DONE"`, `"session_id":"91b46ab3-3e4f-4e4d-b258-3ce035154567"`, `"terminal_reason":"completed"`, `exit=0`, y `skill-ran.txt` con `SKILL-OK alpha-42`.

Codex (el skill se invoca con `$nombre argumentos`; descubre skills en `.agents/skills/` del repo):

```sh
cd <repo> && codex exec '$spike-skill alpha-42' --sandbox workspace-write --json </dev/null
```

Salida observada: `exit=0`, eventos `thread.started` (`thread_id` `01a141eb-6773-7263-b951-dd09037967bd`), un `agent_message` «Uso `spike-skill` para crear el marcador solicitado.», un `file_change` sobre `skill-ran.txt`, `agent_message` `DONE` y `turn.completed`. `skill-ran.txt` contiene `SKILL-OK alpha-42`.

Notas para el adaptador:

- Codex, si hay stdin que no es una terminal, imprime `Reading additional input from stdin...` y espera EOF; con `</dev/null` no se cuelga. Hacer lo mismo con Claude.
- `claude -p` no pregunta permisos con `--permission-mode bypassPermissions` (equivale a `--dangerously-skip-permissions`; es aceptable solo dentro del contenedor del ADR 0003). Codex con `--sandbox workspace-write` escribe dentro del repo sin preguntar; fuera necesita `--add-dir <ruta>` (punto 3).
- Salida máquina-legible: Claude `--output-format json` (un objeto al final) o `stream-json --verbose` (un evento por línea); Codex `--json` (JSONL de eventos). Ambos CLI aceptan además un esquema de salida estructurada (`claude --json-schema`, `codex exec --output-schema`); no se probó.
- Solo se verificaron las versiones `2.1.301` y `0.153.4`; los flags pueden cambiar entre versiones, conviene fijarlas.

## 2. Sesión: id, archivos y retomar

| | Claude | Codex |
|---|---|---|
| Cómo se obtiene el id | campo `session_id` del resultado (`--output-format json`/`stream-json`); también se puede fijar de antemano con `--session-id <uuid>` | primer evento del JSONL: `{"type":"thread.started","thread_id":"..."}` |
| Dónde vive | `$CLAUDE_CONFIG_DIR/projects/<cwd con / y . como ->/<id>.jsonl` (p. ej. `~/.claude-ashu-lab/projects/-private-tmp-carrier-spike5-4J4kU3-repo/0b8e5745-6b93-4d7a-8a8b-ea52dce13c29.jsonl`) | `$CODEX_HOME/sessions/AAAA/MM/DD/rollout-<fecha>-<id>.jsonl` (p. ej. `~/.codex/sessions/2026/10/15/rollout-2026-10-15T20-35-49-01a141ec-06ab-7c00-80b1-aa33e00f2ae9.jsonl`) |
| Retomar | `claude -p "<prompt>" --resume <id> ...` | `codex exec resume <id> "<prompt>" ...` |

Evidencia Claude (la sesión se creó diciendo un código y se retomó en un proceso nuevo):

```
$ claude -p "Remember the codeword TANGERINE-93. Reply only OK." --permission-mode bypassPermissions --output-format json --model haiku
{"session_id":"0b8e5745-6b93-4d7a-8a8b-ea52dce13c29","result":"OK","is_error":false}
$ claude -p "What was the codeword? Reply with only the codeword." --resume 0b8e5745-6b93-4d7a-8a8b-ea52dce13c29 --permission-mode bypassPermissions --output-format json --model haiku
{"session_id":"0b8e5745-6b93-4d7a-8a8b-ea52dce13c29","result":"TANGERINE-93","is_error":false}
```

Evidencia Codex:

```
$ codex exec "Remember the codeword TANGERINE-93. Reply only OK." --sandbox workspace-write --json
{"type":"thread.started","thread_id":"01a141ec-06ab-7c00-80b1-aa33e00f2ae9"} ... agent_message "OK"
$ codex exec resume 01a141ec-06ab-7c00-80b1-aa33e00f2ae9 "What was the codeword? Reply with only the codeword." -c 'sandbox_mode="workspace-write"' --json
{"type":"thread.started","thread_id":"01a141ec-06ab-7c00-80b1-aa33e00f2ae9"} ... agent_message "TANGERINE-93"
```

Detalles que importan al adaptador:

- `codex exec resume` no acepta `--sandbox` ni `-C`/`--cd`: el sandbox se pasa con `-c 'sandbox_mode="..."'` y el cwd es el del proceso. La retomada conserva el mismo `thread_id`.
- Claude conserva el mismo `session_id` al retomar. Retomar desde otra carpeta (`cd <otra> && claude -p ping --resume <id>`) también funcionó: el id se encuentra sin importar el cwd y el archivo original sigue siendo el de la carpeta de origen, así que no hace falta preservar el cwd exacto, pero conviene montar el directorio de sesiones persistente (ADR 0003).
- Cada ejecución headless de Claude con `-p` crea un archivo de sesión nuevo salvo que se use `--resume`; el runner debe guardar el id de cada ejecución.

## 3. JSON del caller validado con `CallerResult`

El prompt pide escribir en una ruta fuera del repo (`/tmp/.../out/<agente>-result.json`) un `completed` con `pr.headSha` real (`git rev-parse HEAD`). Para que Codex pueda escribir fuera del workspace se agrega `--add-dir <carpeta>`; Claude con `--add-dir` también.

```sh
claude -p "<prompt con OUTPATH>" --permission-mode bypassPermissions --add-dir <out> --output-format json --model haiku </dev/null
codex exec "<prompt con OUTPATH>" --sandbox workspace-write --add-dir <out> --json </dev/null
```

Validador descartable (copia de `CallerResult` de la spec, ejecutado con `node validate.mjs <archivo>` en una carpeta aparte con `zod` instalado):

```js
import { z } from 'zod';
import { readFileSync } from 'node:fs';
const Sha = z.string().regex(/^[0-9a-f]{40}$/);
const Pr = z.object({ number: z.number().int().positive(), headSha: Sha });
const Common = {
  executionId: z.string().min(1),
  repo: z.string().regex(/^[\w.-]+\/[\w.-]+$/),
  epic: z.number().int().positive(),
  stage: z.enum(['ship', 'review', 'fix']),
  summary: z.string().min(1),
};
export const CallerResult = z.discriminatedUnion('outcome', [
  z.object({ ...Common, outcome: z.literal('completed'), pr: Pr,
    verification: z.object({ ci: z.enum(['passed', 'absent']), evidence: z.string().min(1) }) }),
  z.object({ ...Common, outcome: z.literal('changes_requested'), stage: z.literal('review'), pr: Pr,
    blockers: z.array(z.object({ title: z.string().min(1), url: z.string().url().optional() })).min(1) }),
  z.object({ ...Common, outcome: z.literal('needs_human'), reason: z.string().min(1) }),
]);
const r = CallerResult.safeParse(JSON.parse(readFileSync(process.argv[2], 'utf8')));
console.log(r.success ? 'VALID outcome=' + r.data.outcome : 'INVALID ' + JSON.stringify(r.error.issues));
process.exit(r.success ? 0 : 1);
```

Resultados observados:

```
claude-result.json  ->  VALID outcome=completed
codex-result.json   ->  VALID outcome=completed
control negativo (epic 0, headSha "abc") -> INVALID [... "path":["epic"] ... "path":["pr","headSha"] ...]
```

El JSON de Claude salió formateado con `summary` y `evidence` redactados por el modelo; el de Codex salió en una línea. Con ambos, el `executionId`, `repo`, `epic` y `stage` repiten lo que el prompt pidió. Ninguno inventó campos. Es un solo intento por agente con un prompt corto: no mide la tasa de JSON inválido, que el spec ya cubre con reintento por fallo técnico.

## 4. Ejecución cortada con `kill`

Tarea: recordar un código (`KUMQUAT-58`), crear `step1.txt`, ejecutar en foreground `python3 -c 'import time; time.sleep(31x)'` y crear `step3.txt`. A los pocos segundos de empezar el sleep se manda la señal al proceso del CLI (no al wrapper) y se mira qué queda con `ps`. Luego se retoma la sesión pidiendo saltar el sleep y completar el paso 3.

Árbol de procesos antes de matar (Claude): `claude -p` → `codegraph-mcp` (servidor MCP del usuario) y `/bin/zsh -c ...` (la tool Bash) → `Python -c ...sleep`. Codex: `codex exec` → `node_repl` (x2), `codex-code-mode-host` y `Python -c ...sleep` (cada uno con su propio pgid).

| Agente | Señal | Archivos y sesión | Hijos tras `ps` | Retomada |
|---|---|---|---|---|
| Claude | `SIGTERM` | `step1.txt` quedó; el `.jsonl` de la sesión (`f485db74-...`) quedó en disco; el stream mostró la tool interrumpida con `Exit code 137`; exit del CLI 143 | ninguno: shell, `python` y `codegraph-mcp` terminaron | `--resume`: recordó `KUMQUAT-58`, vio `step1.txt`, creó `step3.txt` |
| Claude | `SIGKILL` | igual (`step1.txt`, sesión `4c9033c2-...`); exit 137 | **huérfanos**: `/bin/zsh -c ...` (pid 92565, ppid 1) y `Python -c ...sleep` (pid 92566); `codegraph-mcp` sí terminó | recordó `KUMQUAT-58`, creó `step3.txt` (los huérfanos se mataron antes) |
| Codex | `SIGTERM` al CLI real | `step1.txt` y el rollout (`01a141f0-f9c7-7f81-876e-a7dae35e24de`) quedaron; exit 143 | **huérfano**: `Python -c ...sleep` (pid 2267, ppid 1); `codex`, `node_repl` y `codex-code-mode-host` terminaron | `exec resume`: recordó `KUMQUAT-58`, creó `step3.txt` |
| Codex | `SIGKILL` | igual (`01a141f3-6884-7190-a479-7384db9b72ad`); exit 137 | **huérfano**: `Python -c ...sleep` (pid 12705, ppid 1) | recordó `KUMQUAT-58`, creó `step3.txt` |

Salida de `ps` ilustrativa, después de `kill -KILL` del CLI de Claude:

```
92565     1 92565 01:33 /bin/zsh -c source /Users/vemec/.claude-ashu-lab/shell-snapshots/snapshot-zsh-...sh ...
92566 92565 92565 01:33 /Applications/Xcode.app/.../Python -c import time; time.sleep(312)
```

y después de `kill -TERM` del CLI de Codex:

```
 2267     1  2267       02:11 /Applications/Xcode.app/.../Python -c import time; time.sleep(313)
```

Conclusiones:

- Lo que sobrevive siempre: los archivos escritos antes de cortar y el archivo de sesión (se escribe incrementalmente). Retomar funciona con ambos CLI, con cualquier señal.
- Claude con `SIGTERM` limpia a sus hijos; con `SIGKILL` no (nadie puede). Codex no limpia el proceso del comando ni con `SIGTERM`: quedó huérfano en ambos casos.
- Los hijos están en su propio grupo de procesos, así que matar el grupo del CLI no alcanza; se limpiaron con `kill -TERM <pid>` o `kill -TERM -<pgid>` del huérfano. En el runner, esto lo resuelve el contenedor (ADR 0003: «matar el contenedor alcanza a los procesos hijos»). Sin contenedor habría que registrar los descendientes antes de matar.
- Mi primer intento de matar a Codex fue sobre el wrapper bash de Superset: el `SIGTERM` no lo terminó (tiene `trap`) y el CLI real siguió corriendo. Matar al wrapper no detiene a Codex; confirmar el pid real.
- Mi primer intento con Claude y `sleep 311` mostró que Claude 2.1.301 bloquea un `sleep` suelto en foreground y lo manda a background; por eso los experimentos usan `python3 -c 'import time; time.sleep(N)'`.
- Al retomar tras un corte hay que decirle al agente que verifique el estado real (la sesión no registra el efecto real de la tool interrumpida), tal como ya prevé la spec.

## 5. Delegación en subagentes o procesos hijos

Prompt: «lanzá UN subagente que ejecute en foreground `python3 -c 'import time; time.sleep(N)'` y esperalo». Claude lo hizo con la tool `Agent` (eventos `tool_use` `Agent` y luego `Bash` del subagente); Codex con una `collab_tool_call` (`codex features list`: `multi_agent` está `stable` y activa). En los dos, el sleep corrió en un proceso nieto del CLI.

| Agente | Señal al padre | Huérfanos |
|---|---|---|
| Claude (subagente `Agent`) | `SIGTERM` | ninguno (la shell y el `python` terminaron con el CLI) |
| Claude (subagente `Agent`) | `SIGKILL` | `/bin/zsh -c ...` (pid 20914, ppid 1) y `Python -c ...sleep(317)` (pid 20915) |
| Codex (subagente) | `SIGTERM` | `Python -c ...sleep(318)` (pid 26052, ppid 1) |
| Codex (subagente) | `SIGKILL` | `Python -c ...sleep(319)` (pid 28408, ppid 1) |

Los subagentes no son procesos propios: viven dentro del CLI padre; lo que queda huérfano son los comandos que ejecutaron. Es el mismo comportamiento del punto 4. Se usó un subagente simple, no `ship` real (que despacha hasta tres por batch): el mecanismo de hijos es el mismo, pero la cantidad de huérfanos crecería con el paralelismo.

Todos los huérfanos se documentaron con `ps` y se mataron al terminar; al final no quedó ningún proceso de los experimentos, y se borraron la carpeta temporal y los archivos de sesión de los experimentos (por eso las rutas de ejemplo ya no existen).

## Opciones y recomendación

No hay criterio que falle, pero sí un riesgo operativo: los huérfanos. Opciones para la detención del runner:

1. **Contenedor por ejecución, matarlo al detener (ADR 0003, ya decidido).** Cubre todos los casos de arriba sin código extra. Lo que sigue pendiente es probarlo en el spike de contenedores.
2. Registrar el árbol de procesos (`pgrep -P` recursivo) antes de enviar `SIGTERM` al CLI y matar los restantes después de un plazo. Sirve de red de seguridad en el host y para tests, no reemplaza al contenedor.
3. Lanzar cada CLI en su propio grupo de sesión (`setsid`) para poder matar por grupo. No alcanza: la shell del comando abre otro grupo (se vio `pgid` distinto) y no hay `setsid` nativo en macOS.

Recomendación: mantener la opción 1 y hacer que el runner mande primero `SIGTERM` (Claude limpia sus hijos) y deje la limpieza final al contenedor.

## Impacto en la spec y los ADR

Ningún resultado contradice la spec ni el ADR 0003. Lo observado respalda el ADR: matar el CLI no alcanza a los procesos hijos en el host (Codex ni con `SIGTERM`), así que el supuesto «matar el contenedor termina todos los procesos» es lo que el spike de contenedores debe confirmar. La spec recibió un párrafo breve en la sección de validaciones que enlaza este documento y lista las trampas para el runner (binario real, `</dev/null`, `--add-dir`, `exec resume` sin `--sandbox`).

## Limitaciones

- Skill de juguete, no `ship`: no se verificó que `ship` real (con `gh`, subagentes en paralelo y sesiones de horas) funcione sin interacción.
- Un solo intento por caso, sin medir variabilidad entre corridas; Claude se probó con `haiku`, no con el modelo que usaría el autor real.
- No se probó `--bare`, `--ignore-user-config` ni `--no-session-persistence`, ni el aislamiento de `CLAUDE_CONFIG_DIR`/`CODEX_HOME`, ni límites (`--max-budget-usd`, `--max-turns`).
- macOS únicamente; el comportamiento de señales y grupos de procesos en el contenedor Linux es del spike de contenedores.
