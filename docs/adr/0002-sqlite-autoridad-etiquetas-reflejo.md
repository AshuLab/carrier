# 0002 - SQLite es la autoridad del estado, las etiquetas son su reflejo

- Status: accepted
- Date: 2026-10-15

## Context

La etiqueta `solve:epic:ready` es la señal de entrada, y Diego quiere ver el estado de cada épica en GitHub. Pero Carrier se interrumpe con `Ctrl+C`, puede caerse entre publicar algo en GitHub y guardarlo, y GitHub puede estar caído o limitar las consultas. Una ejecución también necesita guardar sesión, ronda, SHA revisado e historial, que las etiquetas no pueden contener.

## Decision

SQLite es la fuente de verdad de cada ejecución. Las etiquetas `solve:epic:running`, `ready-for-test` y `needs-human` son su reflejo visible en GitHub y se reconcilian al arrancar y después de un fallo. `solve:epic:ready` basta para encolar una épica nueva, pero una ejecución ya registrada se retoma desde SQLite aunque el issue ya no tenga esa etiqueta. El resultado del caller y la transición de estado se guardan en una sola transacción y su importación es idempotente.

## Alternatives considered

Usar las etiquetas como único estado, sin persistencia propia. Se descartó porque no distingue una ejecución interrumpida de una detenida, no guarda sesiones ni rondas, depende de que GitHub responda y cualquiera puede editar una etiqueta.

Usar solo SQLite, sin etiquetas de estado. Se descartó porque Diego perdería visibilidad desde GitHub y porque `ready` ya es parte del contrato con Solve.

## Consequences

Escribir en dos lugares exige lógica de reconciliación y pruebas de recuperación para cada punto de corte entre GitHub y SQLite, en particular un JSON incompleto o un resultado publicado pero no importado. Una etiqueta cambiada a mano no altera una ejecución en curso; solo el cierre del issue o del PR y el merge del PR final tienen efecto, según las reglas del brief.
