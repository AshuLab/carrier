# Carrier — Orquestador de épicas autónomas

El nombre de la aplicación es **Carrier**, inspirado en la nave de StarCraft que despliega múltiples interceptores. Carrier coordina agentes en paralelo; Agent Forge aporta sus identidades y Solve el flujo de skills.

Estado: borrador de requisitos. Registra decisiones de la conversación y propuestas pendientes; no describe un sistema implementado.

El brief de `solve:sharpen` está en [docs/specs/autonomous-orchestrator.md](specs/autonomous-orchestrator.md). Este documento conserva el detalle de la conversación; el brief sintetiza el problema, dirección, alcance y validaciones pendientes.

## Objetivo

Diego prepara ideas con `sharpen`, genera specs y tickets, y habilita épicas para ejecución. Un proceso local toma esas épicas, ejecuta `ship` y coordina revisión y correcciones del PR final hasta dejarlo listo para probar o pedir intervención.

El proceso permite seguir preparando nuevas features mientras los agentes trabajan. Diego prueba y mergea el PR final.

## Decisiones acordadas

- Construir nuestro propio orquestador y runner en TypeScript sobre Node.js.
- Runtime inicial: Node.js 26, con módulos ESM. Usar pnpm como gestor de paquetes. Incorporar TypeScript, pnpm y cada dependencia de runtime/desarrollo en su última versión estable disponible al implementar o actualizar; excluir prereleases.
- Es una app independiente, con repositorio propio separado de SecondBrain. La primera interfaz es un comando con panel de terminal; el almacenamiento de ejecución permanece bajo la raíz compartida `~/.solve/` configurable.
- Plataforma inicial soportada y validada: macOS. TypeScript/Node.js permite mantener el núcleo portable; soporte de Linux/Windows queda para después de validar dependencias, procesos, credenciales y rutas en esas plataformas.
- Ejecutar el proceso desde cualquier carpeta. Configurar explícitamente los repos GitHub donde busca épicas; el directorio actual no determina qué repos consulta.
- Al reiniciar, no retomar trabajo de repos que ya no figuren en la configuración. Conservar sus épicas, sesiones, workspaces e historial y mostrar el motivo; no borrar información ni consumir reintentos por esa exclusión.
- Usar una raíz de almacenamiento compartida entre Solve y el orquestador para clones y worktrees, con ubicación configurable. El orquestador agrega allí su base, sesiones y logs. Solve administra los worktrees y ramas de implementación; ambos reutilizan las mismas rutas de código para retomar.
- Raíz compartida por defecto: `~/.solve/`, configurable. Organización acordada: `repos/` para clones, `worktrees/` para workspaces de Solve y `orchestrator/` para SQLite, sesiones y logs.
- Empezar con un comando en la terminal y un panel que muestre el progreso en esa misma terminal.
- El panel inicial es simple e informativo, sin controles para pausar, reintentar o administrar ejecuciones. Primero validar el flujo; mejorar la interfaz en versiones posteriores.
- Usar SQLite para el estado y archivos separados para los logs.
- Usar Drizzle ORM con `better-sqlite3` para esquema y acceso a SQLite, y Drizzle Kit para generar migraciones. Elegir las últimas versiones estables compatibles con Node 26.
- Usar el package `@ashulab/universal-logger` como dependencia runtime de la app para logging de información, warnings y errores. Importar y configurar su API; no copiar su implementación ni crear un logger o formato propio en su reemplazo.
- Usar `solve:epic:ready` como etiqueta de entrada a la cola.
- Solve agrega esa etiqueta automáticamente cuando termina todas las etapas de preparación. El cambio se realiza en los skills de Solve, fuera de este orquestador.
- `solve:epic:ready` es la señal suficiente para tomar una épica: el orquestador la registra directamente en la cola, sin una consulta adicional a Solve para habilitarla.
- Al iniciar la ejecución de una épica, quitar `solve:epic:ready` y agregar `solve:epic:running` en GitHub. Conservar la ejecución en SQLite para retomar sin depender de que el issue siga ready.
- Al quedar lista para probar, reemplazar `solve:epic:running` por `solve:epic:ready-for-test`. Si requiere intervención, reemplazarla por `solve:epic:needs-human`. Registrar también el resultado en SQLite.
- Los agentes no corren con los permisos del sistema anfitrión: cada ejecución va en un contenedor con permisos amplios adentro y solo el workspace de la épica montado. Los scopes mínimos del token y la branch protection de los repos son el segundo límite. Ver [ADR 0003](adr/0003-agentes-en-contenedor.md).
- Ejecutar épicas independientes en paralelo, con un máximo de concurrencia configurable como entero positivo. Valor inicial: tres épicas; puede ser uno, dos, cuatro, ocho u otro valor según la configuración.
- Tomar épicas ready en orden de llegada a la cola (FIFO), conservando el orden de ingreso al reiniciar.
- Las dependencias entre épicas quedan fuera de la primera versión y se resolverán en Solve por separado. La regla discutida para una evolución es esperar el merge de los prerequisitos; el MVP no implementa un grafo, un estado de espera por dependencias ni un desbloqueo por merge.
- Revisar el PR final de integración de la épica, como lo produce `ship`.
- Si se detecta que el PR final de integración de una épica fue mergeado mientras aún hay trabajo activo, detener sus agentes y nuevos turnos, conservar sesiones/logs y registrar el motivo. Esto no aplica a los merges de slices que realiza `ship` como parte de la implementación.
- Alternar autor y reviewer con identidades GitHub distintas, usando Agent Forge para preparar identidades y credenciales.
- Agent Forge es una dependencia externa instalada. El runner la utiliza para preparar la identidad y las credenciales GitHub de cada ejecución; no incorpora una copia de Forge dentro del proyecto.
- Soportar un catálogo de `n` identidades GitHub, incluyendo la de Diego, en lugar de limitarse a dos bots fijos. Identidades y sesiones se distinguen: una misma identidad puede participar en varias épicas con sesiones aisladas.
- El usuario configura los perfiles GitHub disponibles y elige explícitamente cuál utiliza el propio orquestador para consultar issues y actualizar etiquetas. Puede reutilizar un perfil de agente o asignar otro; no se asume automáticamente que sea el autor.
- Asignar explícitamente las identidades de autor y reviewer mediante configuración; no seleccionarlas automáticamente de un pool.
- Permitir elegir proveedor y modelo por rol. Separar identidad GitHub de proveedor/modelo.
- Definir valores globales de identidad, proveedor y modelo por rol, con overrides por repo. Cada repo hereda los valores globales y reemplaza sólo los que configura explícitamente.
- Al iniciar una épica, guardar su configuración efectiva de agentes. Cambiar defaults u overrides afecta a las nuevas épicas; las que ya están en curso conservan sus identidades y modelos, incluso al retomar sesiones.
- El archivo de configuración usa JSON para repos, identidades, modelos, overrides y límites. Validar al arrancar y mostrar errores claros para campos ausentes o valores inválidos.
- Usar `zod` como dependencia runtime para los esquemas y validación de configuración y resultados del caller. Inferir los tipos TypeScript desde los esquemas para mantener ambos contratos alineados.
- Usar Vitest como dependencia de desarrollo para los tests de la app. Probar cola, transiciones, persistencia y recuperación con agentes simulados; las pruebas con Claude/Codex reales se mantienen como integración aparte.
- Incluir una configuración default con la app y permitir un archivo JSON del usuario que la sobrescribe. Merge por campo de objetos; valores simples del usuario reemplazan los defaults; las listas se reemplazan completas, sin concatenarlas. Validar la configuración resultante.
- Proveedores iniciales: Claude y Codex.
- Máximo de cinco revisiones por épica, configurable; detener el loop antes cuando no queden blockers y se cumplan los checks.
- En repos sin CI, alcanza con revisión concluyente sin blockers y evidencia de tests reportada por los skills para quedar listo para probar. Registrar esa evidencia y la ausencia de CI. Si hay checks requeridos, deben estar verdes en el commit revisado.
- Tres reintentos de fallos de ejecución, configurables, separados de las rondas de revisión.
- Las correcciones y repeticiones de tests/CI son trabajo interno de los agentes y skills. El orquestador recibe su resultado final y no cuenta esos intentos ni agrega un loop específico para corregir tests.
- Tiempo máximo inicial por ejecución de agente: cuatro horas, configurable. Admitir una opción explícita sin límite (`unlimited`); cero no se interpreta como infinito. El límite no incluye el tiempo de una épica en cola ni representa una duración máxima de todo el loop.
- Al vencer el límite de tiempo, detener la ejecución, conservar sesión y workspace, y marcar la épica como requiere intervención. El timeout no dispara un reintento automático.
- Si el reviewer no puede concluir por falta de contexto, la épica requiere intervención. Registrar el motivo; ausencia de blockers detectados en una revisión incompleta no habilita el PR.
- Las épicas que requieren intervención las resuelve Diego manualmente. La primera versión registra y muestra el motivo, sin comando ni controles para reactivarlas. Esto se distingue de retomar automáticamente las ejecuciones interrumpidas por `Ctrl+C`.
- Los skills conservan sus salidas actuales. El agente caller las interpreta como lo haría una persona que invoca el skill.
- El orquestador coordina sin interpretar el dominio del repo. Autor y reviewer aplican las reglas del repo/Solve, eligen y evalúan tests/checks y determinan blockers. El orquestador valida el contrato JSON y su coherencia técnica, persiste resultados y administra etapas, límites y etiquetas. Ver [ADR 0001](adr/0001-separar-coordinacion-y-evaluacion-del-repo.md).
- El caller escribe su conclusión por ejecución en un archivo JSON estructurado. El orquestador valida su esquema y guarda la información en SQLite, asociada a la épica, etapa y ejecución, conservando el historial.
- El JSON del caller tiene tres resultados: `completed`, `changes_requested` y `needs_human`. El motor combina el resultado con la etapa para coordinar el siguiente turno.
- Conservar las sesiones de los agentes por épica y rol para retomar desde el contexto de una etapa interrumpida, además de continuar las etapas pendientes. Registrar proveedor, identificador y ubicación de la sesión cuando corresponda, y conservar el workspace.
- Si una sesión guardada no se puede recuperar, iniciar una nueva con el contexto persistido y el estado actual del workspace/GitHub. El agente verifica qué quedó hecho antes de continuar; mantiene la identidad y registra la recuperación en el historial.
- `Ctrl+C` detiene el orquestador y las ejecuciones activas en ese momento, sin esperar que terminen sus etapas. Conservar sesiones, workspaces y el estado persistido para retomar al reiniciar.
- Diego adaptará los skills para que las etapas autorizadas puedan ejecutarse sin esperar aprobación.
- SQLite es la autoridad del estado de cada ejecución; las etiquetas `solve:epic:*` son su reflejo y se reconcilian. Ver [ADR 0002](adr/0002-sqlite-autoridad-etiquetas-reflejo.md).
- Una UI web o app del OS queda para una evolución posterior.

## Recorrido de una épica

### Repos de trabajo y arranque

El proceso se ejecuta desde cualquier carpeta y permanece activo. La configuración incluye una lista explícita de repos GitHub donde buscar issues; cada entrada identifica el repo por organización/usuario y nombre. El proceso consulta los repos de esa lista y busca la etiqueta `solve:epic:ready`.

Sólo se permite una instancia activa por carpeta de datos del orquestador. Antes de iniciar consultas o agentes, el proceso adquiere un bloqueo exclusivo de esa carpeta. Si otra instancia lo mantiene, muestra que el orquestador ya está corriendo y termina sin iniciar trabajo. Un cierre inesperado no debe impedir el próximo arranque: el mecanismo debe distinguir un bloqueo activo de uno residual y evitar que dos arranques simultáneos adquieran la misma carpeta.

El código de cada épica se ejecuta en su propio workspace, separado del directorio donde se inició el proceso. Solve y el orquestador comparten una raíz configurable para clones y worktrees. El orquestador guarda allí también sus sesiones, base y logs. El caller invoca `ship` con aislamiento por épica; Solve crea o reutiliza su worktree, administra sus ramas y registra el PR final. El clon compartido del repo no es un directorio donde varios autores implementan en paralelo.

La integración usa la misma ubicación y convención de worktrees que Solve, mediante su mecanismo de configuración/invocación. El orquestador registra el path real y lo reutiliza al retomar; no crea en paralelo una segunda estructura de worktrees de implementación ni elimina los que administra Solve. El checkout separado del reviewer se mantiene bajo la raíz compartida.

La raíz compartida por defecto es `~/.solve/`, configurable. La organización acordada es `repos/` para clones, `worktrees/` para workspaces de Solve y `orchestrator/` para SQLite, sesiones y logs. Los directorios de repo deben distinguir organización/usuario y nombre para evitar colisiones. Pendiente: la forma de comunicar esta configuración a Solve y comprobar su compatibilidad; es el diseño acordado, no una afirmación de que todos estos directorios ya existan en Solve.

### 1. Preparar y habilitar

Diego prepara la idea, spec y tickets con Solve. Al completar todas las etapas de preparación, Solve agrega `solve:epic:ready` automáticamente. La épica debe contener lo necesario para que `ship` pueda trabajar; una idea todavía sin spec o tickets no está lista. La incorporación de la etiqueta se implementa en los skills de Solve, fuera de este proyecto.

La etiqueta significa que un agente puede tomar la épica directamente. Para una épica nueva, el orquestador comprueba que el issue siga abierto y ready al reservarlo y que no exista una ejecución registrada que deba retomar o respetar. Las ejecuciones existentes se recuperan desde SQLite y no requieren volver a agregar ready. La gestión de dependencias entre épicas es un cambio separado en Solve.

### 2. Descubrir y poner en cola

El proceso consulta todos los repos configurados y descubre issues abiertos con la etiqueta de entrada. Debe recorrer todos los resultados, aunque haya muchas épicas, y reconocer los que ya están registrados. La identidad de una épica incluye repo e issue, dado que distintos repos pueden tener el mismo número de issue.

Las consultas periódicas a GitHub usan un intervalo fijo de 5 minutos por defecto, configurable en JSON. La primera consulta también espera ese intervalo desde el arranque. No se usan webhooks, una URL pública ni intervalos adaptativos. Este intervalo no agrega esperas entre turnos de autor y reviewer: el loop avanza al recibir el resultado de cada agente.

Si GitHub no está disponible o limita las consultas, conservar la cola y el estado persistido, mostrar el error y volver a consultar en el siguiente intervalo configurado. Si GitHub indica una espera mayor, respetarla. Estos fallos de consulta no consumen reintentos de ejecución de los agentes ni convierten una consulta fallida en una lista vacía de épicas. Los errores de autenticación se tratan mediante la integración con Forge según lo definido para los perfiles.

Las épicas ready nuevas se guardan directamente en SQLite como encoladas. La etiqueta es el contrato de disponibilidad para esta versión; no se consulta otro skill ni se resuelven dependencias entre épicas antes de encolarlas. El orquestador administra reservas y concurrencia sobre esa cola.

El orden de selección es FIFO entre épicas ready, según su ingreso a la cola persistida. Las épicas que requieren intervención quedan detenidas sin impedir que otras avancen. La representación y resolución de dependencias futuras pertenecen a Solve.

### 3. Reservar y ejecutar ship

Cuando hay un slot disponible, el scheduler reserva una épica mediante una operación atómica en SQLite. Una épica no puede tener dos ejecuciones activas.

Al iniciar su ejecución, quitar `solve:epic:ready` y agregar `solve:epic:running` en GitHub para que sea visible que la épica ya fue tomada. Persistir el inicio y reconciliar el estado de GitHub al retomar; el cambio de etiquetas no reemplaza el registro de ejecución en SQLite.

Prepara un workspace aislado y lanza al autor con la identidad, proveedor, modelo, skill y contexto de esa épica. `ship` mantiene el control de sus slices, ramas y PR final; el orquestador coordina la ejecución y registra el resultado.

El caller lee el informe actual de `ship`, identifica el PR final y comunica el resultado al orquestador. Antes de avanzar, el orquestador comprueba que existe y corresponde a la épica. Si `ship` necesita una decisión o no puede completar el trabajo, se registra el motivo y se solicita intervención.

### 4. El agente verifica el código

El autor aplica las reglas del repo y de Solve para determinar qué tests y checks corresponden al PR. Ejecuta o consulta esas verificaciones, interpreta sus resultados y espera los checks pendientes cuando corresponda. Resuelve los fallos como parte de su trabajo con los skills y, cuando termina, reporta qué completó y en qué estado quedó. Si no puede terminar, informa el motivo y la necesidad de intervención. El reviewer verifica después la evidencia. El orquestador consume las conclusiones de cada ejecución, sin definir qué checks son obligatorios, reinterpretar sus resultados ni administrar los intentos internos del agente.

Si el repo no tiene CI, el caller recoge la evidencia de tests reportada por los skills y registra que la verificación no incluyó CI. Esa evidencia, junto con el review concluyente sin blockers, alcanza para quedar listo para probar; no se exige incorporar GitHub Actions ni un check externo para utilizar el orquestador.

El orquestador no tiene un contador ni un límite propio de correcciones de tests/CI. Los tres reintentos configurables siguen siendo para fallos técnicos de ejecución; las cinco reviews limitan el intercambio autor/reviewer. La selección, evaluación y corrección de checks pertenece a los agentes y skills. Este apartado describe trabajo del agente dentro de su turno, no una etapa adicional de control de CI a cargo del motor.

### 5. Revisar y publicar

Lanza al reviewer con otra identidad y un checkout separado del autor. Recibe spec, tickets, PR, SHA y contexto de las rondas anteriores.

El reviewer invoca los skills de revisión y publicación, interpreta sus informes actuales y comunica si la revisión fue concluyente sin blockers, tuvo blockers o quedó inconclusa.

El orquestador registra el SHA revisado, findings, links a los comentarios y número de ronda. Un proceso que termina exitosamente no basta para declarar que el código está listo.

### 6. Corregir o responder

Si hay blockers y quedan rondas, el proceso activa al autor con los comentarios y evidencia. El autor evalúa cada finding: corrige o responde con razones verificables.

Responder o marcar un thread como resuelto no equivale a eliminar el blocker. El reviewer verifica la corrección o acepta la respuesta en la siguiente pasada. La identidad del autor se mantiene durante toda la épica; su sesión puede retomarse o reconstruirse si no está disponible.

El autor verifica el nuevo commit según las reglas del repo y el reviewer vuelve a revisar, verificando evidencia, findings pendientes y posibles regresiones. El orquestador administra el cambio de turno y los límites.

### 7. Terminar el loop

Una épica queda [lista para probar](glossary.md) cuando el reviewer emitió un resultado concluyente sin blockers y los agentes confirmaron las verificaciones requeridas por el repo sobre el mismo commit. En un repo sin CI, alcanza con ese review y la evidencia de tests reportada por los skills, dejando registrada la ausencia de CI. El orquestador consume esa conclusión, comprueba su coherencia técnica con la ejecución/PR/SHA y registra la transición; no decide por sí mismo si el código o CI son correctos. Un cambio posterior de código invalida ese resultado y exige nueva verificación de los agentes.

Máximo acordado: cinco revisiones, configurable. Si la quinta mantiene blockers, se solicita intervención. No se aplica otra corrección para luego declarar listo un commit que no fue revisado. Los errores de ejecución no consumen una ronda de revisión. Si el reviewer no puede concluir por falta de contexto, la épica requiere intervención y se registra el motivo; una revisión incompleta sin blockers detectados no habilita el PR.

Tres reintentos de fallos de ejecución, configurables. Se interpretan como hasta tres reintentos después del intento inicial. Antes de relanzar una etapa, comprobar sus efectos para evitar duplicar publicaciones o trabajo. Un finding de código o un desacuerdo no es un fallo de infraestructura que se resuelva repitiendo la misma ejecución.

Los desacuerdos sobre findings se trabajan entre autor y reviewer dentro del límite de revisiones. Las épicas que requieren intervención quedan detenidas con el motivo registrado para que Diego las resuelva como humano, sin comando de reactivación en esta versión. Otras épicas pueden seguir avanzando. Reiniciar el proceso no reactiva automáticamente estas épicas; es distinto de retomar una ejecución interrumpida por `Ctrl+C`.

La salida queda visible también en el issue de GitHub: reemplazar `solve:epic:running` por `solve:epic:ready-for-test` cuando se cumplan las condiciones de entrega para pruebas, o por `solve:epic:needs-human` al requerir intervención. SQLite conserva el resultado, evidencia e historial; al recuperarse de un fallo durante la actualización de etiquetas, reconciliar ambos registros.

### 8. Probar y mergear

Diego prueba el PR y decide el merge. El orquestador continúa buscando nuevos issues ready en los repos configurados; la primera versión no incluye desbloqueo de épicas por merge.

Mientras la épica tenga trabajo activo, comprobar si su PR final ya fue mergeado. Si se detecta ese merge, detener sus ejecuciones y no lanzar otros turnos para esa épica; conservar sesiones, workspace e historial y registrar que se detuvo por merge del PR final. Las demás épicas continúan. Los merges de PRs de slices no disparan esta regla. La comprobación de estado del PR es coordinación técnica, no evaluación de código o CI.

Si se cierra manualmente el issue de la épica o su PR final sin merge, registrar la épica como cancelada, detener sus agentes y no iniciar nuevos turnos. Conservar el trabajo realizado y mostrar el motivo en terminal; las demás épicas continúan. La cancelación finaliza el trabajo del orquestador y comienza el plazo de retención de 30 días para sus logs y sesiones. La regla no se aplica a los cierres de tickets o PRs de slices realizados por `ship`.

Para una evolución con dependencias, se conversó que si A crea una API y B la consume, B debería esperar al merge de A. Ese comportamiento se diseñará por separado en Solve.

## Comunicación y resultados

Los agentes no necesitan quedar vivos esperando mensajes entre etapas. El orquestador recibe el resultado de una etapa y lanza la siguiente con contexto persistido. GitHub conserva código, PRs, reviews y respuestas; SQLite conserva el estado de coordinación.

Los skills mantienen sus informes actuales. El caller recibe la tarea, invoca el skill, lee el informe y actúa sobre él como una persona: identifica el PR, entiende blockers y respuestas, o detecta que necesita ayuda. La adaptación para invocación sin aprobación sigue a cargo de Diego.

El caller devuelve una conclusión breve con lo que terminó, PR/SHA cuando corresponda, evidencia, blockers o motivo de intervención. El orquestador valida el contrato y guarda el resultado en SQLite, asociado a la épica, etapa y ejecución; conserva las conclusiones anteriores como historial. El panel consume esas conclusiones y el informe completo del skill queda en los logs. Puede comprobar referencias y vigencia del SHA en GitHub para evitar coordinar sobre otro commit; la evaluación de código, tests, CI y blockers es del autor/reviewer.

Transporte acordado: el caller escribe un archivo JSON estructurado de resultado y el orquestador valida su esquema antes de importarlo a SQLite. La base es el registro persistente. Comprobar campos requeridos según la etapa, tipos, valores permitidos y correspondencia con la épica/ejecución esperada. Guardar el resultado y la transición de estado en una transacción para evitar avances sin información persistida; la importación del mismo resultado debe ser idempotente. Un resultado inválido no habilita avanzar de etapa. Los campos exactos se definen al diseñar el esquema, manteniendo las salidas actuales de los skills.

El campo de resultado (`outcome`) admite:

| Resultado | Significado y transición |
| --- | --- |
| `completed` | El agente terminó su turno correctamente. Si era `ship` o corrección del autor, habilita un review; si era review, significa que concluyó sin blockers y confirmó las verificaciones del repo, y habilita listo para probar. |
| `changes_requested` | El reviewer concluyó que hay blockers y pide correcciones. Si quedan rondas, habilita al autor; al agotar el límite, requiere intervención. Es válido sólo para un turno de review. |
| `needs_human` | El agente no puede continuar y explica el motivo. Detener nuevos turnos de la épica y registrar la intervención necesaria. |

El runner informa por separado la terminación técnica del proceso. Un fallo de CLI o un JSON ausente/inválido no se convierten en `completed`: se reconcilia lo realizado y se aplica la política de reintentos técnicos. Los tres outcomes son conclusiones del caller, no un catálogo de errores de infraestructura.

Los adaptadores de proveedores traducen la tarea al CLI correspondiente, preparan credenciales para esa ejecución y capturan salida, logs y errores. Las credenciales de un agente no deben mezclarse con las de otra ejecución paralela. Debe resolverse su renovación durante trabajos largos.

Agent Forge se utiliza como dependencia externa instalada, mediante un adaptador del runner. El orquestador conserva la cola y el loop; el runner conserva el lanzamiento de tareas y sesiones con Claude/Codex; Forge prepara identidad y credenciales GitHub. Queda validar el mecanismo concreto de integración y fijar una versión compatible.

El catálogo admite múltiples identidades, incluida la personal de Diego. La configuración asigna explícitamente una identidad al autor y otra al reviewer. Para un mismo PR, deben ser diferentes. Agent Forge es responsable de la autenticación de los perfiles; la app referencia esos perfiles y consume los errores de la integración. Queda validar el soporte concreto de perfiles personales y bots.

La configuración también selecciona un perfil GitHub para las operaciones del orquestador: descubrimiento de issues, consulta de referencias y actualización de etiquetas. El usuario declara los perfiles que tiene disponibles y los referencia desde la configuración; puede elegir el mismo para distintas responsabilidades cuando corresponda, salvo la separación de autor/reviewer de un mismo PR. Configurar perfiles no implica agregar una UI o wizard en esta versión: el archivo JSON contiene las referencias y Agent Forge resuelve la autenticación.

Si Forge informa un error de autenticación, se detienen las épicas que necesitan el perfil afectado y se muestra el motivo en terminal. Las demás pueden continuar. Si el perfil afectado es el del orquestador, se suspenden las operaciones GitHub que dependen de él. La app no implementa un sistema propio de autenticación ni cambia de perfil automáticamente.

## Estado persistido

Guardar por épica: repo e issue, fecha de ingreso a la cola, workspace, PR final, etapa, ronda, identidades, configuración elegida, SHA revisado, blockers pendientes, ejecuciones, errores e historial de eventos. No guardar tokens en el estado ni en los logs.

Los logs y sesiones vinculados a una épica se borran automáticamente 30 días después de que termina la épica. Mientras siga pendiente, incluidos los casos interrumpidos o que requieren intervención, se conservan para permitir retomarla. Esta limpieza no elimina el registro de la épica en SQLite ni sus workspaces.

Al reiniciar, el proceso reconcilia etapas incompletas con los procesos existentes y con GitHub antes de reintentar. No asume que una etapa falló sólo porque no alcanzó a registrar su resultado; podría haber creado un PR, comentario o commit.

Antes de retomar, comprobar que el repo siga en la configuración actual. Si fue quitado, conservar la ejecución, su orden de cola y configuración efectiva, pero dejarla detenida con el motivo repo no configurado. Mantener sesiones, workspace e historial; no consumir reintentos ni ejecutar acciones nuevas sobre ese repo. Si vuelve a configurarse, sus ejecuciones pendientes vuelven a ser elegibles para recuperación, respetando las que ya requerían intervención. Esta regla se evalúa al arrancar; no implica implementar recarga de configuración en caliente.

La continuidad incluye la sesión del autor y del reviewer, el contexto del caller y el workspace con su estado Git, incluyendo trabajo aún sin commit. Los adaptadores de Claude y Codex deben permitir retomar las sesiones conservadas. Reiniciar el orquestador no implica volver a lanzar `ship` desde cero. Al retomar, el agente verifica qué operaciones terminaron y continúa desde el estado real; una sesión recuperada no equivale a reanudar un comando del sistema exactamente en la instrucción donde fue interrumpido.

Si una sesión no se puede recuperar, el proceso registra el motivo y abre una nueva con la misma identidad, el contexto persistido, conclusiones e informes previos y el estado actual del workspace/GitHub. El agente verifica qué operaciones quedaron realizadas y continúa lo pendiente. La recuperación queda en el historial para distinguir una sesión retomada de un contexto reconstruido.

`Ctrl+C` deja de tomar trabajo y detiene las ejecuciones activas, incluidos los procesos hijos de los agentes, sin esperar la finalización de las etapas. El estado y los identificadores de sesión se registran durante la ejecución, no únicamente al terminarla. Se conservan archivos de sesión, workspaces y logs. Al reiniciar, las etapas interrumpidas se reconcilian antes de continuar; no se duplican agentes que hayan quedado vivos ni acciones externas ya realizadas.

## Panel de terminal

El comando se ejecuta en la terminal que Diego use: Terminal de macOS, iTerm, Ghostty o una terminal integrada. El panel se dibuja en esa misma ventana; el programa no requiere una terminal propia. Los agentes se ejecutan como procesos hijos y su salida se captura para logs y actividad. Propuesta: salida simple si no hay una terminal interactiva.

Mostrar slots ocupados, épicas en cola y etapa de cada ejecución. Para cada épica: ronda, blockers, tiempo en etapa, última actividad y links al issue/PR. Los logs detallados quedan en archivos.

La etapa actual y la última actividad son datos distintos: ausencia de salida no significa que el agente esté avanzando. El panel debe mostrar también errores y motivos de intervención.

El primer panel sólo informa: épicas, etapas, rondas, blockers, actividad, errores y referencias a logs. No incorpora controles de pausa o reintento. `Ctrl+C` detiene el proceso; la configuración y el arranque se realizan desde el comando. Se prioriza probar el flujo completo antes de ampliar la interfaz.

## Configuración propuesta

Formato acordado: JSON. La app incluye una configuración default y admite una configuración del usuario que sólo necesita declarar los valores que quiere cambiar. Los valores simples del usuario reemplazan los defaults; los objetos se combinan por campo, conservando los campos omitidos; las listas se reemplazan completas, sin concatenación. Un valor de tipo incompatible no debe convertirse silenciosamente para completar el merge.

Al arrancar, la aplicación combina defaults y configuración del usuario y valida el resultado, incluyendo campos requeridos, tipos, referencias a identidades y límites permitidos. Los errores deben identificar el campo y problema para que pueda corregirse la configuración. Después se resuelven los overrides por repo sobre los valores globales de agentes; la configuración efectiva de una épica se persiste al iniciarla. La configuración default pertenece al paquete de la app; los datos específicos del usuario se mantienen fuera del código.

La validación se implementa con Zod, compartiendo los esquemas con los tipos TypeScript inferidos. `config/` mantiene el esquema de configuración y `execution/` el del resultado del caller; cada módulo conserva la propiedad de su contrato. La validación de estructura es distinta de las comprobaciones de coherencia de referencias y de la evaluación del repo que realizan los agentes. [Documentación de Zod](https://zod.dev/).

Lista de repos GitHub para buscar épicas y ubicación de código/workspaces; catálogo de perfiles GitHub y perfil seleccionado para el orquestador; identidad, proveedor y modelo por rol de agente; opciones específicas del proveedor; concurrencia; límite de revisiones; frecuencia de consulta; límites de reintentos de ejecución y tiempo. La configuración debe poder usarse independientemente del directorio desde donde se inicia el proceso. Las reglas de validación del repo se consultan desde los agentes y skills.

Identidad, proveedor y modelo de autor/reviewer tienen valores globales y overrides por repo. Un repo hereda cada campo global que no reemplace explícitamente. La identidad de autor y reviewer para un mismo PR sigue siendo diferente después de resolver esos overrides. El alcance de los overrides acordados no incluye una configuración individual por épica.

Valores acordados: Claude y Codex como proveedores iniciales, cinco revisiones, tres reintentos de ejecución, tres épicas simultáneas y cuatro horas por ejecución de agente como valores iniciales, con todos los límites configurables. La duración permite una opción explícita sin límite. La concurrencia interna de `ship` también debe considerarse para controlar la carga real.

Guardar la configuración efectiva de agentes al iniciar una épica, después de resolver defaults y overrides por repo. Los cambios de configuración se aplican a nuevas épicas; las que están en curso conservan sus identidades, proveedores y modelos, también al retomar una sesión o reconstruir su contexto. La configuración persistida no incluye credenciales secretas. Un cambio de proveedor o fallback durante una ejecución no se deriva automáticamente de modificar los defaults.

### Qué significa un límite de tiempo

Un timeout es un límite para una ejecución o llamada que no termina; no es la frecuencia de polling ni una duración prometida de una épica. Diferenciar llamadas breves a GitHub de un `ship` que puede trabajar durante horas. La ausencia de logs no prueba por sí sola que un agente esté trabado.

El máximo por ejecución de agente es cuatro horas por defecto, configurable, con una opción explícita sin límite. Propuesta de representación en JSON: `"maxExecutionHours": 4` o `"maxExecutionHours": "unlimited"`; si se omite la configuración, aplicar las cuatro horas por defecto. Cero no significa infinito. Es el límite de una invocación de `ship`, review o corrección, no el de toda la épica ni su espera en cola.

Al vencer el límite, detener la ejecución, conservar sesiones y workspaces y registrar el motivo. La épica queda como requiere intervención para que Diego decida cómo continuar; no se reintenta automáticamente por timeout. Antes de continuar, detener o reconciliar los procesos anteriores; nunca lanzar otro autor mientras el anterior siga actuando sobre el mismo workspace. Pendiente: fijar timeouts para operaciones externas breves.

## Límites de la primera versión

Un proceso local para macOS, SQLite, logs y panel de terminal. Sin servidor web ni app del OS. Se mantiene portable el núcleo TypeScript/Node.js; Linux y Windows quedan fuera de la validación y soporte inicial. El merge del PR final y la resolución de casos que requieren intervención son humanos. No se agrega comando ni UI de reactivación de esos casos. Las dependencias entre épicas se resolverán por separado en Solve; el MVP toma directamente issues ready. El sistema ejecuta los skills; no reproduce dentro del orquestador su lógica de implementación y review.

La investigación previa está en [autonomous-ship-review.md](research/autonomous-ship-review.md). Su máximo de cuatro reviews fue reemplazado por los cinco configurables de este documento.

## Proyecto y almacenamiento

El orquestador es una app independiente con repo propio, [AshuLab/carrier](https://github.com/AshuLab/carrier); no se implementa dentro de SecondBrain ni de los repos donde busca épicas. Este documento vive en `docs/` de ese repo como borrador de trabajo. El código y las pruebas viven en el repo de la app; la configuración y datos de ejecución se ubican bajo la raíz compartida, independientemente de la ubicación del código o la carpeta desde donde se ejecuta el comando.

## Tecnologías y versiones

Stack acordado: TypeScript, Node.js 26 y ESM, con pnpm como gestor de paquetes. Dependencias runtime ya elegidas: `zod`, `@ashulab/universal-logger`, `drizzle-orm` y `better-sqlite3`. Drizzle Kit y Vitest se incorporan como tooling de desarrollo para migraciones y tests, junto con los tipos adicionales que requiera el driver. Agent Forge sigue siendo una dependencia externa instalada.

Al incorporar o actualizar cada paquete, consultar la última versión estable publicada y comprobar compatibilidad con Node 26. Aplicar también al tooling de desarrollo; excluir versiones alpha, beta, RC, nightly u otras prereleases. Registrar las versiones seleccionadas y versionar `pnpm-lock.yaml`; fijar la versión de pnpm en `packageManager`. Las instalaciones reproducibles usan ese lockfile, y los upgrades se verifican con build, chequeo de tipos y tests. La selección de versiones recientes no implica resolver nuevas versiones diferentes en cada arranque de la app.

Referencia consultada el 2026-10-15: [Node 26.12.0](https://nodejs.org/en/download), [pnpm 12.11.2](https://registry.npmjs.org/pnpm/latest) y [TypeScript 7.0.2](https://registry.npmjs.org/typescript/latest). Son versiones observadas, no sustituyen volver a consultar las estables al crear el proyecto. La versión de código inspeccionada de universal-logger tampoco debe tomarse automáticamente como la última publicada.

## Estructura de código en definición

Un único paquete Node/TypeScript, agrupado por responsabilidad. Crear los archivos concretos al implementar cada responsabilidad.

```text
src/
  cli/              # arranque, Ctrl+C y panel
  config/           # lectura, validación y overrides
  orchestration/    # selección de épicas, etapas, turnos y límites
  execution/        # procesos, sesiones y contrato de resultados
  storage/          # esquema Drizzle, SQLite y artefactos de ejecución
  logging/          # configuración e integración de universal-logger
  integrations/     # GitHub y Forge
  providers/        # Claude y Codex
  prompts/          # instrucciones de autor y reviewer
  shared/           # helpers reutilizables entre módulos
test/
```

`shared/` reúne utilidades generales realmente compartidas, por ejemplo formateadores de duración para panel/logs o helpers de rutas. Puede contener archivos como `formatters.ts` y `paths.ts` cuando sean necesarios. Las normalizaciones específicas de una configuración, un resultado de proveedor o una respuesta de GitHub pertenecen a `config/`, `providers/` o `integrations/`, respectivamente. Los helpers compartidos no dependen del workflow ni de adaptadores concretos. Evitar concentrar funciones sin relación en un único `utils.ts`.

## Acceso a SQLite

Usar `drizzle-orm` para definir el esquema en TypeScript y acceder a SQLite, y `drizzle-kit` como dependencia de desarrollo para generar migraciones. Mantener esquema, conexión y consultas en `storage/`. Las migraciones generadas se versionan con el código y forman parte de los artefactos necesarios para ejecutar la app.

El driver acordado es `better-sqlite3`, consumido por el adaptador SQLite de Drizzle. La [documentación oficial](https://orm.drizzle.team/docs/sqlite/get-started-sqlite) describe esa combinación. Los ejemplos actuales muestran releases RC: al implementar, consultar las versiones estables publicadas y sus APIs compatibles, respetando la política de excluir prereleases acordada. No asumir que una API disponible en la documentación RC ya existe en la estable. Validar instalación, migraciones y transacciones con Node 26 en macOS antes de probar el flujo de agentes.

## Logging y errores

Dependencia runtime acordada: `@ashulab/universal-logger`, el package del repo [AshuLab/universal-logger](https://github.com/AshuLab/universal-logger). El [package.json revisado](https://github.com/AshuLab/universal-logger/blob/16eabc1e3d78bf145f6619f60f5419e1565075b7/package.json) declara ese nombre y exports ESM. La versión inspeccionada es 0.1.1; fijar una versión compatible al implementar la app. La decisión es consumir el package instalado, no reproducir su formato ni copiar su código.

Configurar la biblioteca una vez al arrancar y usar su API de niveles y `createScopedLogger` en los módulos. Nivel inicial propuesto: INFO, configurable; la biblioteca usa WARN fuera de desarrollo cuando no se configura un nivel. Para errores, pasar el objeto de error original a `logError` o al método `error` del logger scoped para conservar su información y stack. Adjuntar contexto de repo, épica, ejecución, rol y etapa según corresponda, sin credenciales ni tokens. [API e implementación](https://github.com/AshuLab/universal-logger/blob/16eabc1e3d78bf145f6619f60f5419e1565075b7/src/index.ts).

`logging/` sólo integra y configura esa dependencia para la app y su salida. Los logs operativos se guardan bajo `~/.solve/orchestrator/logs/`, siguiendo la raíz configurable. Propuesta de archivos: `orchestrator.log` para el proceso y `executions/<executionId>/stdout.log` y `stderr.log` para conservar las salidas completas de cada agente. SQLite guarda conclusiones e historial de coordinación; los archivos conservan los logs detallados e informes.

La implementación revisada emite por consola: debug/info usan stdout y warn/error usan stderr. No expone un transport general a archivos; `setErrorReporter` sólo reporta errores y no reemplaza esa salida. Validar la integración de ambos streams con los archivos y el panel de terminal, manteniendo el package como implementación de logging. El panel usa el estado del orquestador y la salida detallada de agentes se captura por separado para no mezclarla con su representación visual.

## Estrategia de tests de la app

Usar Vitest en su última versión estable compatible con el stack. Probar comportamiento de coordinación: merge/validación de configuración, FIFO y concurrencia, transiciones por outcome, límites de reviews/reintentos, importación idempotente de resultados, persistencia y recuperación tras interrupciones. Usar SQLite temporal real cuando se verifiquen migraciones y transacciones, y agentes simulados para controlar respuestas, tiempos y fallos de procesos. La política de tests o CI del repo implementado sigue siendo responsabilidad de los agentes, no del motor ni de sus tests.

Las pruebas reales con Claude, Codex, Forge y Solve son integración aparte, con un repo de prueba y configuración explícita; no deben ejecutarse automáticamente en la suite habitual. Deben validar el contrato del runner, sesiones, credenciales, workspaces y entrega de resultados del caller. [Documentación de Vitest](https://vitest.dev/guide/).

## Detalles técnicos pendientes

1. Cómo comunicar a Solve la raíz compartida y convenciones acordadas; `~/.solve/` configurable, los subdirectorios y el arranque desde cualquier carpeta ya están acordados.
2. Comprobar que el cambio externo en Solve publique `solve:epic:ready` como señal de toma directa; el MVP no necesita otra consulta de disponibilidad.
3. Campos y esquema del JSON del caller; el transporte por archivo, validación, almacenamiento en SQLite e historial ya están acordados.
4. Integración de identidades personales y bots con Forge y renovación de credenciales durante ejecuciones largas. La resolución de casos que requieren intervención queda en manos de Diego, sin comando de reactivación en esta versión.
5. Estrategia para retomar trabajo interrumpido y pruebas del flujo; el panel inicial ya está definido como informativo y simple.
6. Integración de la salida de `@ashulab/universal-logger` con archivos y panel de terminal, incluyendo flush al detener el proceso; el package ya está elegido como dependencia runtime.
