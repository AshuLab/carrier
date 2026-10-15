# Glosario de Carrier

**Carrier** - Aplicación que descubre épicas listas y coordina agentes de implementación, revisión y corrección hasta dejar el PR final listo para probar o informar que requiere intervención. Agent Forge gestiona las identidades y su autenticación; Solve aporta los skills. El nombre se inspira en la nave de StarCraft que despliega múltiples interceptores.

**Listo para probar** - El PR final tiene revisión concluyente sin blockers y verificaciones del repo confirmadas por los agentes sobre el mismo commit. En un repo sin CI, alcanza con la revisión y evidencia de tests reportada por los skills, registrando esa ausencia. Diego todavía debe probarlo y decidir el merge.
_Avoid_: aprobado para merge, entregado, épica terminada.

**Reintento de ejecución** - Nueva ejecución tras un fallo técnico del proceso o infraestructura, después de comprobar sus efectos. No es una corrección de código ni una nueva revisión. El timeout del agente tiene su propia salida de intervención y no se reintenta automáticamente.
_Avoid_: reintento sin especificar qué falló.

**Corrección de tests/CI** - Trabajo interno del autor y sus skills para resolver verificaciones fallidas antes de reportar el estado de su ejecución. El orquestador no cuenta esos intentos ni agrega un loop para administrarlos.
_Avoid_: reintento de ejecución, contador de correcciones del orquestador.

**Agente caller** - Agente que invoca los skills, interpreta sus informes actuales y aplica las reglas del repo para trabajar como autor o reviewer. Entrega al orquestador una conclusión estructurada por ejecución.
_Avoid_: skill, orquestador al referirse al agente que interpreta los informes.

**Perfil GitHub** - Referencia configurada por el usuario a una identidad GitHub disponible y su mecanismo de autenticación. Se asigna al orquestador, autor o reviewer; es independiente del proveedor/modelo de IA y de la sesión de trabajo de un agente.
_Avoid_: modelo, sesión del agente, identidad de IA para una cuenta GitHub.

**Épica** - Issue `solve:epic` con spec y tickets preparados; la unidad que Carrier encola, ejecuta y entrega. Se identifica por repo e issue, porque distintos repos repiten números.
_Avoid_: feature, tarea, job.

**Etapa** - Tramo de una épica a cargo de un rol: implementación con `ship`, revisión o corrección. El orquestador combina la etapa con el resultado del caller para decidir el siguiente turno.
_Avoid_: paso, fase, estado de la épica.

**Ronda de revisión** - Cada revisión del PR final por el reviewer, numerada; el límite de cinco cuenta estas revisiones. Un fallo técnico de ejecución no consume una ronda.
_Avoid_: reintento, iteración.

**Ejecución** - Una invocación de un agente (autor o reviewer) con su sesión, límite de tiempo y resultado. Es la unidad del reintento técnico y del timeout; no representa la duración de la épica.
_Avoid_: proceso (la terminación técnica es otra cosa), épica.

**Resultado del caller** - Conclusión estructurada de una ejecución, en JSON: `completed`, `changes_requested` o `needs_human`. Es independiente de que el proceso haya terminado bien o mal.
_Avoid_: éxito/fallo del proceso, estado del CLI.

**Intervención humana** - Estado de una épica detenida (`solve:epic:needs-human`) por `needs_human`, timeout, límite agotado, revisión inconclusa o error de autenticación. Diego la resuelve fuera de Carrier; no se reactiva desde la app ni al reiniciar.
_Avoid_: error, fallo, pausa.

**Autor** - Agente que invoca `ship` y atiende los findings; mantiene su identidad durante toda la épica.
_Avoid_: implementador, developer.

**Reviewer** - Agente con identidad distinta a la del autor que revisa el PR final en un checkout separado, publica findings y verifica las correcciones.
_Avoid_: revisor externo, bot de review.

**Raíz compartida** - Carpeta (por defecto `~/.solve/`) donde Solve y Carrier guardan `repos/`, `worktrees/` y `orchestrator/`. Es independiente de dónde vive el código de la app o desde dónde se la inicia.
_Avoid_: workspace (es el checkout de una épica, dentro de `worktrees/`).
