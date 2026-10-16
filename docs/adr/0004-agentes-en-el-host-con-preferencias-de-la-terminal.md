# 0004 - Los agentes corren en el host con las preferencias de la terminal

- Status: accepted
- Date: 2026-10-15
- Supersedes: [0003](0003-agentes-en-contenedor.md)

## Context

[0003](0003-agentes-en-contenedor.md) fijó que cada ejecución de agente corre en un contenedor. El spike de contenedores ([investigación](../research/agent-containers.md)) lo encontró viable con condiciones, pero con un costo alto para esta primera versión: el login de Claude vive en el Keychain de macOS y no se puede montar, el `auth.json` de Codex no se puede copiar a corridas paralelas sin riesgo, el sandbox propio de Codex falla dentro del contenedor, Claude no acepta `bypassPermissions` como root, los worktrees exigen rutas idénticas al host y el token de `gh` hay que renovarlo desde afuera. Todo eso retrasa probar el flujo completo, que es el objetivo de esta versión.

## Decision

El orquestador corre en el sistema donde se invoca, y sus agentes (Claude y Codex) corren como procesos de ese mismo sistema, con el usuario, el entorno y las preferencias de la terminal desde la que se ejecuta `carrier`: login, configuración y permisos de cada CLI son los que ya tiene esa terminal. Carrier no define ni endurece el aislamiento en esta versión.

Cada ejecución se lanza como su propio grupo de procesos, para que `stop()` y `Ctrl+C` puedan terminar al agente y a todo su árbol de hijos (sin contenedor, Codex deja huérfano el proceso del comando incluso con `SIGTERM`). El token de GitHub de cada ejecución sigue teniendo los scopes mínimos de su rol y los repos mantienen branch protection como límite.

La seguridad de agentes desatendidos (AFK) queda como trabajo posterior y explícito: se revisará cómo acotar permisos y daño (usuario dedicado, sandbox nativo de los CLIs, contenedores u otra vía) con el flujo ya funcionando.

## Alternatives considered

Contenedores por ejecución ([0003](0003-agentes-en-contenedor.md)). Siguen siendo la opción con mejor aislamiento y detención simple (`docker kill` terminó todo el árbol en 0,09 s), pero el costo de credenciales y permisos descrito arriba se aplaza hasta tener el flujo completo. El spike queda como material de partida.

Sandbox nativo de Claude y Codex. Aísla menos y difiere entre proveedores; se evaluará junto con el resto de la seguridad AFK.

## Consequences

Se gana simplicidad: no hay runtime de contenedores, montajes, imágenes ni renovación externa de login, y las sesiones de los CLIs quedan donde ellos las guardan. Se acepta que un agente desatendido corra con los permisos del usuario y la terminal, y por tanto puede tocar archivos, credenciales y otros repos de esa máquina; es un riesgo asumido y temporal hasta definir la seguridad AFK. El runner debe invocar los binarios reales de `claude` y `codex`, no wrappers, y garantizar la detención del árbol de procesos por su cuenta.
