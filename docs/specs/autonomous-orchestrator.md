# Carrier — Orquestador de épicas autónomas

Status: spec

## Problem

Diego quiere dedicar tiempo a preparar varias ideas, specs y tickets con Solve mientras agentes implementan el trabajo ya preparado. Hoy necesita encadenar manualmente implementación, revisión externa y correcciones para llegar a un PR que pueda probar. El objetivo es delegar esa coordinación sin delegar su decisión de probar y mergear el PR final.

El resultado esperado es que una épica marcada `solve:epic:ready` entre en ejecución sin seguimiento manual entre turnos, termine con un PR final listo para probar o un motivo explícito de intervención, y pueda continuar tras interrumpir el proceso. Varias épicas pueden avanzar en paralelo dentro de una concurrencia configurada. Las definiciones y decisiones detalladas están en el [documento de trabajo](../autonomous-orchestrator.md) y el [glosario](../glossary.md).

## Solution

Una app independiente en TypeScript sobre Node.js 26, con ESM y pnpm, inicialmente para macOS. Se inicia desde cualquier carpeta, lee una lista de repos GitHub y permanece corriendo con un panel informativo en la misma terminal. Se eligió este alcance para probar el flujo antes de invertir en una UI web o app del OS. Diego decidió construir el alcance completo descrito abajo (catálogo de n identidades, overrides por repo, retención de logs, tiempo `unlimited`); se evaluó recortarlo a dos identidades fijas y configuración global, y se descartó.

### Arranque, instancia única y configuración

Una sola instancia activa por carpeta `orchestrator/`: antes de iniciar trabajo la app toma un bloqueo exclusivo. Una segunda instancia informa que ya está corriendo y termina. Un cierre inesperado no deja el bloqueo trabado, y dos arranques simultáneos no pueden tomarlo a la vez.

La app incluye una configuración default y admite un archivo JSON del usuario que la sobrescribe: los objetos se combinan por campo, los valores simples del usuario reemplazan los defaults y las listas se reemplazan completas; un tipo incompatible no se convierte en silencio. La configuración resultante se valida al arrancar con Zod, con errores que nombran el campo y el problema, y los tipos TypeScript se infieren de esos esquemas. Se validan campos requeridos, tipos, límites permitidos y referencias entre perfiles, repos y roles.

Identidad (perfil GitHub), proveedor y modelo de autor y reviewer tienen valores globales y overrides por repo; cada repo hereda lo que no reemplaza. El autor y el reviewer de un mismo PR deben tener perfiles distintos después de resolver los overrides. El usuario declara los perfiles disponibles, incluido el personal de Diego, y elige el perfil del orquestador para leer issues y actualizar etiquetas; puede reutilizar uno de los de agentes. Agent Forge resuelve la autenticación de cada perfil. Al iniciar una épica se guarda su configuración efectiva, sin credenciales, y la conserva al retomar aunque cambien los defaults. Los proveedores iniciales son Claude y Codex.

Los límites iniciales, todos configurables, son tres épicas simultáneas, cinco reviews, tres reintentos de ejecución, cuatro horas por ejecución de agente (o `unlimited`; cero no significa infinito) y 30 s por llamada corta a GitHub o Forge.

### Descubrimiento y cola

Cada 5 minutos por defecto (configurable, también la espera antes de la primera consulta al arrancar) la app consulta todos los repos configurados, recorre todas las páginas y registra en SQLite las épicas abiertas con `solve:epic:ready` que no conoce. La épica se identifica por repo e issue. La etiqueta es suficiente para encolar; no hay webhooks ni intervalos adaptativos. El orden de selección es FIFO por ingreso a la cola y se conserva al reiniciar. Solve agrega esa etiqueta al terminar su preparación, en sus skills y fuera de esta app.

Si GitHub está caído o limita las consultas, se conservan cola y estado, se muestra el error y se reintenta en el siguiente intervalo, o después de la espera mayor que indique GitHub. Una consulta fallida nunca equivale a una lista vacía y no consume reintentos de agentes. Cada llamada a GitHub se ejecuta con un timeout corto.

### Ejecución y loop de etapas

Cuando hay un slot libre, el scheduler reserva la épica más antigua con una operación atómica en SQLite; una épica nunca tiene dos ejecuciones activas. Al reservarla comprueba que el issue siga abierto y ready, la pasa a `solve:epic:running` y persiste el inicio. El tiempo en cola no cuenta para el límite de ejecución.

El autor invoca `ship` con la identidad, el proveedor, el modelo y el contexto de la épica y deja el PR final de integración. Después el reviewer, con otra identidad y un checkout separado, recibe spec, tickets, PR, SHA y contexto de rondas anteriores, revisa con `code-review` y publica los findings con `code-post`. Si hay blockers y quedan rondas, el autor corrige o responde cada finding y el reviewer vuelve a revisar, verificando correcciones y regresiones. Los skills conservan sus informes; el agente caller los interpreta y entrega un archivo JSON de resultado por ejecución. El loop avanza cuando llega ese resultado, sin esperar el intervalo de consulta.

El motor combina la etapa con el resultado del caller:

| Etapa | Resultado | Siguiente paso |
| --- | --- | --- |
| `ship` | `completed` | review, ronda 1 |
| `review` | `completed` (concluyente, sin blockers, verificaciones confirmadas sobre el commit revisado) | `solve:epic:ready-for-test` |
| `review` | `changes_requested` | `fix` si la ronda es menor al máximo; si no, `needs_human` |
| `fix` | `completed` | review, ronda siguiente |
| cualquiera | `needs_human` | `solve:epic:needs-human` con el motivo |

Una revisión inconclusa por falta de contexto es `needs_human` del reviewer. Un commit nuevo invalida el veredicto anterior: no se declara listo un commit que no fue revisado. Cada resultado importado se valida contra GitHub: el PR existe, está abierto, referencia la épica y su head coincide con el SHA informado. Si la referencia no coincide, o el head cambió durante una revisión, la épica pasa a `needs_human` con ese motivo; repetir la ejecución no lo arregla.

Autor y reviewer aplican las reglas del repo para elegir y evaluar tests, CI y blockers; el motor no lo hace ([ADR 0001](../adr/0001-separar-coordinacion-y-evaluacion-del-repo.md)). Las correcciones y repeticiones de tests/CI son trabajo interno del agente y el motor no las cuenta. En un repo sin CI alcanzan la revisión y la evidencia de tests que reportan los skills, y la ausencia de CI queda registrada. Diego prueba el PR y decide el merge.

Fallos técnicos (el proceso o el contenedor termina mal, JSON ausente o inválido, error de transporte) se reintentan hasta el límite configurado, después del intento inicial. El reintento es una ejecución nueva que retoma la sesión (o reconstruye el contexto) con la instrucción de verificar primero el estado real, para no duplicar PRs, comentarios ni commits. No consume rondas de review. Agotar los reintentos, vencer el límite de tiempo de una ejecución o agotar las rondas termina en intervención humana; el timeout no se reintenta. Un finding o un desacuerdo no es un fallo técnico.

### Salidas de la épica

`solve:epic:ready-for-test` y `solve:epic:needs-human` reemplazan a `solve:epic:running` en el issue. Una épica en intervención humana queda detenida con su motivo mientras las demás avanzan; Diego la resuelve fuera de Carrier y no se reactiva desde la app ni al reiniciar.

Si el PR final se mergea mientras hay trabajo activo, se detienen sus ejecuciones, se conservan sesiones e historial y no se lanzan turnos nuevos. Si se cierra sin merge el issue de la épica o su PR final, la épica queda cancelada: se detienen sus agentes, se conserva lo realizado y se muestra el motivo en terminal. Ni los merges ni los cierres de slices hechos por `ship` disparan estas reglas. La comprobación de estado del PR es coordinación técnica, no evaluación de código.

Un error de autenticación informado por Forge para un perfil detiene las épicas que lo usan, con el motivo en terminal; las demás continúan. Si falla el perfil del orquestador se suspenden sus operaciones GitHub. Nunca se cambia de perfil automáticamente.

### Agentes aislados

Cada ejecución de agente corre dentro de un contenedor, con permisos amplios adentro y solo el workspace de la épica, lo necesario para Git y las sesiones montados. El contenedor no limita lo que el agente hace en GitHub con su token, así que los scopes mínimos por rol y la branch protection de los repos son el segundo límite. Se descartaron los permisos restringidos del CLI sobre el host y el sandbox nativo de los CLIs como límite principal. Ver [ADR 0003](../adr/0003-agentes-en-contenedor.md).

El runner es propio, con un adaptador por proveedor que traduce la tarea al CLI, prepara las credenciales de esa ejecución sin mezclarlas con las de otra paralela y captura salida, sesión y errores. Agent Forge es una dependencia externa para identidad y credenciales; no se incorpora una copia. Las operaciones GitHub del orquestador pasan por el perfil elegido, con `gh` vía Forge.

### Raíz compartida, estado y logs

Solve y la app comparten una raíz configurable, por defecto `~/.solve/`: `repos/` para clones (separados por organización y nombre), `worktrees/` para los workspaces que administra Solve y `orchestrator/` para SQLite, sesiones y logs. Se comparten las rutas para reutilizar el trabajo de Solve en vez de crear otra estructura de worktrees. La ubicación del código de la app es independiente de la raíz.

SQLite, con Drizzle ORM, `better-sqlite3` y migraciones versionadas de Drizzle Kit, es la autoridad del estado; las etiquetas son su reflejo y se reconcilian al arrancar y tras un fallo ([ADR 0002](../adr/0002-sqlite-autoridad-etiquetas-reflejo.md)). Se guarda por épica: repo e issue, ingreso a la cola, workspace, PR final, etapa, ronda, configuración efectiva, SHA revisado, blockers, ejecuciones con su sesión, errores, resultados del caller e historial de eventos. Importar un resultado y registrar la transición ocurren en una sola transacción y son idempotentes. No se guardan tokens en el estado ni en los logs.

La app usa `@ashulab/universal-logger` como logger, sin construir otro. Una integración central lo configura y añade contexto de repo, épica, ejecución, rol y etapa. Los logs del proceso van a `orchestrator/logs/orchestrator.log` y la salida completa de cada agente a `orchestrator/logs/executions/<executionId>/`, separados de SQLite y del panel. Los logs y sesiones de una épica se borran 30 días después de que termina o se cancela; mientras siga pendiente, interrumpida o en intervención se conservan. La limpieza no toca SQLite ni los workspaces.

### Interrupción y recuperación

`Ctrl+C` detiene las ejecuciones activas, con sus contenedores, sin esperar a que terminen las etapas. Se conservan sesiones, contexto, workspaces y trabajo sin commit. Al reiniciar se reconcilian procesos y efectos externos contra GitHub antes de continuar y una etapa interrumpida no se reinicia a ciegas. Si la sesión no se puede recuperar, se abre una nueva con la misma identidad, el contexto persistido y el estado real del workspace y GitHub, y el agente verifica qué quedó hecho; la recuperación queda en el historial.

Si un repo se quitó de la configuración, al reiniciar sus épicas pendientes quedan detenidas con ese motivo, conservando sesiones, workspaces, historial y orden, sin consumir reintentos ni actuar sobre el repo. Al volver a configurarlo se recuperan, salvo las que ya requerían intervención humana.

### Panel de terminal

Un panel informativo dibujado con secuencias ANSI sin dependencias, en la misma terminal. Muestra slots ocupados, épicas en cola y, por épica, etapa, ronda, blockers, tiempo en la etapa, última actividad, links al issue y PR, errores y motivos de intervención. La etapa y la última actividad son datos distintos. Sin terminal interactiva emite líneas simples. No tiene controles; `Ctrl+C` detiene el proceso.

## Scope

1. Ejecuto `carrier` desde cualquier carpeta con mi archivo de configuración y la app arranca con la configuración efectiva (defaults más lo mío), sin depender del directorio actual.
2. Si la configuración es inválida (campo ausente, tipo incorrecto, referencia a un perfil inexistente, autor y reviewer con el mismo perfil), la app imprime cada error con el campo y termina sin iniciar trabajo.
3. Defino overrides de identidad, proveedor y modelo por repo y la épica queda con la configuración efectiva con la que inició, también al retomar tras cambiar la configuración.
4. Si ya hay una instancia corriendo sobre la misma carpeta, la segunda informa y termina; si la anterior se cerró de golpe, la siguiente arranca.
5. Cada intervalo la app registra, una sola vez y en orden de llegada, las épicas abiertas con `solve:epic:ready` de todos los repos configurados, aunque haya más de una página de resultados.
6. Si GitHub falla o limita las consultas, la cola y el estado se conservan, el error se muestra y se reintenta en el siguiente intervalo o tras la espera que indique GitHub, sin consumir reintentos de agentes.
7. Cuando hay un slot libre se inicia la épica más antigua en cola, nunca más de la concurrencia configurada ni dos ejecuciones de la misma épica, y el issue pasa de `ready` a `running`.
8. Al iniciar, la app crea en cada repo configurado las etiquetas `running`, `ready-for-test` y `needs-human` que falten.
9. El autor ejecuta `ship` en un contenedor aislado con el workspace de la épica y el motor registra el PR final validado contra GitHub.
10. El reviewer, con otra identidad y un checkout separado, revisa el PR final y su resultado `completed` deja la épica en `ready-for-test` solo si el SHA revisado es el head actual del PR.
11. Si el reviewer pide cambios y quedan rondas, el autor recibe un turno de corrección y el reviewer vuelve a revisar; con la última ronda agotada la épica pasa a `needs-human`.
12. Un resultado `needs_human` del autor o del reviewer, incluida una revisión inconclusa, detiene la épica con el motivo mientras las demás siguen.
13. Una referencia que no coincide (PR de otra épica, PR cerrado, SHA que no es el head, head que cambió durante la revisión) detiene la épica en `needs-human` con ese motivo.
14. Un fallo técnico se reintenta hasta el límite configurado con una ejecución que verifica el estado real antes de continuar, sin consumir rondas y sin duplicar PRs, comentarios ni commits; al agotarse, la épica pasa a `needs-human`.
15. Un resultado JSON ausente, incompleto o inválido no avanza la etapa y se trata como fallo técnico; importar el mismo resultado dos veces no duplica la transición.
16. Una ejecución que supera el límite de tiempo (o ninguno con `unlimited`) se detiene, conserva sesión y workspace y deja la épica en `needs-human`, sin reintento.
17. Si el PR final se mergea con trabajo activo la épica se detiene sin lanzar turnos nuevos, y si se cierra sin merge el issue o ese PR la épica se cancela con el motivo en terminal; los merges y cierres de slices no afectan.
18. Un error de autenticación de Forge detiene solo las épicas del perfil afectado; si es el del orquestador, se suspenden sus operaciones GitHub, y no se cambia de perfil.
19. Con `Ctrl+C` las ejecuciones activas y sus contenedores se detienen sin esperar y se conservan sesiones, workspaces y trabajo sin commit.
20. Al reiniciar, las etapas interrumpidas se reconcilian con GitHub y los procesos existentes y se retoman con la sesión, o con un contexto reconstruido si no se puede recuperar, sin duplicar agentes ni acciones; las épicas en `needs-human` no se reactivan.
21. Si quito un repo de la configuración, al reiniciar sus épicas pendientes quedan detenidas con el motivo y se recuperan al volver a configurarlo, salvo las que requerían intervención.
22. Veo en el panel slots, cola y, por épica, etapa, ronda, blockers, tiempo en etapa, última actividad, links, errores y motivos de intervención; sin terminal interactiva obtengo líneas simples.
23. Los logs del proceso y la salida completa de cada ejecución quedan en archivos bajo la raíz, sin tokens y sin interferir con el panel.
24. Los logs y sesiones de una épica terminada o cancelada se borran 30 días después; los de una épica pendiente, interrumpida o en intervención se conservan, y SQLite y los workspaces no se tocan.

## Decisions

Los skills y los repos mantienen sus reglas y formatos; las decisiones de coordinación están en [ADR 0001](../adr/0001-separar-coordinacion-y-evaluacion-del-repo.md), [ADR 0002](../adr/0002-sqlite-autoridad-etiquetas-reflejo.md) y [ADR 0003](../adr/0003-agentes-en-contenedor.md), que no se repiten aquí.

**Estructura.** Un único paquete, agrupado por responsabilidad: `cli/`, `config/`, `orchestration/`, `execution/`, `storage/`, `logging/`, `integrations/`, `providers/`, `prompts/`, `shared/` y `test/`. Los archivos se crean al implementar cada responsabilidad. `shared/` solo tiene utilidades realmente compartidas (formateo de duraciones, rutas); no hay un `utils.ts` general. `config/` es dueño del esquema de configuración y `execution/` del del resultado del caller.

**Versiones.** Se toma la última versión estable de TypeScript, pnpm y cada dependencia al implementar o actualizar, sin prereleases, se comprueba compatibilidad con Node 26 y se versiona `pnpm-lock.yaml` con `packageManager` fijado. Las dependencias de runtime son `zod`, `@ashulab/universal-logger`, `drizzle-orm` y `better-sqlite3`; el tooling incluye `drizzle-kit` y `vitest`. Drizzle, Drizzle Kit y `better-sqlite3` se instalan y se prueban en macOS antes de construir sobre ellos, porque su documentación actual muestra releases RC.

**Instancia única.** El bloqueo es una transacción exclusiva de SQLite sobre un archivo de bloqueo en `orchestrator/`, sin espera, que mantiene el proceso mientras corre. La suelta el sistema operativo al morir el proceso, así que no hay bloqueos residuales que distinguir. Un segundo intento recibe `SQLITE_BUSY` y termina.

**Puertos del motor.** El motor (`orchestration/`) depende de dos interfaces, `GitHub` y `AgentRunner`, y de un reloj inyectado. `GitHub` expone lo que el motor necesita: listar épicas ready, cambiar etiquetas, leer estado de issue y PR. `AgentRunner` lanza una ejecución con tarea, perfil y límite de tiempo, y devuelve su sesión, su terminación técnica y la ruta del JSON, y puede detenerla. Existen para poder probar el motor con fakes; hay una sola implementación real de cada una. La implementación real de `GitHub` ejecuta `gh` vía Forge con `execFile`, sin shell, y valida las respuestas con Zod.

**Estados.** Una épica está en `queued`, `running` (con su etapa y ronda), `ready_for_test`, `needs_human`, `cancelled`, `merged` o `repo_removed`. Una ejecución está en `running`, `finished`, `failed`, `timed_out`, `interrupted` o `invalid_result`. La interrupción por `Ctrl+C` deja la épica en `running` con su ejecución en `interrupted`; `repo_removed` no cambia etiquetas.

**Contrato del resultado del caller.** El caller devuelve exactamente uno de los tres resultados. `executionId`, `repo`, `epic` y `stage` repiten lo que el motor esperaba, para comprobar la correspondencia. `changes_requested` solo es válido en `review`. Un `completed` lleva el resultado de las verificaciones, y el CI puede ser `absent`; un CI fallido no es un `completed`. La validación se probó con entradas vacías, de tipo incorrecto, SHA corto o en mayúsculas, número 0 o no entero, `repo` con barras de más o salto de línea, `blockers` vacío y `changes_requested` fuera de `review`; todas se rechazan.

```ts
const Sha = z.string().regex(/^[0-9a-f]{40}$/);
const Pr = z.object({ number: z.number().int().positive(), headSha: Sha });
const Common = {
  executionId: z.string().min(1),
  repo: z.string().regex(/^[\w.-]+\/[\w.-]+$/),
  epic: z.number().int().positive(),
  stage: z.enum(['ship', 'review', 'fix']),
  summary: z.string().min(1),
};
export const CallerResult = z.discriminatedUnion('outcome', [
  z.object({ ...Common, outcome: z.literal('completed'), pr: Pr,
    verification: z.object({ ci: z.enum(['passed', 'absent']), evidence: z.string().min(1) }) }),
  z.object({ ...Common, outcome: z.literal('changes_requested'), stage: z.literal('review'), pr: Pr,
    blockers: z.array(z.object({ title: z.string().min(1), url: z.string().url().optional() })).min(1) }),
  z.object({ ...Common, outcome: z.literal('needs_human'), reason: z.string().min(1) }),
]);
```

**Configuración.** Los defaults de la app incluyen la raíz, el intervalo, el nivel de log (`logLevel`, `info`) y los límites; perfiles, repos y asignaciones por rol los declara siempre el usuario. Cada perfil es `{ "kind": "forge", "agent": "<nombre en Forge>" }` (bot, vía Agent Forge) o `{ "kind": "gh" }` (el login propio de `gh`, para la cuenta personal que Forge no soporta); sin secretos en la configuración. La forma la fijó el [spike de Forge](../research/agent-forge.md). Ejemplo de la forma, no de valores:

```json
{
  "pollIntervalMinutes": 5,
  "repos": [{ "name": "AshuLab/carrier", "agents": { "reviewer": { "model": "<modelo>" } } }],
  "profiles": {
    "author-bot":   { "kind": "forge", "agent": "<agente-forge-autor>" },
    "reviewer-bot": { "kind": "forge", "agent": "<agente-forge-reviewer>" },
    "diego":        { "kind": "gh" }
  },
  "orchestratorProfile": "author-bot",
  "agents": {
    "author":   { "profile": "author-bot",   "provider": "claude", "model": "<modelo>" },
    "reviewer": { "profile": "reviewer-bot", "provider": "codex",  "model": "<modelo>" }
  },
  "limits": { "maxConcurrentEpics": 3, "maxReviews": 5, "maxExecutionRetries": 3, "maxExecutionHours": 4, "githubCallTimeoutSeconds": 30 }
}
```

**Etiquetas.** Carrier es dueño de `solve:epic:running`, `solve:epic:ready-for-test` y `solve:epic:needs-human` y las crea en los repos configurados si faltan; `solve:epic:ready` es de Solve y no se crea.

**Panel.** Se dibuja con secuencias ANSI de la biblioteca estándar, sin dependencias de TUI.

**Testing seams.** No hay código todavía, así que no hay seams existentes. Se eligen los más anchos que aíslan cada historia:

- Historias 1 a 3: `loadConfig(defaults, user)` es una función pura que devuelve la configuración efectiva o la lista de errores por campo. Tests unitarios con Vitest; cubren merge de objetos, valores y listas, tipo incompatible, referencias y la regla autor distinto de reviewer.
- Historia 4: la función que toma el bloqueo, sobre una carpeta temporal real, con dos procesos hijos y uno terminado con `kill -9`.
- Historias 5 a 21, salvo la 9 (que solo cubre aquí la parte de coordinación): el motor por su interfaz pública, con `GitHub` y `AgentRunner` simulados, un reloj inyectado y SQLite temporal real con migraciones. Un fake de `AgentRunner` escribe el JSON, falla, se cuelga o se corta según el caso. Reiniciar el motor sobre la misma base cubre recuperación y reconciliación.
- Historias 10 a 15: dentro del mismo seam, además de la interfaz pública del motor, `parseCallerResult(raw, expected)` es una función pura con la tabla de casos de la sección de contrato.
- Historia 9: la coordinación (lanzar la etapa, validar el PR contra GitHub, registrarlo) se prueba en el mismo seam del motor con `AgentRunner` simulado. Correr `ship` en un contenedor real y los adaptadores reales de Claude y Codex, Forge y logs se verifican en la integración aparte, con un repo de prueba y configuración explícita.
- Historia 22: `renderPanel(snapshot)` devuelve texto y se prueba por su salida; el dibujo en la terminal real no tiene test.
- Historia 23: sin tests automáticos en la suite habitual; es una integración fina cuyo comportamiento real se valida en el spike de logs.
- Historia 24: la función de limpieza con fecha inyectada sobre una carpeta temporal.

La política de tests o CI del repo que los agentes implementen no es parte de estos tests. Las pruebas con Claude, Codex, Forge, contenedores y Solve reales son una integración aparte y no corren en la suite habitual.

## Out of scope

UI web, app del OS, controles interactivos en el panel, comandos de reactivación de casos que requieren intervención y soporte inicial de Linux/Windows. El motor se mantiene portable, pero el soporte adicional requiere validación.

Merge automático del PR final, reproducir políticas del repo dentro del motor, cambiar los informes actuales de los skills o incorporar una copia de Agent Forge. `ship` conserva su flujo de slices; el loop de revisión de esta app trabaja sobre el PR final de la épica.

Dependencias entre épicas y desbloqueo por merge. Ese trabajo se resolverá en Solve por separado; esta versión toma directamente las épicas ready.

## Open questions

Son validaciones técnicas que solo una prueba con las herramientas reales puede responder; ninguna es una decisión de producto. Cada una se convierte en un spike con un criterio de éxito claro, y su resultado puede cambiar las decisiones de arriba. Las dos primeras (agentes headless y contenedores) condicionan el resto: si fallan, cambia el diseño del runner o de la identidad.

Claude y Codex headless. Comprobar que ambos ejecutan el flujo de skills sin interacción, exponen y conservan sus sesiones, retoman tras una interrupción y entregan el JSON del caller. Incluir el trabajo delegado por `ship` y comprobar que detener el proceso alcanza a sus procesos hijos sin perder lo necesario para reconstruir el contexto.

Resultado (15/10/2026, [investigación](../research/headless-agents.md)): ambos CLI ejecutan un skill sin interacción, exponen su id de sesión, retoman tras un corte y escriben un JSON que valida contra `CallerResult`. Matar el CLI no mata siempre a sus hijos: Codex deja huérfano el proceso del comando incluso con `SIGTERM`, y ambos con `SIGKILL`, por lo que la detención depende del contenedor ([ADR 0003](../adr/0003-agentes-en-contenedor.md)). El adaptador debe invocar el binario real, cerrar stdin (`</dev/null`), pasar `--add-dir` para rutas fuera del workspace y usar `-c sandbox_mode=...` en `codex exec resume`.

Agentes en contenedores. Probar el runtime de contenedores en macOS con Claude y Codex: montaje del workspace y del clon para que los worktrees de Solve y Git funcionen, login y sesiones persistentes dentro, renovación del token de Forge en ejecuciones de hasta cuatro horas, toolchains para los tests del repo, la salida a red mínima que necesitan y que detener el contenedor termine todos los procesos. Si no es viable, Diego elige entre las alternativas del ADR.

Agent Forge. Validar el adaptador para identidades de bots y personales, especialmente la renovación de credenciales durante ejecuciones largas, y que `gh` vía Forge sirva para las operaciones del orquestador. La [investigación previa](../research/autonomous-ship-review.md) identificó que el launcher observado no implementaba nuestro contrato de tareas headless; la app debe integrar las capacidades de identidad sin asumir que ese launcher ya resuelve el runner.

Raíz compartida con Solve. Probar la raíz compartida, la creación y reutilización de worktrees y dos épicas simultáneas desde un clon administrado. Comprobar que el material preparado antes de ready sea accesible al caller y que las sesiones puedan continuar en las mismas rutas. Mientras Solve no agregue `solve:epic:ready` por su cuenta, la etiqueta se puede poner a mano para esta prueba.

Recuperación ante cortes. Probar interrupciones entre publicación en GitHub y persistencia local, incluyendo un JSON incompleto. Verificar que se importen resultados una sola vez y se retome el trabajo sin duplicar agentes, PRs, comentarios ni cambios de estado.

Logs y panel. Validar cómo dirigir stdout y stderr de `@ashulab/universal-logger` a archivos sin interferir con el panel de terminal. El package revisado escribe por consola y no ofrece un transport general; la integración debe reutilizar la biblioteca como implementación de logging y conservar la salida al detener el proceso.

Resultado (15/10/2026, [investigación](../research/logging-panel.md), `@ashulab/universal-logger` 0.1.1): reemplazar `console.log/info/warn/error/debug` por escrituras síncronas (`writeSync`) a un archivo en append alcanza: el panel recibe solo sus bytes y `Ctrl+C` no pierde logs, con o sin handler de `SIGINT`. `logError` con `Error` conserva el stack en el campo `stack`. La biblioteca no necesita cambios, pero la integración debe fijar `NODE_ENV` distinto de `development` (emite varias líneas por log), agregar el nivel desde el método de `console` (el JSON no lo trae) y usar `logError` o `scoped.error` para errores con stack (`scoped.info/warn` con `Error` lo pierde).
