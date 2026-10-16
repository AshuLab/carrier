# Claude y Codex dentro de contenedores en macOS

> Spike del 15/10/2026 (issue #6, épica #3). Responde a la pregunta abierta «Agentes en contenedores» de la [spec](../specs/autonomous-orchestrator.md) y pone a prueba el [ADR 0003](../adr/0003-agentes-en-contenedor.md). Todo se corrió en una carpeta temporal bajo `/tmp`, con un repo descartable y un remoto Git local (`git init --bare`), sin credenciales reales dentro de ningún contenedor y sin tocar GitHub. Los scripts son descartables: [`spike-agent-containers/`](spike-agent-containers/) (`Dockerfile`, `mock-llm.mjs`, `proxy.mjs`).

## Veredicto

**Viable con condiciones.** Lo que dependía del contenedor funciona: worktrees de Solve coherentes adentro y afuera, ambos CLI corren en Linux y hacen `git status`/commit/push desde su herramienta de shell, la sesión se retoma en un contenedor nuevo, `pnpm test` corre, la red se puede restringir con una lista de permitidos y `docker kill` no deja procesos. Quedan **sin verificar** tres cosas que necesitan credenciales reales, y por eso el spike no queda cerrado del todo (detalle en [Sin verificar](#sin-verificar-y-qué-lo-cerraría)):

1. Claude y Codex autenticados de verdad dentro del contenedor, y push a un repo de GitHub de prueba. Los CLI se probaron contra un modelo simulado.
2. Una ejecución de más de 70 minutos con `gh` autenticado y el token renovado por Forge.
3. La lista de red con login real (cuenta ChatGPT, OAuth de Claude): solo se observó con claves falsas.

Ningún resultado contradice el ADR 0003. Hay tres condiciones nuevas para el runner: montar con rutas idénticas a las del host, ejecutar `codex` sin su sandbox propio (el contenedor es el límite) y resolver el login sin montar `~/.claude*` (ver [Sesiones y login](#3-sesiones-y-login)).

| Criterio de la Definition of done | Resultado |
|---|---|
| 1. Documento con runtimes probados, versiones y recomendado | pasa, pero solo Docker Desktop estaba instalado; OrbStack y Colima no se probaron |
| 2. Claude y Codex en contenedor: `git status`, commit y push; `git worktree list` coherente | parcial: coherencia, commit y push (a un remoto local) pasan con modelo simulado; falta login real y push a GitHub |
| 3. Sesión retomada en un contenedor nuevo y dónde está en el host | pasa (modelo simulado) |
| 4. Más de 70 minutos con `gh` autenticado y mecanismo de renovación | **no verificado**; el mecanismo de archivo montado sí se probó con tokens falsos |
| 5. `pnpm test` en el contenedor y estrategia de toolchains | pasa |
| 6. Salidas de red mínimas y si se pueden restringir | pasa para el uso con clave de API; con login real queda sin observar |
| 7. Detener el contenedor con un árbol de procesos en marcha no deja procesos | pasa |
| 8. Veredicto | viable con condiciones |

## Entorno y runtimes

| | |
|---|---|
| Sistema | macOS 27.0 (Darwin 27.0.0), arm64 |
| Runtime probado | **Docker Desktop 4.95.0**: Engine 29.8.2, containerd v2.3.6, runc 1.5.1, kernel de la VM `7.0.14-linuxkit`, driver `overlayfs`, cgroup v2; cliente 29.8.2 |
| VM | 12 CPU, 7,75 GiB de memoria (valores por defecto de la instalación) |
| OrbStack, Colima | **no instalados** en esta máquina (`which orb colima` no devuelve nada). No se probaron ni se instalaron para no modificarla |

Recomendación: **Docker Desktop**, porque es el único que se pudo probar y todo lo de abajo se midió con él. No hay evidencia de que OrbStack o Colima fallen; el diseño solo usa `docker run/kill/stop`, montajes de carpetas, redes y `--init`, que todos exponen, pero no se verificó. Dos consideraciones que no se midieron: la VM tiene memoria fija (7,75 GiB) que hay que repartir entre las épicas en paralelo, y Docker Desktop tiene condiciones de licencia para empresas que conviene revisar antes de adoptarlo como requisito.

Imagen de prueba ([`Dockerfile`](spike-agent-containers/Dockerfile)): `node:26-bookworm-slim` + `git` 2.39.5 + `gh` 2.23.0 (paquete de Debian, viejo; para producción conviene el repositorio oficial de `gh`) + `pnpm` 12.4.1 + Claude Code 2.1.301 + Codex CLI 0.153.4, ambos instalados con `npm i -g` y ejecutándose como binarios `linux-arm64`. Docker informa ~2 GB en disco. Arranque y salida de un contenedor vacío: 0,15-0,16 s (3 medidas).

## 1. Montajes y worktrees de Solve

Layout de prueba, igual al de Solve: clon en `<raíz>/repos/acme/demo`, worktree en `<raíz>/worktrees/demo/feat-demo` y remoto bare en `<raíz>/remote/demo.git`. El archivo `.git` del worktree contiene la ruta **absoluta** del clon (`gitdir: <raíz>/repos/acme/demo/.git/worktrees/feat-demo`), por eso la ruta importa. Todos los casos corren como `-u 1000:1000`.

| Montaje | Resultado adentro |
|---|---|
| clon y worktree en la **misma ruta** que en el host | `git worktree list` idéntico al de afuera; `git status -sb` correcto |
| solo `<clon>/.git` y el worktree, en las mismas rutas | idéntico; alcanza con la carpeta `.git` del clon |
| worktree en `/work`, clon en su ruta | `git status` anda, pero `git worktree list` marca el worktree `prunable` (el clon lo registra en la ruta del host): un `git worktree prune` adentro lo borraría |
| solo el worktree, sin clon | `fatal: not a git repository: <clon>/.git/worktrees/feat-demo` |

Salida del caso bueno, adentro (el afuera es idéntico):

```
/private/tmp/carrier-spike6/solve/repos/acme/demo           e037b92 [main]
/private/tmp/carrier-spike6/solve/worktrees/demo/feat-demo  e037b92 [feat/demo/epic]
```

Detalles que el runner tiene que respetar:

- **Rutas idénticas.** Montar `-v <ruta>:<ruta>` con la ruta resuelta (`/tmp` es `/private/tmp` en macOS; el `.git` del worktree guarda la resuelta).
- **`safe.directory`.** Con un usuario que no es root, Git rechaza el repo con `detected dubious ownership`, porque la carpeta de montaje aparece como de root dentro del contenedor. `GIT_CONFIG_COUNT/KEY/VALUE` con `safe.directory=*` no lo arregló en Git 2.39.5; sí `git config --system safe.directory '*'` en la imagen (última línea del `Dockerfile`).
- **Propietario.** Los archivos creados adentro por el uid 1000 aparecen en el host con el uid del usuario (501): Docker Desktop traduce, no hace falta `chown`.
- **Lo que se monta además.** El remoto del experimento (`<raíz>/remote`) solo existe por ser local; en producción el remoto es GitHub. La carpeta `.git` montada en escritura expone al agente todos los refs y la configuración del clon (también las ramas de otras épicas); es el costo de que `git commit` desde un worktree funcione. Un reviewer con checkout separado ([spec](../specs/autonomous-orchestrator.md)) necesita su propio worktree y el mismo montaje.

## 2. Claude y Codex ejecutan Git dentro del contenedor

**Cómo se probó.** No hay credenciales de modelo disponibles de forma segura, así que los CLI apuntan a un modelo simulado ([`mock-llm.mjs`](spike-agent-containers/mock-llm.mjs)) que habla la API de Anthropic (`ANTHROPIC_BASE_URL`) y la de OpenAI (proveedor `mock` en `config.toml` de Codex). Si el prompt trae `GITFLOW:<comando>`, el simulado responde con una llamada a la herramienta de shell del CLI (`Bash` en Claude, `exec_command` en Codex); luego responde `DONE`. Lo que se prueba es lo que importa al spike: el CLI real, en Linux, ejecutando comandos Git reales por su propia herramienta contra el montaje. **No** prueba el login ni el comportamiento de un modelo real.

Claude (`stream-json`, recortado):

```
$ docker run --rm -u 1000:1000 -e CLAUDE_CONFIG_DIR=/state/claude -e ANTHROPIC_BASE_URL=http://host.docker.internal:18080 -e ANTHROPIC_API_KEY=sk-ant-mock-not-real \
    -v <estado>:/state -v <clon>/.git:<clon>/.git -v <worktree>:<worktree> -v <raiz>/remote:<raiz>/remote -w <worktree> carrier-spike6:base \
    claude -p 'GITFLOW:git status -sb && ... git commit ... && git push origin HEAD && git worktree list' --permission-mode bypassPermissions --output-format stream-json --verbose --model haiku </dev/null
TOOL_RESULT ## feat/demo/epic
To <raiz>/remote/demo.git
 * [new branch]      HEAD -> feat/demo/epic
<raiz>/repos/acme/demo           e037b92 [main]
<raiz>/worktrees/demo/feat-demo  fdd6153 [feat/demo/epic]
RESULT DONE false
```

Codex (`--json`, evento `command_execution` con `exit_code: 0`): mismo flujo, push a `feat/demo/codex`, `git worktree list` adentro con el worktree en `0d69e89`.

Afuera, después de los dos contenedores: `git log` del worktree muestra los commits de los dos agentes (`fdd6153`, `0d69e89`), `git worktree list` los muestra en esos SHA, y `git branch -a` del remoto bare lista `feat/demo/epic` y `feat/demo/codex`. Los commits hechos adentro son visibles afuera sin copiar nada.

Condiciones de cada CLI en contenedor:

- **Codex: su sandbox propio no funciona dentro del contenedor.** Con `--sandbox workspace-write` el comando falla: `bwrap: No permissions to create a new namespace, likely because the kernel does not allow non-privileged user namespaces` (`exit_code: 1`). Con `--sandbox danger-full-access` corre. Es coherente con el ADR: el límite es el contenedor, no el sandbox del CLI. El adaptador debe pasar `danger-full-access` (o `-c 'sandbox_mode="danger-full-access"'` en `exec resume`). No se probó hacer funcionar `bwrap` con capacidades extra: sería ampliar privilegios del contenedor sin necesidad.
- **Claude: no corre `bypassPermissions` como root.** Como uid 0 imprime `--dangerously-skip-permissions cannot be used with root/sudo privileges for security reasons`. Corriendo como `-u 1000:1000` funciona sin más. Con uid 0 y `IS_SANDBOX=1` también corre, pero es mejor no usar root.
- Claude no necesitó ajustes de sandbox: su herramienta `Bash` corrió el flujo Git completo con `bypassPermissions`.
- Ambos se lanzan con stdin cerrado (`</dev/null`), como en el [spike headless](headless-agents.md).

## 3. Sesiones y login

Con el estado de cada CLI en una carpeta del host montada como `CLAUDE_CONFIG_DIR` / `CODEX_HOME`, la sesión sobrevive a destruir el contenedor.

| | Claude | Codex |
|---|---|---|
| Dónde queda en el host | `<estado>/claude/projects/<cwd con / y . como ->/<session_id>.jsonl` (p. ej. `.../projects/-private-tmp-carrier-spike6-solve-worktrees-demo-feat-demo/5e3af7a0-...jsonl`) | `<estado>/codex/sessions/AAAA/MM/DD/rollout-<fecha>-<thread_id>.jsonl` |
| Retomar en un contenedor nuevo | `claude -p "<prompt>" --resume <id> ...` | `codex exec resume <id> "<prompt>" -c 'sandbox_mode="danger-full-access"' ...` |

Evidencia: el primer contenedor recibió «Remember the codeword TANGERINE-93»; se destruyó (`--rm`); un contenedor nuevo, con el mismo montaje, retomó la sesión y se le pidió `RECALL`. El modelo simulado devuelve `RECALLED:<códigos presentes en lo que recibió>`, así que lo que se prueba es que el CLI reconstruyó el historial desde el archivo persistido y se lo mandó al modelo:

```
claude --resume 5e3af7a0-...   (contenedor nuevo)  -> session_id 5e3af7a0-... (el mismo)  result "RECALLED:TANGERINE-93"
claude sin --resume            (control)           -> session_id nuevo                    result "RECALLED:NONE"
codex exec resume 01a14244-7792-... (contenedor nuevo) -> thread_id el mismo               agent_message "RECALLED:TANGERINE-93"
codex exec sin resume          (control)           -> thread_id nuevo                     agent_message "RECALLED:NONE"
```

Para el runner:

- **El `cwd` forma parte de la clave de Claude.** La carpeta de sesiones es el `cwd` con `/` y `.` como `-`; por eso las rutas del worktree deben ser las mismas entre contenedores (ya lo exige el punto 1). El [spike headless](headless-agents.md) vio que retomar desde otro `cwd` también funciona en el host; aquí no se repitió.
- **Un directorio de estado por ejecución o por agente de una épica, no uno global.** Evita que dos contenedores en paralelo escriban el mismo `.claude.json` o el mismo `auth.json`, y es lo que la [spec](../specs/autonomous-orchestrator.md) pide («sin mezclarlas con las de otra paralela»). Debe estar bajo la raíz compartida (`orchestrator/`), donde ya están los logs y las sesiones.
- **Login: no se puede montar `~/.claude*`.** En esta máquina el login de Claude no está en un archivo del directorio de configuración (`~/.claude-ashu-lab/.credentials.json` no existe); `security find-generic-password -s "Claude Code-credentials"` encuentra una entrada en el llavero de macOS, que un contenedor no ve. El login de Codex es el archivo `~/.codex/auth.json`, que sí se podría copiar, pero contiene tokens de refresco que se rotan: copiarlo a varias ejecuciones paralelas arriesga invalidar el original. Alternativas por probar con credenciales reales: `claude setup-token` («Set up a long-lived authentication token» según su ayuda) o `ANTHROPIC_API_KEY` para Claude, y `codex login --with-api-key` / `OPENAI_API_KEY` para Codex. Esto **no se verificó**: no se montó ni leyó ninguna credencial real. Es la decisión de producto más importante que deja el spike: qué tipo de credencial usa cada agente en el contenedor.

## 4. `gh` autenticado más de 70 minutos

**No verificado.** Requiere un repo de GitHub de prueba descartable y una identidad de bot de Forge, que todavía no existen (la slice #7 está pausada por eso), y no se improvisó ninguno.

Lo que sí se midió, con tokens falsos: el mecanismo de renovación por archivo. `GH_CONFIG_DIR` apunta a una carpeta montada **de solo lectura**; `gh` lee `hosts.yml` en cada invocación, así que si el proceso de afuera lo reescribe (con un `mv` atómico, y el montaje es de la carpeta, no del archivo) el contenedor ve el token nuevo sin reiniciarse:

```
before: ghs_FAKE_TOKEN_ONE
after host rewrite (same running container, ro mount): ghs_FAKE_TOKEN_TWO
GH_TOKEN env wins and is fixed per process: ghs_FAKE_ENV
sh: 1: cannot create /ghcfg/x: Read-only file system      (el agente no puede escribir ahí)
```

Consecuencias de diseño, para validar en el spike de Agent Forge:

- `GH_TOKEN` en el entorno **no sirve** para ejecuciones de hasta cuatro horas: es fijo por proceso y los tokens de instalación de una GitHub App duran una hora.
- Recomendado: un proceso afuera (Carrier, vía `agent-forge token`) renueva `hosts.yml` en esa carpeta antes de vencer, y `git` usa `gh auth setup-git` como credential helper para que el push también lea el token vigente en cada llamada. La alternativa es un proxy de credenciales fuera del contenedor, a costa de más piezas.
- Lo que cerraría el criterio: con el repo y el bot de la slice #7, una ejecución de más de 70 minutos que haga `gh auth status` y un push después del minuto 70, con la renovación corriendo desde afuera.

## 5. `pnpm test` y toolchains

```
$ docker run --rm -u 1000:1000 -e HOME=/home/node -v <repo>:/w -w /w carrier-spike6:base sh -c 'node -v && pnpm install && pnpm test'
v26.12.0
+ zod 4.6.7   Done in 799ms using pnpm v12.4.1
$ node --test     ✔ zod   ℹ tests 1  ℹ pass 1  ℹ fail 0
```

También `pnpm test` en el worktree de Solve montado (repo `demo`, `node --test`): pasa. pnpm 12 respeta el campo `packageManager` del repo.

Estrategia recomendada: **una imagen base común** (Node, pnpm, git, `gh` y los dos CLI) y, solo para el repo que lo necesite (otra versión de Node, Python, bases de datos, dependencias del sistema), una imagen derivada `FROM` la base declarada en la configuración del repo. La base cubre los repos Node/pnpm de AshuLab sin trabajo por repo; una imagen por repo desde el día uno duplicaría la instalación de los CLI y su actualización. No se probó una imagen derivada ni otro repo real.

Riesgos que el spike no midió:

- `pnpm test` creó `node_modules/` y `pnpm-lock.yaml` sin seguimiento dentro del worktree montado. Un `node_modules` instalado en el contenedor está compilado para Linux; si el mismo worktree se usa después desde macOS (Diego probando el PR), las dependencias nativas (p. ej. `better-sqlite3`) fallarían. Convendría que el contenedor instale en su propio volumen o que Diego reinstale.
- Los tests de repos que necesiten servicios (base de datos, navegador) no se probaron.

## 6. Salidas de red

Se midió desde contenedores en una red `--internal` (sin ruta a internet) y un proxy propio ([`proxy.mjs`](spike-agent-containers/proxy.mjs), CONNECT con lista de permitidos) conectado a esa red y a una normal. Ambos CLI respetan `HTTPS_PROXY`. Sin proxy, desde la red interna: `curl https://api.github.com` falla (`000`); con el proxy: `200`.

Destinos observados en el proxy con **claves falsas** (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`), una pregunta mínima:

| Destino | Quién | Hace falta |
|---|---|---|
| `api.anthropic.com` | Claude (13 conexiones) | sí; con la clave falsa responde `Invalid API key`, es decir, llegó |
| `http-intake.logs.us5.datadoghq.com` | Claude | no: telemetría; denegada, Claude respondió igual. Con `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` no aparece y solo queda `api.anthropic.com` |
| `api.openai.com` | Codex (`wss://.../v1/responses`, 13 conexiones) | sí (modo clave de API) |
| `chatgpt.com`, `github.com`, `api.github.com` | Codex | no en modo clave: denegados, Codex siguió intentando solo con `api.openai.com`. `chatgpt.com` sí es el destino del login de ChatGPT |
| `api.github.com` | `gh`/`git` de la ejecución | sí: probado alcanzable por el proxy (`200`) |
| `registry.npmjs.org` | `pnpm install` | sí si el repo instala dependencias. La instalación del punto 5 corrió en la red normal; a través del proxy no se probó (con la lista restringida de abajo estaba denegado) |

Lista mínima propuesta, restringible: `api.anthropic.com` y/o `api.openai.com` según el proveedor del perfil, `github.com` y `api.github.com`, y el registry de paquetes del repo, más lo que haga falta para el login real (ver abajo). **Sí se puede restringir**: con `ALLOW=api.anthropic.com,api.openai.com`, Claude y Codex funcionaron igual y el proxy registró `DENY` para Datadog, `chatgpt.com`, `github.com`, `api.github.com`; `curl https://example.com` desde la red interna falló. Un contenedor en una red `--internal` más un proxy con lista es la forma de aplicarlo; la regla la aplica la red, no `HTTPS_PROXY`: un agente que ignore la variable no tiene ruta directa a internet.

Pendiente: con login real, Claude (OAuth) y Codex (ChatGPT) usan además hosts de autenticación (`claude.ai`, `platform.claude.com`, `auth.openai.com` según su documentación) que no se observaron aquí. Observar la lista con credenciales reales antes de fijarla en la configuración. No se probó si `pnpm install` o `gh` funcionan completos a través del proxy.

## 7. Detener el contenedor

Prueba: Claude y Codex dentro de un contenedor ejecutan por su herramienta de shell un árbol que incluye hijos, nietos y un proceso que se sale del grupo (`setsid nohup`):

```
sleep 300 & setsid nohup sleep 301 >/dev/null 2>&1 & sh -c 'sleep 302 & sleep 303 & wait' & sleep 304
```

Árbol dentro del contenedor antes de matar (`docker exec ps`, Codex, 8 s después de empezar):

```
  PID  PPID  PGID STAT  COMMAND
    1     0     1 Ssl   node /usr/local/bin/codex exec GITFLOW:sleep 300 & setsid ...
   14     1     1 Sl    .../codex-linux-arm64/vendor/a...
  114    14   114 Ss    /bin/bash -c sleep 300 & setsid nohup sleep 301 ...
  115   114   114 S     sleep 300
  116   114   116 Ss    sleep 301          <- setsid: otro grupo
  117   114   114 S     sh -c sleep 302 & sleep 303 & wait
  118   114   114 S     sleep 304
  119   117   114 S     sleep 302
  120   117   114 S     sleep 303
```

El de Claude fue equivalente (`claude` PID 1 → `bash` → 3 `sleep` y un `sh` con 2 nietos; el `sleep 301` de `setsid` con `ppid` 1).

Resultado de `docker kill` (SIGKILL), medido con `time.time()` de Python alrededor de la llamada:

| Agente | `docker kill` | Estado | Procesos que quedan |
|---|---|---|---|
| Claude | 0,09 s | `Exited (137)` | ninguno |
| Codex | 0,09 s | `Exited (137)` | ninguno |

«Ningún proceso» se comprobó con `docker run --rm --pid=host carrier-spike6:base ps -eo pid,ppid,args | grep -E 'sleep 30|claude|codex'` (ve los procesos de toda la VM): sin coincidencias (`exit 1` de `grep`). Control positivo: con un contenedor `sleep 305` vivo, ese mismo comando sí lo lista (`13690 13666 sleep 305`).

`docker stop` (SIGTERM, 10 s de plazo), mismo árbol:

| Agente | `--init` | Tiempo | Código de salida | Huérfanos |
|---|---|---|---|---|
| Claude | no | 1,68 s | 143 | ninguno |
| Claude | sí | 0,26 s | 143 | ninguno |
| Codex | no | 0,15 s | 0 | ninguno |
| Codex | sí | 0,14 s | 0 | ninguno |

Esto cierra el supuesto del [spike headless](headless-agents.md) («matar el contenedor termina todos los procesos»): en el host Codex deja huérfano el comando incluso con `SIGTERM`; dentro del contenedor no queda nada, ni con el proceso fuera del grupo. `docker kill` es suficiente para `Ctrl+C`; `docker stop` da al CLI la oportunidad de cerrar su sesión. Recomendado `--init` para reapear procesos zombi (reduce el `stop` de Claude de 1,68 s a 0,26 s).

## Impacto en la spec y el ADR

Ningún resultado contradice el ADR 0003: los montajes coherentes, la sesión persistente y la detención por contenedor funcionan como asume. Cambia el detalle de cómo, y la spec recibe un párrafo breve de resultado en la pregunta abierta «Agentes en contenedores» con las condiciones del runner y lo que falta. No se comentó en la épica #3 porque el veredicto no es «no viable»; lo pendiente (credenciales reales y renovación de token) depende de la slice #7 y se informa en el informe de esta slice.

## Sin verificar y qué lo cerraría

| Pendiente | Qué lo cerraría |
|---|---|
| Claude y Codex autenticados de verdad dentro del contenedor (qué credencial, cómo se inyecta, que un modelo real use la herramienta de shell sin interacción) | Decidir el tipo de credencial (clave de API, `setup-token`, `auth.json`) y correr un prompt mínimo real en el contenedor con una credencial descartable |
| Push a un repo de GitHub de prueba desde cada CLI en contenedor | El repo descartable y la identidad de bot de Forge de la slice #7; repetir el flujo del punto 2 con remoto GitHub |
| `gh` autenticado más de 70 minutos con renovación | Lo mismo, más una ejecución de más de 70 minutos con renovación de `hosts.yml` desde afuera (punto 4) |
| Lista de red con login real | Observar el proxy con login real de Claude y Codex y fijarla en la configuración |
| OrbStack y Colima | Instalarlos y repetir los puntos 1, 2 y 7; solo si Docker Desktop no sirve por licencia o recursos |
| `node_modules` Linux vs macOS; tests con servicios; imagen derivada por repo | Un repo real de AshuLab con sus dependencias nativas |
| Ejecuciones de cuatro horas y varios contenedores en paralelo | Prueba de carga con el límite de memoria de la VM |

## Limitaciones

- El modelo era simulado: la sesión, las herramientas y el montaje son reales, pero no hay evidencia de cómo se comportan Claude y Codex con credenciales y modelo reales en el contenedor.
- Una sola corrida por caso, en una sola máquina (macOS 27.0, arm64, Docker Desktop 4.95.0). Solo se probaron `claude` 2.1.301 y `codex` 0.153.4.
- Remoto Git local, no GitHub: no se probó autenticación HTTPS, `gh` contra la API ni branch protection.
- Se limpió todo lo creado: contenedores, redes, imágenes, el simulador y la carpeta temporal. Las imágenes que ya existían en Docker no se tocaron.
