# Agent Forge como proveedor de identidad (spike #7)

Fecha: 15/10/2026 (las marcas UTC de abajo ya son 16/10). Entorno: macOS, Node v25.6.0, `gh` 2.102.0. Se ejecutó solo `agent-forge` y `gh`; no se corrió código del repo.

Resultado: todos los criterios de aceptación tienen evidencia, con una salvedad declarada en [Lo que no se observó](#lo-que-no-se-observó) (perfil realmente revocado o instalación desinstalada: se observó solo el análogo seguro).

## Versión de Forge usada

```
$ agent-forge --version
0.8.0
```

Instalado globalmente con pnpm (`@ashulab/agent-forge` 0.8.0). La investigación previa usó el commit `8dee1b0` del repo; este spike lee y ejecuta el `dist/launcher.cjs` instalado (0.8.0). Perfiles registrados (`agent-forge --list`): `artanis-agent` y `tassadar-agent`, dos GitHub Apps instaladas en dos cuentas (`AshuLab`, `vemec`). No se leyó `~/.config/agent-forge/agents.json` (contiene rutas a claves privadas); ningún token ni clave se imprimió, y los tokens de abajo están redactados.

## Cómo se invoca `gh` como bot

```
agent-forge gh <agente> <args de gh...>     # acuña un token fresco y ejecuta gh con GH_TOKEN/GITHUB_TOKEN
agent-forge token --agent <agente>          # imprime solo el token (stdout, sin salto de línea)
```

Reglas observadas:

- Debe invocarse con argv separado (`execFile`, `shell:false`). Pasado como un único string (`agent-forge "gh x --version"`) Forge cae al selector interactivo y sale con **exit 0** sin hacer nada.
- El **cwd importa**: las Apps están instaladas en 2 cuentas; sin `installationId` en el registro, Forge resuelve la instalación por el `origin` del cwd. Desde `/tmp` falló:
  ```
  exit=1  ■  GitHub App 4854138 is installed on 2 accounts (AshuLab, vemec). Launch from inside a repo under one of them.
  ```
  Desde un cwd con `origin` en `AshuLab/*` (el worktree de carrier) funcionó. El orquestador debe ejecutar Forge con `cwd` dentro de un clon del owner correcto; un cwd bajo `vemec` acuñaría un token de la instalación equivocada.
- El token queda acotado a la instalación: `GET /installation/repositories` con el token de cada bot lista 8 repos de `AshuLab`, incluido `AshuLab/agent-forge` (verificado antes de actuar).
- Permisos acuñados (línea en stderr `minted fresh token for ... · scope: ...`): `artanis-agent` = `issues:write contents:write pull_requests:write checks:read actions:read statuses:read metadata:read issue_fields:write issue_types:write organization_projects:write`; `tassadar-agent` = lo mismo sin los tres últimos. Ambos pueden escribir issues, labels, contenido y PRs.
- Forge añade esa línea propia a stderr, así que el stderr de `gh` no llega limpio.

## Evidencia: `gh` como bot en un repo de prueba

Repo de prueba: `AshuLab/agent-forge` (uso autorizado explícitamente por Diego). Huella: un issue, un label temporal y una rama; ver [Huellas](#huellas-en-ashulabagent-forge).

Issue creado por el bot autor (`artanis-agent`):

```
$ agent-forge gh artanis-agent issue create --repo AshuLab/agent-forge --title "[carrier spike] forge identity test - safe to close" --body "..."
exit=0   stdout: https://github.com/AshuLab/agent-forge/issues/27
$ agent-forge gh artanis-agent issue view 27 --repo AshuLab/agent-forge --json author,...
author: "app/artanis-agent"  (is_bot: true)
```

Label y comentario (el comentario lo hace el segundo bot, `tassadar-agent`):

```
$ agent-forge gh artanis-agent label create carrier-spike-tmp --repo AshuLab/agent-forge ...   exit=0
$ agent-forge gh tassadar-agent issue comment 27 --repo AshuLab/agent-forge --body "..."
exit=0   stdout: https://github.com/AshuLab/agent-forge/issues/27#issuecomment-6205875110
  (autor del comentario: tassadar-agent)
```

Commit con autoría del bot, en la rama `spike/carrier-forge-20261016012437` (sin PR; `main` siguió en `8dee1b0` antes y después):

```
git clone --depth 1 https://github.com/AshuLab/agent-forge.git /tmp/spike/clone
git checkout -b spike/carrier-forge-20261016012437
GIT_AUTHOR_NAME="artanis-agent[bot]" GIT_AUTHOR_EMAIL="325794106+artanis-agent[bot]@users.noreply.github.com" \
GIT_COMMITTER_NAME=... GIT_COMMITTER_EMAIL=... git commit -m "chore: carrier spike forge identity test (throwaway)"
git -c credential.helper='!f() { echo username=x-access-token; echo password=$GH_TOKEN; }; f' push origin HEAD:refs/heads/spike/...
exit=0   * [new branch] HEAD -> spike/carrier-forge-20261016012437
$ gh api repos/AshuLab/agent-forge/commits/5957170...
author_login: artanis-agent[bot]  author_type: Bot  committer_login: artanis-agent[bot]  parent: 8dee1b0
```

(`GH_TOKEN` salió de `agent-forge token --agent artanis-agent` y nunca se imprimió.)

Hallazgo importante: **el token de Forge solo da permiso de push; no fija la autoría**. Forge exporta `GIT_AUTHOR_*`/`GIT_COMMITTER_*` únicamente en el modo interactivo `launchAgent`; los subcomandos `gh` y `token` no lo hacen. El runner debe fijar él mismo, por ejecución, `GIT_AUTHOR_NAME=<agente>[bot]` y `GIT_AUTHOR_EMAIL=<botId>+<agente>[bot]@users.noreply.github.com` (y los de committer). Forge calcula `botId` con `GET /users/<agente>[bot]` (endpoint público; `artanis-agent[bot]` = 325794106); si el agente tiene `botName` o `botId` en el registro, usa esos. El commit no queda firmado (`verification.verified: false`).

## Evidencia: perfil del orquestador (`gh issue list --label ... --json ...` y cambio de labels)

Orquestador = `artanis-agent` (el `author-bot` del spec):

```
$ agent-forge gh artanis-agent issue edit 27 --repo AshuLab/agent-forge --add-label carrier-spike-tmp      exit=0
$ agent-forge gh artanis-agent issue list --repo AshuLab/agent-forge --label carrier-spike-tmp --state all --json number,labels
  (+0 s)  []
  (+3 s)  [{"labels":["carrier-spike-tmp"],"number":27}]       (idem a +8 s y +15 s)
$ agent-forge gh artanis-agent issue edit 27 --repo AshuLab/agent-forge --remove-label carrier-spike-tmp   exit=0
$ agent-forge gh artanis-agent issue list ... --label carrier-spike-tmp --json number
  (+5 s)  []
```

Todo con exit 0. Hallazgo: `issue list --label` es **eventualmente consistente**: inmediatamente después de cambiar un label devolvió el estado anterior (lo vimos tras agregar y tras quitar); unos 3 s después ya era correcto. El motor no debe asumir lectura-tras-escritura en `list`; para confirmar un cambio propio hay que leer con `gh issue view --json labels` (devolvió el estado correcto) o tolerar un ciclo de polling.

## Perfil personal de Diego: no soportado por Forge

Forge tiene un solo camino de credenciales: tokens de instalación de GitHub App (`generateGithubAppToken`: JWT RS256 con la clave de la App, luego `POST /app/installations/{id}/access_tokens`). No existe modo "usuario"; no hay PAT ni OAuth de usuario. `--help` solo ofrece `token --agent` y `gh <agent>`, ambos sobre Apps. Por eso una identidad personal no puede salir de Forge y no se intentó actuar como Diego. La cuenta personal es el login propio de `gh` (`gh auth status`: cuenta `vemec`, token en keyring) y se usa llamando a `gh` directo, sin Forge. Un token de bot no actúa como persona (los autores figuran como `app/...`) ni tiene los permisos de una persona (p. ej. proyectos de usuario).

## Renovación de token

No hay caché ni estado: cada `agent-forge token` y cada `agent-forge gh` firman un JWT nuevo y acuñan un token de instalación nuevo (dura ~1 h según GitHub). Renovar = volver a llamar. Prueba (tokens identificados por los 8 primeros hex del sha256, no por valor):

```
token#1 exit 0 sha256[:8] 55eabaf5   token#2 exit 0 sha256[:8] 91a8de2e   different: true
GET /rate_limit con #1 -> exit 0     GET /rate_limit con #2 -> exit 0
DELETE /installation/token con #1 (revoca solo ese token efímero; no la App ni la instalación) -> 204
#1 muerto: gh api /installation/repositories        -> exit 1  {"message":"Bad credentials","status":"401"}  gh: Bad credentials (HTTP 401)
#1 muerto: gh issue list --repo AshuLab/agent-forge -> exit 1  HTTP 401: Bad credentials (https://api.github.com/graphql)
#2 sigue válido -> exit 0 (8 repos)
token#3 (renovación, con #1 ya muerto) exit 0 sha256[:8] 1379ab24 -> GET /installation/repositories exit 0 (8 repos)
```

No se esperó la hora real: el vencimiento se simuló revocando el token (GitHub responde 401 `Bad credentials` igual a un token vencido o revocado) y una nueva llamada devolvió un token válido. Los tokens #2, #3 y otro de prueba se revocaron al terminar; los demás vencen solos.

Consecuencias para el runner: un proceso al que se le inyectó `GH_TOKEN` no se renueva solo. Para ejecuciones de hasta 4 h, `gh` debe invocarse siempre vía `agent-forge gh` (token fresco por llamada); para procesos de larga vida (agente en contenedor) el adaptador debe reacuñar con `agent-forge token --agent` antes de ~1 h (p. ej. cada ~45 min) y reinyectar el token. Reacuñar crea un token independiente; no invalida los anteriores.

## Forma observable de los errores (para derivar `AuthError`)

Los errores propios de Forge salen por el mismo `main().catch`: **exit 1**, stdout vacío, stderr `│` + salto + `■  <mensaje>`. Lo de `gh` se propaga con su propio código, normalmente 1, así que el exit code por sí solo no distingue; hay que clasificar por stderr.

| Caso | Cómo se obtuvo | exit | stderr (tras `■  `) |
|---|---|---|---|
| Perfil inexistente en Forge | real: `agent-forge gh no-such-agent-xyz --version` y `token --agent no-such-agent-xyz` | 1 | `Agent not found: no-such-agent-xyz` |
| Clave privada no encontrada | `AGENT_FORGE_CONFIG` temporal con `privateKeyPath` inexistente | 1 | `Private key for "<agente>" not found or unreadable: <ruta>` |
| Clave que no pertenece a la App (análogo de clave revocada/eliminada) | `AGENT_FORGE_CONFIG` temporal: `appId` real, clave RSA recién generada | 1 | `GitHub API /app/installations: 401 A JSON web token could not be decoded — the App JWT was rejected. Check that appId matches privateKeyPath ...` |
| Varias instalaciones y cwd sin repo del owner | real, desde `/tmp` | 1 | `GitHub App <id> is installed on 2 accounts (AshuLab, vemec). Launch from inside a repo under one of them.` (cwd/config, no auth) |
| Uso incorrecto | real: `agent-forge gh no-such-agent-xyz` | 1 | `Usage: agent-forge gh <agent-name> <gh args...>` |
| Token acuñado vencido o revocado, usado por `gh` | real (token revocado) | 1 | `gh: Bad credentials (HTTP 401)` / `HTTP 401: Bad credentials (https://api.github.com/graphql)` |

Las simulaciones apuntaron `AGENT_FORGE_CONFIG` a un archivo temporal con perfiles falsos: no se tocó el registro real, no se creó ninguna App ni bot, y la clave de prueba se borró.

Regla de clasificación sugerida (validar en el adaptador con fixtures de estos mensajes):

- `AuthError` (detiene las épicas del perfil): `Agent not found:`, `Private key for ... not found or unreadable`, `GitHub API ...: 401` con "App JWT was rejected", `GitHub App ... has no installations` (leído en el código, no observado), `Bad credentials`/`HTTP 401` de `gh`.
- No `AuthError`: `installed on N accounts` (error de cwd/configuración del adaptador), `Usage:`, 404/422 de recursos (error normal de la operación).
- Todos son exit 1: se parsea stderr, no el código. Un `Bad credentials` de `gh` puede ser un token vencido a mitad de ejecución: conviene reacuñar una vez y reintentar antes de declarar `AuthError`.

## Lo que no se observó

- Un perfil **realmente revocado** (instalación desinstalada/suspendida o clave eliminada en la App): no se revoca nada real. Se observó el análogo seguro (clave que no pertenece a la App → 401) y el mensaje de "sin instalaciones" está leído en el código, no observado. Lo cerraría un bot de prueba descartable que Diego pueda desinstalar y reinstalar, repitiendo `agent-forge token --agent <bot>`.
- El tope real de 1 h del token: se toma de la documentación de GitHub; lo verificado es la renovación.

## Propuesta: forma de `profiles` y comando

```json
"profiles": {
  "author-bot":   { "kind": "forge", "agent": "artanis-agent" },
  "reviewer-bot": { "kind": "forge", "agent": "tassadar-agent" },
  "diego":        { "kind": "gh" }
}
```

- `kind: "forge"`: bot vía Forge; `agent` es el nombre en el registro de Forge. Sin secretos en la config (las claves viven en el registro de Forge).
- `kind: "gh"`: login propio de `gh` (cuenta personal, que Forge no soporta); se ejecuta `gh` directo.

Comando exacto, argv separado y `cwd` dentro de un clon del owner correcto:

```ts
execFile("agent-forge", ["gh", profile.agent, ...ghArgs], { cwd, timeout: githubCallTimeoutSeconds * 1000 })
```

Para `kind: "gh"`: `execFile("gh", ghArgs, { cwd, timeout })`. Pasar siempre `--repo <owner>/<repo>` explícito. Para `git` como bot: `agent-forge token --agent <agente>`, exportar `GIT_AUTHOR_*`/`GIT_COMMITTER_*` como arriba y pasar el token al credential helper vía `GH_TOKEN`.

El spec se actualizó en este mismo PR (`docs/specs/autonomous-orchestrator.md`: ejemplo de `profiles` y la frase que decía que la forma se fijaba tras el spike). El esquema actual (`src/config/schema.ts`) acepta cada perfil como `z.looseObject({})`; endurecerlo a estas dos formas queda para la slice de configuración (este PR es solo documentación).

## Huellas en `AshuLab/agent-forge`

Eliminados: la rama `spike/carrier-forge-20261016012437` y el label `carrier-spike-tmp`. Verificado al final: `main` en `8dee1b0` (sin cambios), ramas = `["main"]`, labels = los 7 preexistentes (sin el temporal), sin PR.

Permanece: el issue #27 `[carrier spike] forge identity test - safe to close`, **cerrado** (`not planned`), con sus dos comentarios (uno de `tassadar-agent`, otro de cierre de `artanis-agent`) y su historial de eventos (label agregado y quitado); un issue no se puede borrar por API. Actores: solo `artanis-agent` y `tassadar-agent`. No se rotó, revocó ni eliminó ninguna credencial real; solo se revocaron tokens de instalación efímeros acuñados durante la prueba.
