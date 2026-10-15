# Carrier — Orquestador de épicas autónomas

Status: sharpening

## Problem

Diego quiere dedicar tiempo a preparar varias ideas, specs y tickets con Solve mientras agentes implementan el trabajo ya preparado. Hoy necesita encadenar manualmente implementación, revisión externa y correcciones para llegar a un PR que pueda probar. El objetivo es delegar esa coordinación sin delegar su decisión de probar y mergear el PR final.

El resultado esperado es que una épica marcada `solve:epic:ready` entre en ejecución sin seguimiento manual entre turnos, termine con un PR final listo para probar o un motivo explícito de intervención, y pueda continuar tras interrumpir el proceso. Varias épicas pueden avanzar en paralelo dentro de una concurrencia configurada. Las definiciones y decisiones detalladas están en el [documento de trabajo](../autonomous-orchestrator.md) y el [glosario](../glossary.md).

## Direction

Construir una app independiente en TypeScript sobre Node.js 26, con ESM y pnpm, inicialmente para macOS. Seleccionar las últimas versiones estables de dependencias y tooling al implementar o actualizar y conservar las resoluciones en el lockfile. Se inicia desde cualquier carpeta, lee una lista de repos GitHub y permanece corriendo con un panel informativo en la misma terminal. Se eligió este alcance para probar el flujo antes de invertir en una UI web o app del OS.

Diego decidió construir el alcance completo descrito abajo: catálogo de n identidades, overrides por repo, retención de logs y tiempo `unlimited`. Se evaluó recortarlo a dos identidades fijas y configuración global para validar el flujo antes, y se descartó. Los términos están en el [glosario](../glossary.md).

Se permite una sola instancia activa por carpeta de datos del orquestador, protegida con un bloqueo exclusivo antes de iniciar trabajo. Una segunda instancia informa que ya está corriendo y termina. El bloqueo debe permitir volver a arrancar tras un cierre inesperado sin habilitar dos procesos simultáneos sobre la misma carpeta.

Si GitHub está caído o limita las consultas, se conserva la cola y el estado, se muestra el error y se vuelve a consultar en el siguiente intervalo configurado, respetando una espera mayor indicada por GitHub. Estos errores de consulta no consumen reintentos del agente.

Solve agrega `solve:epic:ready` al completar su preparación; ese cambio se hace en sus skills, fuera de esta app. La etiqueta es suficiente para encolar una épica. El orquestador consulta todos los repos configurados, registra nuevas épicas en SQLite y las toma por orden de ingreso a la cola. Las consultas periódicas a GitHub tienen un intervalo fijo configurable, de 5 minutos por defecto, incluida la espera antes de la primera consulta al arrancar. No se usan webhooks ni intervalos adaptativos. El loop entre agentes avanza al recibir sus resultados, sin esperar ese intervalo. Al iniciar una ejecución, cambia ready por `solve:epic:running`. Al terminar, la reemplaza por `solve:epic:ready-for-test` o `solve:epic:needs-human`. SQLite es la autoridad del estado y las etiquetas son su reflejo, que se reconcilia al arrancar y tras un fallo; una ejecución registrada se retoma sin depender de que el issue siga ready. Ver [ADR 0002](../adr/0002-sqlite-autoridad-etiquetas-reflejo.md).

El orquestador coordina un autor que invoca `ship`, un reviewer con otra identidad que revisa y publica findings sobre el PR final de integración, y nuevos turnos del autor para corregir o responder. El reviewer verifica los resultados y vuelve a revisar. Los skills conservan sus informes actuales y Diego adapta sus aprobaciones para invocación autónoma. El caller interpreta esos informes y entrega un archivo JSON estructurado por ejecución; el motor valida su contrato y coherencia técnica y persiste el resultado junto con la transición de estado en SQLite. Se usan esquemas Zod para configuración y resultados del caller, con tipos TypeScript inferidos desde los mismos contratos; los campos exactos del JSON se fijan en el spec. Se conservan informes, evidencia, PR, SHA e historial.

Los resultados del caller son `completed`, `changes_requested` y `needs_human`. `completed` del autor habilita revisión y `completed` del reviewer habilita listo para probar; `changes_requested` es la conclusión del reviewer que devuelve el turno al autor mientras queden rondas; `needs_human` detiene el trabajo automático de la épica con el motivo. La terminación técnica del proceso y los errores de transporte/validación del JSON se manejan por separado.

Si el PR final de integración fue mergeado mientras aún hay trabajo activo, detener las ejecuciones de esa épica, conservar sesiones e historial y no lanzar otros turnos. Los merges de slices realizados por `ship` no disparan esta regla. Las demás épicas continúan.

Cerrar manualmente el issue de la épica o su PR final sin merge cancela su trabajo: se detienen sus agentes, no se lanzan nuevos turnos y se conserva lo realizado, mostrando el motivo en terminal. Las demás épicas continúan. La cancelación inicia la retención de 30 días para logs y sesiones. Los cierres de slices de `ship` no disparan esta regla.

Autor y reviewer aplican las reglas del repo para seleccionar y evaluar tests, CI y blockers. Se descartó incorporar esa política al orquestador: su responsabilidad es administrar etapas, límites, procesos y persistencia. Ver [ADR 0001](../adr/0001-separar-coordinacion-y-evaluacion-del-repo.md). Listo para probar requiere review concluyente sin blockers y verificaciones del repo confirmadas por los agentes sobre el mismo commit. En repos sin CI alcanza la revisión y evidencia de tests reportada por los skills, registrando esa ausencia. Diego todavía prueba y decide el merge.

Los valores iniciales configurables son tres épicas simultáneas, cinco reviews, tres reintentos por fallos de ejecución y cuatro horas por ejecución de agente. El tiempo admite `unlimited`; cero no significa infinito. Un timeout, una revisión inconclusa por falta de contexto o un límite agotado termina en intervención humana. Las correcciones y repeticiones de tests/CI pertenecen al trabajo interno de los agentes y skills: el motor recibe la conclusión final y no agrega un contador ni un loop para esos intentos. Las épicas que requieren intervención quedan detenidas mientras otras avanzan; en esta versión Diego resuelve esos casos fuera del orquestador.

Los agentes no corren con los permisos del sistema anfitrión: cada ejecución va dentro de un contenedor, con permisos amplios adentro y solo el workspace de la épica, lo necesario para Git y las sesiones montados. El contenedor no limita lo que el agente hace en GitHub con su token, por lo que los scopes mínimos por rol y la branch protection de los repos son el segundo límite. Se descartaron los permisos restringidos del CLI sobre el host y el sandbox nativo de los CLIs como límite principal. Ver [ADR 0003](../adr/0003-agentes-en-contenedor.md).

Los proveedores iniciales son Claude y Codex. La app incluye una configuración default y admite un archivo JSON del usuario que la sobrescribe: objetos se combinan por campo, valores simples del usuario reemplazan defaults y listas se reemplazan completas. La configuración resultante se valida al arrancar. Admite un catálogo de n identidades, incluida la personal de Diego, y asignación explícita por rol. Identidad, proveedor y modelo tienen defaults globales y overrides por repo. Cada épica conserva la configuración efectiva con la que inició, incluso al retomar. Agent Forge es una dependencia externa instalada para preparar identidades y credenciales GitHub; el runner propio ejecuta las tareas.

El usuario configura los perfiles GitHub disponibles y selecciona también el que utilizará el orquestador para leer issues y actualizar etiquetas. Puede reutilizar uno de los perfiles de agentes o elegir otro; la asignación es explícita y Agent Forge se encarga de la autenticación. No se persisten credenciales en las ejecuciones. Un error de autenticación informado por Forge detiene las épicas afectadas y se muestra en terminal; las demás continúan. Si falla el perfil del orquestador, se suspenden sus operaciones GitHub dependientes. No se cambia de perfil automáticamente.

Solve y la app comparten una raíz configurable, por defecto `~/.solve/`: `repos/` para clones, `worktrees/` para workspaces que administra Solve y `orchestrator/` para SQLite, sesiones y logs. Se eligió compartir las rutas para reutilizar el trabajo de Solve en vez de crear otra estructura de worktrees de implementación. El reviewer usa un checkout separado. La ubicación del código de la app es independiente de esa raíz de ejecución.

La persistencia SQLite usa Drizzle ORM con el driver `better-sqlite3` para el esquema y acceso a datos y Drizzle Kit para generar migraciones versionadas. Se mantiene la política de últimas versiones estables y se valida compatibilidad con Node 26 en macOS.

Los tests de la app usan Vitest para verificar cola, transiciones, persistencia y recuperación con agentes simulados. Las pruebas con Claude/Codex reales forman una integración aparte, con un repo de prueba y configuración explícita.

Los logs y sesiones de una épica se borran automáticamente 30 días después de que termina. Mientras la épica siga pendiente, se conservan para permitir retomarla, también si fue interrumpida o requiere intervención. Esta limpieza no elimina los registros de la épica en SQLite ni sus workspaces.

La app usa `@ashulab/universal-logger` como dependencia runtime para información, warnings y errores, mediante imports de su API. Se reutilizan su implementación, niveles y representación de errores; no se construye un logger propio en su reemplazo. La integración central configura la biblioteca y añade contexto de ejecución. Los logs quedan bajo la raíz configurable, en `orchestrator/logs/`, separados del estado SQLite y de la presentación del panel. Los detalles de API y capacidades observadas están en el [documento técnico](../autonomous-orchestrator.md#logging-y-errores).

`Ctrl+C` detiene las ejecuciones activas sin esperar a que terminen sus etapas. Se conservan sesiones, contexto, workspaces y trabajo sin commit. Al reiniciar, se reconcilian procesos y efectos externos antes de continuar; una etapa interrumpida no se vuelve a empezar ciegamente. Si una sesión no se puede recuperar, se reconstruye su contexto en una nueva con la misma identidad y el agente verifica el estado real antes de continuar. Una épica detenida por intervención no se reactiva automáticamente al reiniciar.

Si un repo fue quitado de la configuración, al reiniciar sus épicas pendientes quedan detenidas con el motivo registrado. Se conservan sesiones, workspaces, historial y orden de cola; esa exclusión no consume reintentos. Volver a configurar el repo permite recuperar sus ejecuciones pendientes, manteniendo detenidas las que requieren intervención humana.

## Out of scope

UI web, app del OS, controles interactivos en el panel, comandos de reactivación de casos que requieren intervención y soporte inicial de Linux/Windows. El motor se mantiene portable, pero el soporte adicional requiere validación.

Merge automático del PR final, reproducir políticas del repo dentro del motor, cambiar los informes actuales de los skills o incorporar una copia de Agent Forge. `ship` conserva su flujo de slices; el loop de revisión de esta app trabaja sobre el PR final de la épica.

Dependencias entre épicas y desbloqueo por merge. Ese trabajo se resolverá en Solve por separado; esta versión toma directamente las épicas ready.

## Open questions

Son validaciones técnicas que solo una prueba con las herramientas reales puede responder; ninguna es una decisión de producto. Cada una es candidata a un spike con un criterio de éxito claro. Las dos primeras (agentes headless y contenedores) condicionan el resto: si fallan, cambia el diseño del runner o de la identidad.

Claude y Codex headless. Comprobar que ambos ejecutan el flujo de skills sin interacción, exponen y conservan sus sesiones, retoman tras una interrupción y entregan el JSON del caller. Incluir el trabajo delegado por `ship` y comprobar que detener el proceso alcanza a sus procesos hijos sin perder lo necesario para reconstruir el contexto.

Agentes en contenedores. Probar el runtime de contenedores en macOS con Claude y Codex: montaje del workspace y del clon para que los worktrees de Solve y Git funcionen, login y sesiones persistentes dentro, renovación del token de Forge en ejecuciones de hasta cuatro horas, toolchains para los tests del repo, la salida a red mínima que necesitan y que detener el contenedor termine todos los procesos. Si no es viable, Diego elige entre las alternativas del ADR.

Agent Forge. Validar el adaptador para identidades de bots y personales, especialmente la renovación de credenciales durante ejecuciones largas. La [investigación previa](../research/autonomous-ship-review.md) identificó que el launcher observado no implementaba nuestro contrato de tareas headless; la app debe integrar las capacidades de identidad sin asumir que ese launcher ya resuelve el runner.

Raíz compartida con Solve. Probar la raíz compartida, la creación y reutilización de worktrees y dos épicas simultáneas desde un clon administrado. Comprobar que el material preparado antes de ready sea accesible al caller y que las sesiones puedan continuar en las mismas rutas. Es validación del contrato acordado, no una delegación de decisiones de producto al prototipo. Mientras Solve no agregue `solve:epic:ready` por su cuenta, la etiqueta se puede poner a mano para esta prueba.

Recuperación ante cortes. Probar interrupciones entre publicación en GitHub y persistencia local, incluyendo un JSON incompleto. Verificar que se importen resultados una sola vez y se retome el trabajo sin duplicar agentes, PRs, comentarios ni cambios de estado.

Logs y panel. Validar cómo dirigir stdout y stderr de `@ashulab/universal-logger` a archivos sin interferir con el panel de terminal. El package revisado escribe por consola y no ofrece un transport general; la integración debe reutilizar la biblioteca como implementación de logging y conservar la salida al detener el proceso.
