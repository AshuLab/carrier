# 0003 - Los agentes corren aislados en contenedores

- Status: superseded by [0004](0004-agentes-en-el-host-con-preferencias-de-la-terminal.md)
- Date: 2026-10-15

## Context

Los agentes de Carrier trabajan sin supervisión durante horas y necesitan permisos amplios para ejecutar `ship`, tests y comandos del repo sin esperar aprobaciones. Si corren en el sistema de Diego con sus permisos, un error o una instrucción maliciosa en un repo puede tocar archivos, credenciales y otros repos de su máquina, y nadie está mirando para frenarlo.

## Decision

Cada ejecución de agente corre dentro de un contenedor, con permisos amplios dentro y sin acceso al resto del sistema. Solo se montan el workspace de la épica, lo necesario para que Git funcione y las sesiones del agente. El token de GitHub de la ejecución tiene los scopes mínimos de su rol y los repos configuran branch protection como segundo límite, porque el contenedor no limita lo que el agente puede hacer en GitHub con ese token. Carrier no ejecuta agentes directamente en el host.

## Alternatives considered

Ejecutar en el host con permisos restringidos del CLI. Se descartó porque deja a un agente desatendido corriendo con los permisos del sistema donde corre, y la restricción depende de cada CLI.

Usar el sandbox nativo de Claude Code y Codex sobre el host. Se descartó como límite principal: aísla menos que un contenedor, difiere entre proveedores y sigue compartiendo el sistema de archivos del host. Queda como alternativa si el spike de contenedores no es viable.

## Consequences

Se gana un daño máximo acotado a los workspaces y una detención simple: matar el contenedor alcanza a los procesos hijos. Se acepta una dependencia de un runtime de contenedores en macOS, que corre en una VM Linux, y trabajo extra: montar worktrees y clon en rutas coherentes, mantener el login de Claude y Codex y sus sesiones dentro, renovar el token de Forge durante ejecuciones largas y proveer toolchains para los tests de cada repo. El diseño depende de que el spike de contenedores confirme que todo esto funciona; si no, Diego decide entre las alternativas.
