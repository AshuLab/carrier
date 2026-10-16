# Integración end-to-end con el repo de prueba (slice #33)

Fecha: 16/10/2026. Entorno: macOS, Node 26.12.0, pnpm, `agent-forge`, Claude Code (`~/.local/bin/claude`), Codex CLI, `gh` con login de Diego (solo para sembrar y contar). Repo de prueba: `AshuLab/carrier-sandbox` ([sandbox-repo.md](sandbox-repo.md)).

Resultado: los cinco escenarios de la Definition of done corrieron con Carrier (el CLI, como proceso), Claude, Codex, Forge y Solve reales. Se encontraron y arreglaron **dos bugs reales** de Carrier, más varios del arnés; queda un riesgo abierto menor (§4). La evidencia de cada escenario salió de corridas distintas, porque la primera pasada se cortó por un error del arnés y por el primer bug (§3); ver la trazabilidad en §2. No hay desvíos respecto de la spec.

## 1. Montaje

Código: `src/e2e/harness.ts` y `src/e2e/carrier.integration.test.ts`. Corre con `pnpm test:integration` y **se saltea sola** si faltan las variables, así que no corre en `pnpm test`. Tarda minutos por escenario y gasta plata.

| Variable | Valor usado | Para qué |
| --- | --- | --- |
| `CARRIER_E2E_REPO` | `AshuLab/carrier-sandbox` | repo descartable; el nombre debe terminar en `sandbox` (el arnés lo rechaza si no) |
| `CARRIER_E2E_AUTHOR_AGENT` | `artanis-agent` | agente de Forge del autor (también el orquestador) |
| `CARRIER_E2E_REVIEWER_AGENT` | `tassadar-agent` | agente de Forge del reviewer; tiene que ser otro |
| `CARRIER_E2E_AUTHOR` | `claude:sonnet` (default) | `<claude\|codex>:<modelo>` |
| `CARRIER_E2E_REVIEWER` | `codex:gpt-5.6-luna` (default) | idem |
| `CARRIER_E2E_SCENARIOS` | `a,b,c,d,e` (default) | cuáles escenarios correr |
| `CARRIER_E2E_SKILLS_DIR` | sin usar | copia `code-review` y `code-post` a `.agents/skills` del sandbox; ya están en su `main` |
| `CARRIER_E2E_KEEP` | opcional | no borrar la raíz temporal al terminar |

```sh
CARRIER_E2E_REPO=AshuLab/carrier-sandbox CARRIER_E2E_AUTHOR_AGENT=artanis-agent CARRIER_E2E_REVIEWER_AGENT=tassadar-agent \
  CARRIER_E2E_SCENARIOS=c pnpm test:integration
```

Antes de correr: ninguna épica del sandbox con `solve:epic:ready` (el arnés se detiene si hay alguna, porque Carrier la importaría). Perfiles: `author` = Forge `artanis-agent` (Claude `sonnet`), `reviewer` = Forge `tassadar-agent` (Codex `gpt-5.6-luna`). Config generada: `pollIntervalMinutes: 0.2` (12 s, para no esperar 5 min entre consultas), `maxConcurrentEpics: 2`, `maxReviews: 2`, `maxExecutionRetries: 2`, `maxExecutionHours: 1`. El `cwd` de Carrier es una carpeta temporal fuera de cualquier clon, a propósito.

Cada escenario siembra su propia épica (spec comiteada en `main` del sandbox antes de ponerla `ready`, issue de épica, slices con `--parent` y `--blocked-by`), la marca `solve:epic:ready` a mano, arranca `carrier --config` como proceso hijo y cuenta en GitHub **antes y después** con `gh api` (PRs por rama, comentarios de la épica, comentarios y reviews de los PR, commits únicos por SHA de las ramas de la épica). Lee SQLite en modo solo lectura para estados de épica y ejecuciones. Deja `e2e-evidence.log`, `carrier.stdout.log` (el panel) y `carrier.config.json` en la raíz temporal.

## 2. Resultados por escenario

Cada fila dice de qué corrida sale. Las raíces temporales (`/var/folders/.../T/carrier-e2e-<id>/`) son descartables; lo que sigue es lo copiado de sus `e2e-evidence.log` y de GitHub.

### a. Épica de dos slices, `ready` a mano, termina en `ready-for-test`

Corridas: la pasada inicial (épica `#21 Reverse x0l7`; su `e2e-evidence.log` ya no existe, queda el rastro en GitHub) y, de nuevo con dos slices, la del escenario c (`#71 Initials nv27`), que además fue cortada con `kill -9`. No se volvió a correr `a` sola por costo: lo que `a` afirma está en el rastro de GitHub de ambas.

`#71` (eventos del issue, `gh api repos/AshuLab/carrier-sandbox/issues/71/events`):

```
21:37:55Z labeled   solve:epic:ready            vemec           (a mano)
21:38:14Z labeled   solve:epic:running          artanis-agent[bot]
21:38:19Z unlabeled solve:epic:ready            artanis-agent[bot]
21:41:55Z labeled   solve:epic:ready-for-test   artanis-agent[bot]
21:41:57Z unlabeled solve:epic:running          artanis-agent[bot]
```

- Etiquetas finales `["solve:epic","solve:epic:ready-for-test"]`; ejecuciones `ship` y `review` terminadas; workspace bajo `<raíz>/worktrees/carrier-sandbox/initials-nv27`.
- 3 PR: slice 1 (`#74`), slice 2 (`#75`), integración `#76` (`feat/initials-nv27/epic -> main`, borrador, `Closes #71`), uno solo con `Closes #71`. Autor de los PR y de todos los commits: `artanis-agent[bot]`; la review de `#76`: `tassadar-agent`, `COMMENTED`. Perfiles distintos, ninguno es Diego.
- `#21` (pasada inicial): `#26` integración, borrador, de `artanis-agent`, 2 reviews de `tassadar-agent`; `ready` 20:49:04Z, `ready-for-test` 20:53:43Z (4 min 39 s).

### b. Concurrencia 2, dos épicas del mismo repo

Corrida `carrier-e2e-pxhvs7` (`#47 Double lnsx`, `#49 Negate lnsx`, una slice cada una):

```
21:08:21Z carrier started pid=15215
21:08:57Z b: both epics running at once; running executions per epic 1 and 1; agent processes [17043,18960]
21:12:18Z b: #47 {"status":"ready_for_test","prNumber":54,"workspace":".../worktrees/carrier-sandbox/double-lnsx"}
21:12:18Z b: #49 {"status":"ready_for_test","prNumber":53,"workspace":".../worktrees/carrier-sandbox/negate-lnsx"}
21:12:20Z b: files of the integration PRs: #54 ["README.md","double.js","double.test.js"] #53 ["README.md","negate.js","negate.test.js"]
```

Dos agentes vivos a la vez (uno por épica), workspaces y carpetas de review separados (`reviews/carrier-sandbox/<épica>`), cada PR de integración toca solo su función, ramas, comentarios y commits propios sin duplicados. El panel muestra `slots 2/2 cola 0` desde 21:08:47Z. Ambas terminaron en unos 4 minutos. El escenario pasó entero.

### c. `kill -9` en medio de `ship`, reinicio sin duplicados

Corrida `carrier-e2e-gVWkVE` (`#71 Initials nv27`, dos slices, una sola vez; escenario pasó):

```
21:39:27Z c: GitHub before kill -9: {"prs":1,"prHeads":["feat/initials-nv27/072-add-initials"],"integrationPrs":[],"epicComments":1,"prComments":0,"reviewComments":0,"reviews":0,"commits":1,"branches":[".../072-add-initials",".../epic"]}
21:39:27Z c: kill -9 carrier pid=39491; exit={"code":null,"signal":"SIGKILL"}
21:39:27Z c: agent processes left running by the dead carrier: [{"pid":44116,"command":".../claude -p You are the author of the final integration PR of epic #71 ..."}]
21:39:27Z carrier started pid=51232
21:42:05Z c: executions [{"id":"4c4b6f76","stage":"ship","status":"interrupted","session":"1a5d7943"},
                         {"id":"7919b2f4","stage":"ship","status":"finished","session":"1a5d7943"},
                         {"id":"4b420392","stage":"review","status":"finished","session":"01a146a9"}]
21:42:05Z c: GitHub after: {"prs":3,"prHeads":[".../072-add-initials",".../073-list-initials-in-the-readme",".../epic"],"integrationPrs":[76],"epicComments":1,"reviews":1,"commits":4,"commitMessages":["Merge pull request #74 ...","Merge pull request #75 ...","docs: list initials in the README","feat: add initials()"]}
```

Antes: 1 PR, 1 comentario, 1 commit. Después: 3 PR (2 slices + 1 integración), el mismo único comentario, 4 commits únicos (2 de contenido + 2 merges), 1 review. Cero duplicados por rama, por cuerpo de comentario y por mensaje de commit. La sesión retomada es la misma (`1a5d7943`). El `orchestrator.log` muestra la recuperación: al reiniciar Carrier encontró el agente huérfano (el `claude` seguía vivo tras el `kill -9`), lo detuvo (`[engine] stopping orphan execution`, +1,3 s) y recién después relanzó `ship` en la misma sesión (`recovering epic ... lastStatus interrupted`). Al final no quedó ningún proceso de agente.

### d. `kill -9` con el JSON escrito y antes de importar; JSON truncado

Primera mitad (kill -9 entre el JSON y su importación), observada en las tres corridas. Siempre: JSON en disco, 0 resultados importados, `ship` en `running`, reinicio, 1 importación, `ship` no se relanza:

```
pxhvs7  21:14:45Z d: kill -9 with the JSON on disk (1176 bytes) and 0 imported results; ship execution status running
        21:14:54Z d: imported 1 time(s); executions [{"stage":"ship","status":"finished"}]
myD0QA  21:22:21Z d: kill -9 with the JSON on disk (1144 bytes) and 0 imported results; ship execution status running
        21:22:30Z d: imported 1 time(s); executions [{"stage":"ship","status":"finished"}]
iWapYE  21:32:42Z d: kill -9 with the JSON on disk (953 bytes) and 0 imported results; ship execution status running
        21:32:51Z d: imported 1 time(s); executions [{"stage":"ship","status":"finished"}]
```

GitHub antes del reinicio en `iWapYE` (`#67 Clamp eb4m`): `prs 2, epicComments 2, commits 2, reviews 0`; al terminar `prs 2, epicComments 2, commits 2, reviews 1`. Nada duplicado. El `orchestrator.log` registra además `result imported ... "duplicate":false` y, cuando se intenta una segunda vez, `"duplicate":true` (se ignora): la idempotencia por `executionId` funciona.

Segunda mitad (JSON del reviewer truncado), corrida `iWapYE`: el arnés cortó el JSON del reviewer a la mitad 38 veces mientras su agente corría, y lo que Carrier encontró al salir el agente fue un archivo de 85 bytes:

```
21:36:25Z d: cut the review JSON 38 time(s) while its agent ran; what carrier found: 85 bytes
21:37:11Z d: ended {"status":"ready_for_test","round":1,"prNumber":70}
21:37:11Z d: executions [{"id":"07ca55e8","stage":"ship","status":"finished","session":"2a6cafb6"},
                         {"id":"a11ed2fc","stage":"review","status":"invalid_result","session":"01a146a1","error":"result is not valid JSON"},
                         {"id":"418046ea","stage":"review","status":"finished","session":"01a146a1"}]; events ["execution_retried"]
[warn] [engine] invalid caller result ... "reason":"result is not valid JSON"
```

Un JSON truncado es un fallo técnico (`invalid_result`, sin gastar ronda: `round` sigue en 1), se reintenta en la misma sesión (`execution_retried`) y la épica llega a `ready-for-test` con 1 PR de integración y 1 review en GitHub. Esa corrida falló en la última aserción del escenario por un error **del arnés**, no de Carrier: comparaba la sesión del reintento contra la sesión leída cuando la ejecución recién había empezado (Codex todavía no la había informado, `null`). Se corrigió leyéndola de la fila final y se endureció (ahora exige `error = "result is not valid JSON"` y una sesión no nula); los datos de la corrida cumplen la aserción corregida (`01a146a1` en ambas ejecuciones). La corrección no se volvió a correr completa por costo.

### e. `Ctrl+C` en medio de una ejecución, reinicio retoma la sesión

Corrida `carrier-e2e-myD0QA` (`#63 Square 0wov`, pasó entera):

```
21:24:25Z e: Ctrl+C (SIGINT) to carrier pid=31503; session 72aa086f-604f-4996-bd1f-c0d96f26aa81 ... 260368 bytes; GitHub before: {"prs":0,...,"commits":0,"branches":[]}
21:24:27Z e: carrier exit={"code":0,"signal":null}; epic running/ship; executions [{"stage":"ship","status":"interrupted"}]; agent processes left: []; others under the root: []
21:27:37Z e: ended {"status":"ready_for_test","prNumber":66}
21:27:37Z e: executions [{"id":"d868f0d6","stage":"ship","status":"interrupted","session":"72aa086f"},{"id":"4b2a42e6","stage":"ship","status":"finished","session":"72aa086f"},{"id":"84cf6d74","stage":"review","status":"finished","session":"01a1469c"}]; session file grew 260368 -> 487062 bytes
21:27:37Z e: GitHub after: {"prs":2,"integrationPrs":[66],"epicComments":1,"reviews":2,"commits":2}
```

Salida limpia (código 0), épica sigue `running`/`ship`, ejecución `interrupted`, ningún proceso de agente vivo, la sesión de Claude sobrevivió. El reinicio retomó **la misma** sesión (`72aa086f`) y el archivo de sesión creció (se agregó al mismo historial), 2 PR (slice + integración), sin duplicados. El `Ctrl+C` llegó 8 s después de arrancar `ship`, cuando todavía no había nada en GitHub; la prueba de «sin duplicados con trabajo ya publicado» es la del escenario c.

## 3. Bugs encontrados y arreglados en este slice

**1. Git usaba la credencial de la persona, no el token de la ejecución (`0039ad0`).** `GH_TOKEN` lo respeta `gh`, pero `git` por HTTPS pregunta a los credential helpers del usuario (en macOS, el llavero, o sea el login de Diego). Con eso cada push y cada operación de ramas de un bot se haría como la persona. `childEnv` ahora vacía la lista de helpers y agrega uno que responde con el token de la ejecución (leído del entorno cuando git lo pide, el token no queda en el valor) vía `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n`, respetando las entradas que el entorno ya tuviera. Verificado en GitHub: los commits de los PR `#74`, `#75`, `#76` tienen autor y committer `artanis-agent[bot]`, y los PR `app/artanis-agent`. Test unitario en `src/providers/claude.test.ts`.

**2. Un reviewer Codex escribía su JSON en una ruta con un segmento menos y cada reintento lo repetía (`4d043db`).** En la corrida `pxhvs7` la épica `#55 Clamp lnsx` terminó en `needs-human` (sigue así en el sandbox): el reviewer escribió el JSON en `.../T/orchestrator/results/<id>.json` en lugar de `.../T/carrier-e2e-pxhvs7/orchestrator/results/<id>.json` (se comió el segmento de la raíz), Carrier no lo encontró (`invalid caller result ... "reason":"result file is missing"`) y los tres intentos (`maxExecutionRetries: 2`) repitieron la ruta mal copiada, hasta `se agotaron los reintentos de review (3 intentos)`. Era un bug real, no un fallo del escenario: el comportamiento de Carrier fue el correcto (fallo técnico, reintentos, `needs-human`); la causa era el prompt, que daba una ruta larga para que el modelo la retipee. Arreglo: la ruta también va en la variable de entorno `CARRIER_RESULT_PATH` (en Claude y en Codex) y el prompt manda escribir en `"$CARRIER_RESULT_PATH"` en lugar de retiparla. Con el arreglo, las corridas siguientes (`myD0QA`, `iWapYE`, `gVWkVE`) no repitieron el fallo en el flujo normal. `#55` quedó como estaba por ser evidencia: no es un problema abierto de Carrier.

**Arnés** (no son bugs de Carrier): los carriers de un escenario fallido se matan para no dejar el lock tomado al siguiente (`a034932`); el reviewer se corta hasta que su proceso termina y `b` espera a los dos agentes; en `d` el arnés ahora tolera que el agente borre el JSON para reescribirlo (antes `readFileSync` tiraba `ENOENT`; es la causa más probable de que `d` se cortara en `myD0QA`: el reviewer Codex había borrado el archivo, ver su `stderr.log`); la aserción de sesión de `d` (arriba); y sin las variables el cuerpo del `describe` saltado igual se ejecuta al recolectar los tests y tiraba `TypeError`, así que `pnpm test:integration` fallaba sin credenciales en lugar de saltearse (ahora usa un entorno vacío).

## 4. Abierto o a vigilar

- **Rutas mal retipeadas por Codex, riesgo residual.** Con `CARRIER_RESULT_PATH` el flujo normal anda, pero en `iWapYE`, peleando contra el arnés que le truncaba el archivo, el reviewer escribió dos veces en rutas mal armadas (`.../T/orchestrator/results/...` y `.../gn/orchestrator/results/...`, sin la raíz y sin `T`) antes de acertar. Se absorbe como fallo técnico, pero cada reintento repite el mismo prompt: si el modelo insiste, termina en `needs-human` (el comportamiento previsto). No se tocó el diseño; si en uso real aparece, el reintento podría anteponer al prompt la ruta ya intentada y que falló.
- **Costo de un reviewer que pelea.** En esa corrida el reviewer gastó 3,5 M de tokens de entrada (contra 0,24 a 0,52 M normales) hasta que su proceso terminó. Es un artefacto del arnés (corta el archivo 38 veces), no de uso real.
- **Comentarios `Lane 1 worktree`.** Algunas épicas tienen dos comentarios de Solve (`Epic worktree` y `Lane 1 worktree`) con cuerpos distintos: es lo que escribe `ship`, no un duplicado de Carrier (los chequeos comparan cuerpos).
- **Huérfanos.** Tras `kill -9`, el agente sigue vivo hasta que el reinicio lo detiene (≈1,3 s después de arrancar). Previsto por [ADR 0004](../adr/0004-agentes-en-el-host-con-preferencias-de-la-terminal.md). Con `Ctrl+C` no quedó nada. El arnés mata igual lo que cuelga de la raíz por si Codex orfana su proceso de comando.
- **Escenario `a` suelto.** No hay un log del arnés para `a`; su evidencia es la de GitHub (§2.a) y la de c.

## 5. Costo y tiempo observados

- Por corrida: `c` 4 min 29 s, `d` 7 min, `e` ≈ 4 min, `b` ≈ 4 min por épica en paralelo; `a` ≈ 4,7 min.
- `ship` con Sonnet: USD 0,38 a 0,54 por épica (el campo `total_cost_usd` del stream de Claude; la mayor, 2 slices). Un `ship` cortado con `kill -9` cuesta lo que alcanzó a hacer más lo mismo al retomar. Codex no informa USD: 0,24 a 0,52 M tokens de entrada por review normal.
- Total de lo gastado en este slice: la corrida inicial creó unas 12 épicas (USD 10 a 13 estimados, de la sesión anterior); esta pasada de consolidación sumó 2 épicas más (`d` y `c`, estimado USD 2 a 3). Sin la suite entera.

## 6. Qué quedó en el sandbox

Todo queda como evidencia, nada borrado ni cerrado, y ninguna épica quedó con `solve:epic:ready`:

- 14 épicas de Carrier (`#15`, `#21`, `#27`, `#29`, `#35`, `#41`, `#45`, `#47`, `#49`, `#55`, `#59`, `#63`, `#67`, `#71`), sus slices y PR (slices mergeados en la rama de la épica, integración en borrador sin mergear), y las ramas `feat/<feature>/epic`.
- `#55 Clamp lnsx` en `solve:epic:needs-human` (bug 2); `#15 Reverse r1qe` (primer intento, con su PR de integración cerrado `#20`) y `#45 Square 40vx` (cerrada, un slice abierto) son restos de la primera pasada.
- `main` con un commit de spec por épica y un `chore: point the solve worktrees at the e2e root` por corrida; el `path` de `docs/agents/solve.md` apunta a la última raíz temporal, ya borrada: el próximo escenario lo reescribe (`Sandbox.prepare`). Para limpiar todo, ver «Reiniciarlo» en [sandbox-repo.md](sandbox-repo.md).
