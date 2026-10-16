# Raíz compartida con Solve (spike #8)

Fecha: 15/10/2026. Entorno: macOS, git 2.54.0 (Apple Git-157), Claude Code 2.1.301, plugin `solve` 0.24.0 (el más reciente de `~/.claude-ashu-lab/plugins/cache/ashulab/solve/`). Todo lo local se corrió en repos descartables dentro de `mktemp -d` con un remoto bare local (sin GitHub, sin pushes a remotos reales); los temporales se borraron al final.

Resultado: los criterios 1, 3, 4 y 5 tienen evidencia, cada uno con una condición de diseño nueva; el 2 (dos épicas drenadas por `ship`) **no se pudo verificar** (ver [Lo que no se observó](#lo-que-no-se-observó)). La spec se actualizó en este mismo PR.

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

## Lo que no se observó

- **Dos épicas del repo de prueba drenadas por `ship` desde un clon en `<raíz>/repos/<org>/<repo>/`, con sus worktrees reales** (criterio 2). Requiere un repo de GitHub descartable con épicas y slices reales, corridas reales de `ship` y agentes que abran PRs. Ese repo no existe: `AshuLab/agent-forge` se autorizó solo para la prueba de identidad de Forge, sin épicas ni PRs, y no se corrió `ship` contra ningún repo real ni se creó ninguno. Lo de §1 sale de leer las fuentes de Solve y de simular las rutas con `git worktree`, no de una corrida de `ship`. Para cerrarlo: un repo descartable (p. ej. `AshuLab/carrier-sandbox`) con dos épicas de 2 slices triviales, un clon en `<raíz>/repos/AshuLab/carrier-sandbox`, `solve:epic:ready` puesto a mano, `ship` lanzado dos veces en paralelo pidiendo «worktree this epic», y registrar `git worktree list` y los comentarios de ruta que `ship` deja en cada épica. En esa corrida confirmar también las consecuencias 2 (modo off y pedir aislamiento) y 5 (reuso tras cortar y relanzar).
- Codex: el cwd de la sesión retomada se tomó de lo observado en #5 (`exec resume` usa el cwd del proceso); no se repitió la prueba del run 3.
- Un repo con `docs/agents/solve.md` sin `<repo>` en el path (la colisión que `WORKTREES.md` advierte) no se probó.

## Efecto en la spec

La spec se actualizó en este PR: la sección *Raíz compartida* dice que Solve no recibe la raíz y qué hace Carrier con eso, define `reviews/`, y fija las condiciones nuevas (preparar y pushear antes de `ready`, pedir aislamiento, `cwd` guardado, nombres de repo únicos). La pregunta abierta recibe un resultado parcial.
