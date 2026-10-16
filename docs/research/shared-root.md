# Raíz compartida con Solve (spike #8)

Fecha: 15/10/2026 (§1 a §5) y 16/10/2026 (§6). Entorno: macOS, git 2.54.0 (Apple Git-157), gh 2.102.0, Node 26.12.0, pnpm 12.11.2, Claude Code 2.1.301, plugin `solve` 0.24.0 (el más reciente de `~/.claude-ashu-lab/plugins/cache/ashulab/solve/`). §1 a §5 se corrieron en repos descartables dentro de `mktemp -d` con un remoto bare local (sin GitHub); §6 se corrió contra el repo descartable de GitHub `AshuLab/carrier-sandbox` (ver [sandbox-repo.md](sandbox-repo.md)). Los temporales se borraron al final.

Resultado: los seis criterios tienen evidencia. El 2 (dos épicas drenadas por `ship` desde un clon en `<raíz>/repos/<org>/<repo>/`) se cerró el 16/10 con corridas reales de `ship` (§6) y **confirma lo leído de las fuentes**; solo cambia un detalle del orden de los lanes (ver §6). La spec se actualizó en este mismo PR.

## 1. Cómo se le comunica la raíz a Solve

**No se le comunica: Solve no tiene el concepto de raíz.** Se leyeron sus fuentes reales (`skills/ship/SKILL.md`, `skills/ship/WORKTREES.md`, `skills/setup/SKILL.md`, `skills/setup/REFERENCE.md`, `skills/land/SKILL.md`, `skills/ship/scripts/solve-next-startable`, `README.md`):

- `grep -rnE "process\.env|SOLVE_|getenv|environment variable|\$HOME|XDG"` sobre todo el plugin, sin contar `code-*`: **cero resultados**. No hay variable de entorno, flag ni clave de configuración para una raíz.
- Lo único que decide dónde va un worktree es la línea **Worktrees → path** de `docs/agents/solve.md` de *cada repo* (lo escribe `setup`, se versiona con el repo), con los tokens `<repo>` y `<feature>` que `ship` rellena en cada corrida. Sin archivo o sin path: `~/.solve/worktrees/<repo>/<feature>/` (`WORKTREES.md`: «From **Worktrees** in `docs/agents/solve.md` - default `~/.solve/worktrees/<repo>/<feature>/`»). Este repo tiene exactamente ese valor (`docs/agents/solve.md`, sección Worktrees, modo off).
- `<repo>` es «the repository directory's name», o sea el nombre de la carpeta del clon donde corre `ship`. Solve **no crea, no busca ni administra clones**: trabaja en el árbol donde lo invocan (el «shared tree»). `~/.solve/repos/` y `~/.solve/orchestrator/` no existen en Solve; son convención de Carrier. Hoy `~/.solve/` tiene `worktrees/` y `local-marketplace/` (este último no lo usa `ship`).
- La invocación de `ship` solo puede pedir **aislar la épica** («worktree this epic»); eso se respeta en cualquier modo, pero la ruta sigue saliendo de `solve.md`. No se puede pasar la ruta por corrida.

Consecuencias para Carrier:

1. **La raíz de worktrees es la de `solve.md` de cada repo, no la de Carrier.** Con la raíz por defecto (`~/.solve/`) todo coincide sin configurar nada. Con otra raíz, Carrier no puede empujarla a Solve por corrida: habría que cambiar el `path` en el `solve.md` de cada repo configurado (config versionada, vale para todas las máquinas y personas). Por eso Carrier no debe **suponer** la ruta del workspace: la deriva, la verifica con `git worktree list` y guarda la real en SQLite.
2. **Con Worktrees en `off` (como este repo) `ship` trabaja en el clon mismo** y solo aísla la épica si se lo piden. Dos épicas desde un mismo clon administrado chocarían en el pre-flight (`git status` sucio por la otra épica detiene la corrida). La tarea de `ship` debe pedir siempre «worktree this epic», o el repo debe tener Worktrees `on`. El orquestador no debe depender de lo que diga `solve.md`.
3. **Colisión entre organizaciones.** El worktree es `worktrees/<repo>/<feature>/`, sin la organización. `AshuLab/demo` y `otra/demo` con la misma `<feature>` apuntan a la misma ruta (ver §4). La configuración de Carrier debe rechazar dos repos con el mismo nombre de carpeta, o dejar que el segundo espere.
4. **Los lanes** (hasta 3 slices en paralelo) son `<raíz>/worktrees/<repo>/<feature>--lane-<N>/`, hermanos del worktree de la épica y siempre, esté Worktrees `on` u `off`. Ejemplo real de esta misma corrida de `ship` en esta máquina (`git worktree list` desde el clon de este repo):

```
/Users/vemec/DG-Projects/AshuLab/carrier                                              f254c27 [feat/carrier-orquestador-de-epicas-autonomas/epic]
/Users/vemec/.solve/worktrees/carrier/carrier-orquestador-de-epicas-autonomas--lane-1 f254c27 [feat/carrier-orquestador-de-epicas-autonomas/008-spike-shared-root]
/Users/vemec/.solve/worktrees/carrier/carrier-orquestador-de-epicas-autonomas--lane-2 f254c27 (detached HEAD)
/Users/vemec/.solve/worktrees/carrier/carrier-orquestador-de-epicas-autonomas--lane-3 476380e [feat/carrier-orquestador-de-epicas-autonomas/032-codex-runner]
```

   La épica quedó en el árbol compartido (modo off, sin pedir aislamiento) y los lanes bajo `~/.solve/worktrees/carrier/`. Es evidencia real de rutas de Solve, pero **no** es el caso del criterio 2 (no hay clon bajo `repos/` ni dos épicas).
5. **Reutilización:** `ship` deriva la ruta, mira `git worktree list` y si ya está «it's yours»; la reutiliza sin recrearla, y `<feature>` se lee de la rama de la épica, nunca se vuelve a calcular. Además `ship` comenta en el issue de la épica ruta, máquina y rama de cada worktree que crea. `land` solo borra lo que `git worktree list` muestra (un path de otra máquina lo reporta y no lo toca) y se ejecuta desde el árbol principal.

## 2. Ruta del checkout del reviewer

**`<raíz>/reviews/<repo>/<feature>/`**, un `git worktree add --detach <ruta> <SHA>` del mismo clon administrado.

- **Fuera de `worktrees/`**: Solve solo escribe ahí `<feature>` y `<feature>--lane-N`. Un nombre como `<feature>--review` dentro de `worktrees/<repo>/` podría pisar a una épica llamada igual; `reviews/` nunca es de Solve, así que no hay colisión posible.
- **Separado por `<repo>/<feature>`**, igual que el autor, para que dos épicas se revisen a la vez. Mismo límite de nombre de repo que en §1.
- **Detached al SHA revisado**, no en la rama de la épica: git no deja sacar una rama ya sacada en otro worktree y el autor la tiene.
- **No anidado** en el worktree del autor: sería contenido sin seguimiento en su `git status`, justo lo que los chequeos de árbol sucio de `ship` tratarían como trabajo ajeno.
- **Cada ronda reutiliza la misma ruta**: `git fetch` y `git switch --detach <SHA nuevo>`.
- Se quita con `git worktree remove` al terminar la épica. Como comparte `.git` con el clon aparece en `git worktree list`; `land` actúa sobre lo que ese comando lista, así que podría quitarlo si está limpio: es inocuo, la épica ya terminó.

Demostración (repo descartable `demo`, clon en `<raíz>/repos/AshuLab/demo`, remoto bare local, dos épicas `alpha` y `beta` con un lane cada una; `<root>` es el `mktemp -d`):

```
$ git worktree list    # antes del reviewer
<root>/repos/AshuLab/demo           303ec11 [main]
<root>/worktrees/demo/alpha         303ec11 [feat/alpha/epic]
<root>/worktrees/demo/alpha--lane-1 303ec11 [feat/alpha/001-x]
<root>/worktrees/demo/beta          303ec11 [feat/beta/epic]
<root>/worktrees/demo/beta--lane-1  303ec11 [feat/beta/001-x]

$ git worktree add <root>/reviews/demo/alpha feat/alpha/epic     # el checkout ingenuo
fatal: 'feat/alpha/epic' is already used by worktree at '<root>/worktrees/demo/alpha'

$ git worktree add --detach <root>/reviews/demo/alpha <SHA>      # el propuesto
<root>/reviews/demo/alpha           303ec11 (detached HEAD)
$ git -C <root>/worktrees/demo/alpha status --porcelain          # autor: limpio (salida vacía)

$ git worktree add --detach <root>/worktrees/demo/beta/review <SHA>   # contraste: anidado
$ git -C <root>/worktrees/demo/beta status --porcelain
?? review/

# ronda 2: el autor commitea y pushea; el reviewer reapunta la MISMA ruta
$ git -C <root>/reviews/demo/alpha fetch && git -C <root>/reviews/demo/alpha switch --detach <SHA nuevo>
reviewer HEAD == author HEAD: yes
```

Comprobación de rutas: la del reviewer no es igual ni prefijo ni descendiente de ninguna de `worktrees/demo/alpha`, `alpha--lane-1`, `beta`, `beta--lane-1` ni del clon (`ok` en las cinco).

## 3. Spec y tickets preparados antes de `ready`

Qué es cada cosa, según `to-spec`, `to-tickets` y `ship`:

- **Épica (el PRD) y tickets** son issues de GitHub (la épica con `solve:epic`, cada slice sub-issue con `solve:ticket`). No dependen de ninguna ruta: el caller los lee con `gh` desde cualquier clon o worktree (`gh issue view <n>`, `gh issue list --label solve:refined` con el filtro de la épica).
- **El brief/spec en archivo** (`docs/specs/<feature>.md`), los ADR (`docs/adr/`) y la edición del glosario (`docs/glossary.md`) son los «hand-off artifacts» de `sharpen`, `to-spec` y `vocab`: archivos **sin seguimiento en el árbol donde se escribieron** (el de Diego). `ship` solo los ve y los comete a la rama de la épica si corre en ese mismo árbol (`SKILL.md`, *Pick the tree* y *Clean the tree, cut the epic branch*).

Un clon administrado bajo `<raíz>/repos/` **no tiene esos archivos** si nadie los comitea y pushea antes de `ready`. Demostración:

```
# checkout del autor, archivos sin seguimiento
$ git -C author/demo status --porcelain
?? docs/

# clon administrado y worktree de la épica nuevos: no existe docs/
ls: <root>/repos/AshuLab/demo/docs: No such file or directory
ls: <root>/worktrees/demo/gamma/docs: No such file or directory

# el autor los comitea en la rama de la épica y pushea; el worktree la actualiza
$ ls <root>/worktrees/demo/gamma/docs/specs/ <root>/worktrees/demo/gamma/docs/adr/
0001-x.md     gamma.md

# un archivo suelto en el clon NO cruza a un worktree nuevo (se corta desde lo comiteado)
$ ls <root>/worktrees/demo/delta
README.md
```

Rutas usadas: `<raíz>/worktrees/<repo>/<feature>/docs/specs/<feature>.md` (y `docs/adr/`, `docs/glossary.md`). La evidencia real: el spec de este proyecto se lee en `/Users/vemec/.solve/worktrees/carrier/carrier-orquestador-de-epicas-autonomas--lane-1/docs/specs/autonomous-orchestrator.md`, un worktree bajo la raíz, porque está comiteado en la rama.

Condición nueva: **antes de poner `solve:epic:ready`, spec, ADR y glosario deben estar comiteados y pusheados** (a la rama de la épica o a la base). Si no, el autor corre sin ellos y el reviewer también. La tarea del caller debe además llevar el número de la épica para leer el PRD y los tickets por `gh`, que es la fuente que no depende de rutas.

## 4. Mismo nombre de repo en dos organizaciones

Con clones `repos/AshuLab/demo` y `repos/other/demo`, ambos derivan `worktrees/demo/<feature>/`:

```
$ git -C <root>/repos/other/demo worktree add -b feat/alpha/epic <root>/worktrees/demo/alpha origin/main
fatal: '<root>/worktrees/demo/alpha' already exists
```

Git no pisa la carpeta ajena, pero la corrida de `ship` del segundo repo termina «sin workspace». Ver la consecuencia 3 de §1.

## 5. Una sesión retomada sigue operando en las mismas rutas

Lo que ya establecía el [spike de headless (#5)](headless-agents.md): `claude --resume <id>` encuentra la sesión sin importar el cwd; `codex exec resume` toma el cwd del proceso. Faltaba qué cwd usa realmente un agente retomado. Prueba con Claude 2.1.301 (haiku), repo descartable con el worktree `<root>/worktrees/demo/alpha`:

```
== run 1: cwd = el worktree, "recuerda KIWI-7 y corre pwd"
{"session_id":"733e9909-afeb-4f6b-9ca9-ef92f505423c","result":"KIWI-7 <root>/worktrees/demo/alpha"}
== run 2: proceso nuevo (como tras reiniciar carrier), mismo cwd, --resume
{"session_id":"733e9909-...","result":"KIWI-7 <root>/worktrees/demo/alpha"}
== run 3: proceso nuevo, OTRO cwd (<root>/elsewhere), --resume
{"session_id":"733e9909-...","result":"KIWI-7 <root>/elsewhere"}
```

- Retomar recuerda el contexto y mantiene el `session_id` en los tres casos.
- **El Bash del agente retomado corre en el cwd del proceso nuevo, no en el original** (run 3). La sesión no «recuerda» el workspace.
- El archivo de sesión sigue en la carpeta del cwd original: `$CLAUDE_CONFIG_DIR/projects/<cwd con / y . como ->/<id>.jsonl`; el run 3 no creó otro.

Por tanto una sesión retomada opera en las mismas rutas **si y solo si Carrier la lanza con el `cwd` guardado de la épica**. Condición para el runner: persistir en SQLite la ruta real del workspace (y la del reviewer) junto con el id de sesión, y usar ese `cwd` en cada `--resume` (y cada `codex exec resume`). Esto coincide con la condición de la [investigación de contenedores](agent-containers.md) («si el `cwd` no cambia»). Del lado de Solve, el reinicio no cambia nada: `ship` rederiva la ruta y reutiliza el worktree si ya está en `git worktree list` (§1.5).

## 6. Dos épicas drenadas por `ship` desde un clon administrado (criterio 2)

Corrida real del 16/10/2026 contra `AshuLab/carrier-sandbox` (privado, descartable; cómo se sembró y se reinicia está en [sandbox-repo.md](sandbox-repo.md)). `<root>` es `/var/folders/k_/fjsrsfrd2wg690wbghkg77c80000gn/T/tmp.uVIZdTien0/solve-root` (un `mktemp -d` fuera de `~/.solve`, para no tocar trabajo real).

**Montaje.** Clon en `<root>/repos/AshuLab/carrier-sandbox` (`gh repo clone`, remoto https sin token en `.git/config`). El `docs/agents/solve.md` del sandbox lo escribió el skill `setup` real (`claude -p "/solve:setup ..." --model sonnet`, con las respuestas en el prompt): Worktrees **on**, path `<root>/worktrees/<repo>/<feature>/` (absoluto, con `<repo>` y `<feature>` literales), base y destino `main`, tipo de rama `feat`. Dos épicas con la forma de `to-spec`/`to-tickets` (`#1 Farewell` y `#2 Shout`, etiqueta `solve:epic`, a mano `solve:epic:ready`; cada una con 2 slices `solve:ticket,solve:refined`, sub-issue de su épica, el segundo `blocked-by` el primero y cada uno con Definition of done). Sus specs (`docs/specs/farewell.md`, `docs/specs/shout.md`) se comitearon y pushearon a `main` antes de poner `ready`.

**Comando** (dos procesos a la vez, mismo clon como cwd, stdin cerrado, binario real `~/.local/bin/claude`, no el wrapper de Superset):

```sh
cd <root>/repos/AshuLab/carrier-sandbox && ~/.local/bin/claude -p "/solve:ship drain epic #<n> of AshuLab/carrier-sandbox (the repo in the current directory). Worktree this epic. Run unattended: nobody can answer questions, decide from the skill's own rules. Leave the integration PR as a draft and do not merge it." \
  --model sonnet --permission-mode bypassPermissions --output-format stream-json --verbose --max-budget-usd 4 </dev/null
```

Identidad: el login de `gh` (`vemec`), sin Forge, como el spike pedía.

**Resultado** (ambas salieron con `exit=0`, `outcome` de `ship`: épica drenada, PR de integración en borrador):

| | `#1 Farewell` | `#2 Shout` |
|---|---|---|
| Duración | 186 s | 169 s |
| Costo (Sonnet 5.5) | USD 0,51 (18 turnos) | USD 0,50 (19 turnos) |
| Worktree de la épica | `<root>/worktrees/carrier-sandbox/farewell` | `<root>/worktrees/carrier-sandbox/shout` |
| Lane | `<root>/worktrees/carrier-sandbox/farewell--lane-1` | `<root>/worktrees/carrier-sandbox/shout--lane-1` |
| PR de slices (mergeados con merge commit) | #8 (slice #3), #10 (slice #4) | #7 (slice #5), #9 (slice #6) |
| PR de integración (borrador, **sin mergear**) | #12 `feat/farewell/epic` -> `main` | #11 `feat/shout/epic` -> `main` |

El `<repo>` del path es `carrier-sandbox`, el nombre de la carpeta del clon, sin la organización (§1.3 y §4). `<feature>` es el slug del título de la épica y se leyó de la rama `feat/<feature>/epic`. Los tiempos: los worktrees de las épicas aparecieron a los ~38 s del arranque, los PR de slices entre 1 min 10 s y 2 min 20 s y los de integración a los ~2 min 50 s y ~3 min 5 s.

`git worktree list` del clon al terminar (las rutas largas abreviadas con `<root>`):

```
<root>/repos/AshuLab/carrier-sandbox                          c423756 [main]
<root>/worktrees/carrier-sandbox/farewell                     4c5302c [feat/farewell/epic]
<root>/worktrees/carrier-sandbox/farewell--lane-1             4c5302c (detached HEAD)
<root>/worktrees/carrier-sandbox/shout                        1acb19f [feat/shout/epic]
<root>/worktrees/carrier-sandbox/shout--lane-1                1acb19f (detached HEAD)
```

Mientras corrían (a los 45 s) cada lane estaba en su rama de slice (`feat/farewell/003-add-farewell`, `feat/shout/005-add-shout`): al terminar, `ship` los **desacopló** (*Freeing a lane*) y borró las ramas de slice, así que el lane queda «estacionado» en el SHA de la épica. El clon administrado no se movió: sigue en `main`, en `c423756`, con el árbol limpio, y nunca hizo pull.

**Comentarios que `ship` deja en el issue de cada épica**, uno por worktree, con máquina, ruta absoluta, rama y base (épica #1; la #2 es igual con `shout`):

```
**Epic worktree**
- Machine: vemec@mac-studio.lan (Darwin arm64)
- Path: <root>/worktrees/carrier-sandbox/farewell
- Branch: feat/farewell/epic
- Base: main

**Lane 1 worktree**
- Machine: vemec@mac-studio.lan (Darwin arm64)
- Path: <root>/worktrees/carrier-sandbox/farewell--lane-1
- Epic branch: feat/farewell/epic
- First slice: #3 (feat/farewell/003-add-farewell)
```

Los dos PR de integración nombran las dos rutas y el `git worktree remove <ruta>` de cada una en el cuerpo (`Closes #<épica>`, slices, verificación, worktrees). `ship` no cierra la épica (siguen `OPEN`) ni borra worktrees.

**Lo que se confirmó de §1 y §3 con una corrida real:**

- **Dos drenajes a la vez desde un mismo clon no chocan.** Cada uno cortó su rama de épica y de slice en su propio namespace y ninguno empujó `main`. Cada informe de `ship` dice que vio el drenaje del otro y no lo tocó.
- **Aislar la épica funciona con la ruta de `solve.md`**, y los lanes son hermanos `<feature>--lane-1` (§1.4). Con Worktrees **on** `ship` crea el worktree solo; **no se probó off + «worktree this epic»** (la consecuencia 2 de §1 sigue sin observación directa; el prompt pedía aislar en ambos casos).
- **El spec comiteado llega al workspace**: `<root>/worktrees/carrier-sandbox/farewell/docs/specs/farewell.md` (y `shout.md`) existen en el worktree de la épica y en cada lane, porque estaban en `main` antes de `ready` (§3). La épica y los tickets se leyeron por `gh` desde esos mismos árboles.
- **Reutilización tras relanzar (§1.5).** Se agregó el slice `#13` a la épica `#1` ya drenada (con la etiqueta `ready` puesta) y se volvió a lanzar el mismo comando: `ship` reutilizó el worktree de la épica y el lane estacionado sin crear nada (`git worktree list` idéntico, mismas dos rutas; **no** hubo comentarios nuevos en el issue), construyó el slice en el lane, mergeó el PR #14 y **actualizó el cuerpo del PR de integración #12 existente** en vez de abrir otro. 104 s, USD 0,24.
- **El conflicto de README es de integración, no del drenaje.** Los dos PR de integración aparecen `MERGEABLE` / `CLEAN` contra `main`, pero `git merge-tree --write-tree --name-only origin/feat/farewell/epic origin/feat/shout/epic` sale con código 1: `CONFLICT (content): Merge conflict in README.md`. Quien se mergee segundo choca; es el aviso del propio `ship` («the conflict is `land`'s to surface»). Carrier debe tratarlo como un blocker de integración, no como un fallo del drenaje.

**Cosas nuevas para el runner:**

- Correr `pnpm test` en cada worktree deja un `pnpm-lock.yaml` sin seguimiento (y `node_modules`, ignorado). `ship` borró el lock sin comitearlo; un reviewer o un chequeo de «árbol limpio» de Carrier que corra después debe tolerarlo o el repo debe ignorarlo.
- La ruta del worktree vive en el `solve.md` **versionado** del repo, y en el sandbox quedó absoluta y apuntando a un temporal. Borrar el temporal deja un `solve.md` con una ruta muerta; el siguiente sembrado la reescribe (ver [sandbox-repo.md](sandbox-repo.md)). Es la consecuencia 1 de §1 en la práctica: una raíz distinta de `~/.solve/` obliga a editar y pushear el `solve.md` de cada repo.
- Orden de magnitud por épica de 2 slices triviales: ~3 min y ~USD 0,5 con Sonnet; el setup real costó USD 0,20 y 31 s. Total del spike: ~USD 1,45.

## Lo que no se observó

- Worktrees en `off` con «worktree this epic» (el sandbox se configuró en `on`; la lectura de `SKILL.md` dice que se respeta en cualquier modo, pero no se corrió).
- Codex: el cwd de la sesión retomada se tomó de lo observado en #5 (`exec resume` usa el cwd del proceso); no se repitió la prueba del run 3.
- Un repo con `docs/agents/solve.md` sin `<repo>` en el path (la colisión que `WORKTREES.md` advierte) no se probó.

## Efecto en la spec

La spec se actualizó en este PR: la sección *Raíz compartida* dice que Solve no recibe la raíz y qué hace Carrier con eso, define `reviews/`, y fija las condiciones nuevas (preparar y pushear antes de `ready`, pedir aislamiento, `cwd` guardado, nombres de repo únicos). La pregunta abierta recibe un resultado parcial.
