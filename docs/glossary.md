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
