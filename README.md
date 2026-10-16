# Carrier

Orquestador de épicas autónomas. Corre en tu máquina, mira una lista de repos GitHub y, por cada épica marcada `solve:epic:ready`, lanza a un agente autor (Claude o Codex) que ejecuta `ship` y a otro agente reviewer, con otra identidad, que revisa el PR final de integración. Cuando la revisión es concluyente deja la épica lista para que la pruebes y decidas el merge; Carrier nunca mergea el PR final.

> **Estado:** primera versión, solo macOS, pensada para uso personal. Los agentes corren como el CLI normal de `claude` y `codex` con **tus permisos** y sin aislamiento (ver [Seguridad](#seguridad)).

## Cómo funciona

1. Cada intervalo consulta los repos configurados y registra, en orden de llegada, las épicas con `solve:epic:ready`.
2. Con un slot libre toma la más antigua y cambia la etiqueta a `solve:epic:running`.
3. **Ship:** el autor ejecuta `ship` sobre la épica en un clon administrado y Carrier valida el PR final contra GitHub (existe, está abierto, referencia la épica, el head es el esperado).
4. **Review:** el reviewer, con otra identidad y un checkout separado, revisa el PR. Si pide cambios, el autor corrige y se vuelve a revisar hasta `maxReviews`.
5. La épica termina en `solve:epic:ready-for-test` (revisión completa sobre el head actual) o `solve:epic:needs-human` (con el motivo en la terminal). Carrier es dueño de esas tres etiquetas; `solve:epic:ready` es de Solve.

SQLite es la autoridad del estado y las etiquetas son su reflejo. Ante fallos técnicos (proceso caído, JSON ausente o inválido) reintenta con una ejecución nueva que verifica el estado real, sin duplicar PRs, comentarios ni commits. `Ctrl+C` detiene los agentes conservando sesiones y trabajo; al reiniciar se reconcilia con GitHub y se retoma.

## Requisitos

- macOS, Node 26 y pnpm 12.
- `git` y `gh`.
- Los CLIs `claude` y/o `codex` instalados y con sesión iniciada en esa terminal.
- [Agent Forge](https://github.com/AshuLab/agent-forge) para las identidades de los bots (GitHub Apps). Un perfil `gh` usa tu propio login de `gh`.
- Los repos configurados usan el flujo de [Solve](https://github.com/AshuLab/skills) (`ship`).

## Instalación

```sh
pnpm install
```

## Configuración

Un archivo JSON que se combina sobre los defaults (los objetos se combinan por campo, los valores simples reemplazan y las listas se reemplazan completas). Se valida al arrancar y cada error nombra el campo; autor y reviewer deben tener perfiles distintos.

```json
{
  "repos": [{ "name": "AshuLab/mi-repo", "agents": { "reviewer": { "model": "<modelo>" } } }],
  "profiles": {
    "author-bot": { "kind": "forge", "agent": "<agente-forge-1>" },
    "reviewer-bot": { "kind": "forge", "agent": "<agente-forge-2>" }
  },
  "orchestratorProfile": "author-bot",
  "agents": {
    "author": { "profile": "author-bot", "provider": "claude", "model": "<modelo>" },
    "reviewer": { "profile": "reviewer-bot", "provider": "codex", "model": "<modelo>" }
  }
}
```

Defaults: `root` `~/.solve`, `pollIntervalMinutes` 5, `logLevel` `info`, `limits` con `maxConcurrentEpics` 3, `maxReviews` 5, `maxExecutionRetries` 3, `maxExecutionHours` 4 (o `"unlimited"`) y `githubCallTimeoutSeconds` 30. Identidad, proveedor y modelo de autor y reviewer pueden sobrescribirse por repo. No hay credenciales en el archivo: cada perfil referencia a Forge (`{ "kind": "forge", "agent": ... }`) o a tu `gh` (`{ "kind": "gh" }`).

## Uso

```sh
node src/cli/main.ts --config ./carrier.config.json
```

Node 26 ejecuta el TypeScript directamente. El paquete declara el binario `carrier`, así que tras un `pnpm link --global` también sirve `carrier --config ./carrier.config.json`. Se puede ejecutar desde cualquier carpeta. Corre hasta `Ctrl+C` y muestra un panel con los slots, la cola y, por épica, etapa, ronda, blockers, tiempo en la etapa y última actividad (líneas simples si no hay terminal interactiva). Solo puede haber una instancia por carpeta raíz.

## Dónde guarda las cosas

Bajo `root` (por defecto `~/.solve/`), compartido con Solve:

- `repos/<org>/<repo>/`: clones administrados.
- `worktrees/<repo>/<feature>/`: workspaces que crea Solve; `reviews/<repo>/<épica>/`: checkout separado del reviewer.
- `orchestrator/`: `carrier.db` (SQLite), `logs/orchestrator.log` y `logs/executions/<id>/` con la salida de cada agente. Los logs y sesiones de una épica terminada o cancelada se borran a los 30 días; SQLite y los workspaces no se tocan.

## Seguridad

Los agentes desatendidos corren con tus permisos: Claude con los permisos saltados y Codex con `--dangerously-bypass-approvals-and-sandbox`, y pueden tocar archivos, credenciales y otros repos de la máquina. Carrier no añade aislamiento en esta versión ([ADR 0004](docs/adr/0004-agentes-en-el-host-con-preferencias-de-la-terminal.md)); córrelo en una máquina o usuario en el que lo aceptes. Los tokens de GitHub de cada ejecución tienen los scopes mínimos de su rol y los repos deberían tener branch protection. Además, sin contenedor detener un agente no garantiza terminar sus procesos hijos.

## Desarrollo

```sh
pnpm typecheck
pnpm test                # suite completa, sin red ni agentes reales
pnpm test:integration    # pruebas con herramientas reales, se saltan sin variables de entorno
pnpm db:generate         # nueva migración de Drizzle tras cambiar el esquema
```

Las pruebas de integración con GitHub, Claude, Codex y el end-to-end contra el repo de prueba `AshuLab/carrier-sandbox` se activan con variables `CARRIER_IT_*`, `CARRIER_TEST_*` y `CARRIER_E2E_*` (por ejemplo `CARRIER_E2E_REPO`, `CARRIER_E2E_AUTHOR_AGENT`, `CARRIER_E2E_REVIEWER_AGENT`); ver [`docs/research/e2e-findings.md`](docs/research/e2e-findings.md) y [`docs/research/sandbox-repo.md`](docs/research/sandbox-repo.md).

## Documentación

- [Spec](docs/specs/autonomous-orchestrator.md) y [glosario](docs/glossary.md).
- [ADRs](docs/adr/): coordinación y evaluación, SQLite como autoridad, y agentes en el host (reemplaza al ADR 0003 de contenedores).
- [Investigaciones](docs/research/): agentes headless, Agent Forge, logs y panel, raíz compartida, contenedores (descartado) y hallazgos del end-to-end.
