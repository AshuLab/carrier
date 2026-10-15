# Agent Forge como proveedor de identidad (spike #7)

> Estado: **incompleto, detenido**. Se verificó solo lo posible en modo lectura. No hay un repo de prueba descartable verificado en este entorno, así que no se ejecutó ninguna acción contra GitHub con identidades de bots ni con el perfil personal. Los criterios sin evidencia ejecutada figuran como no verificados; nada de lo no verificado se da por cierto.

Fecha: 15/10/2026. Entorno: macOS, Node v25.6.0, `gh` 2.102.0.

## Versión de Forge usada

```
$ agent-forge --version
0.8.0
```

Instalado globalmente con pnpm (`@ashulab/agent-forge`, `package.json` de la instalación dice `"version": "0.8.0"`). La investigación previa usó el commit `8dee1b0` del repo; este spike lee el `dist/launcher.cjs` instalado (0.8.0).

## Lo verificado (lectura / sin tocar GitHub)

Perfiles registrados (`agent-forge --list`, salida real, 2 bots):

```
◇  2 agents
│  artanis-agent
│  tassadar-agent
```

Superficie CLI relevante (`agent-forge --help`):

```
agent-forge token --agent <name>   print a fresh GitHub App token (for refresh)
agent-forge gh <name> <gh args...> mint a fresh token and run gh with it
```

Se evitó leer `~/.config/agent-forge/agents.json` por contener rutas a claves privadas (el entorno bloqueó la lectura y no se la eludió); no se imprimió ninguna credencial.

### Error con perfil inexistente (observado)

```
$ agent-forge gh no-such-agent-xyz --version
exit=1   stdout: (vacío)   stderr:
│
■  Agent not found: no-such-agent-xyz

$ agent-forge token --agent no-such-agent-xyz
exit=1   stdout: (vacío)   stderr: idéntico

$ agent-forge gh no-such-agent-xyz          # sin args de gh
exit=1   stderr: ■  Usage: agent-forge gh <agent-name> <gh args...>
```

Esto no mintió ningún token ni hizo red. Todo error de Forge sale por el mismo `main().catch`: mensaje a stderr con prefijo `■  ` y **exit 1**. Es indistinguible por código de salida de un fallo de `gh` que también devuelva 1 (`gh` propaga su propio código con `process.exit(code ?? 1)`), así que el `AuthError` tipado debe basarse en el texto de stderr (ver abajo) o en el paso previo `agent-forge token`.

Trampa observada: si los argumentos llegan como un único string (por ejemplo `agent-forge "gh x --version"`) Forge cae al selector interactivo y sale con **exit 0** sin hacer nada. El orquestador debe invocar con `execFile` y argv separado, nunca por shell.

### Mecanismo de obtención y renovación (por lectura del código instalado, NO ejecutado)

En `dist/launcher.cjs` (0.8.0), `generateGithubAppToken(agent)`:

1. Lee la clave privada de `privateKeyPath`; si no se puede: `Private key for "<ref>" not found or unreadable: <path>`.
2. Firma un JWT RS256 de 10 min (`iss=appId`).
3. Resuelve la instalación: `installationId` del registro, o la del repo del `origin` del **cwd** (`/repos/{owner}/{repo}/installation`), o la única instalación de la App; con varias instalaciones y sin repo falla con `GitHub App <id> is installed on N accounts (...). Launch from inside a repo under one of them.`
4. `POST /app/installations/{id}/access_tokens` con `repositories` y `permissions` del registro, si existen.

No hay caché: cada `agent-forge token` y cada `agent-forge gh` acuñan un token nuevo (la renovación es simplemente otra llamada). El token de instalación dura ~1 h (dato de GitHub, ya citado en la investigación previa). `gh` hijo recibe `GH_TOKEN` y `GITHUB_TOKEN`, `stdio` heredado y `shell:false`; el único aviso es una línea en stderr `minted fresh token for <agent> · scope: ...`. Los errores de GitHub salen como `GitHub API <path>: <status> <message>`; con 401 sobre el JWT añade `— the App JWT was rejected. Check that appId matches privateKeyPath ...`.

Implicancia para el runner: un proceso lanzado con un token en el entorno no se renueva solo. Para ejecuciones de hasta 4 h, `gh` debe invocarse siempre vía `agent-forge gh` (token fresco por llamada) o el adaptador debe reacuñar con `agent-forge token --agent` antes de ~1 h.

### Perfil personal

Forge solo tiene un camino de credenciales: tokens de GitHub App (`generateGithubAppToken`). No existe un modo "usuario personal". Conclusión (por lectura del código y `--help`): **no soportado por Forge**. El perfil personal de Diego se obtiene con el login propio de `gh` (`gh auth status`: cuenta `vemec`, token en keyring, scopes `gist, read:org, repo, workflow`) y no pasa por Forge. Evidencia de commit/comentario como Diego: no ejecutada.

## No verificado (requiere repo de prueba descartable)

Consultados en modo lectura, `AshuLab` solo tiene repos reales o públicos (`carrier`, `skills`, `agent-forge`, `universal-logger`, `codegraph`, `peloton-fit`, `ashulab-landing`, `financial`); ninguno es un repo de prueba. No se creó uno (la tarea prohíbe repos públicos o nuevas identidades) ni se actuó sobre repos reales.

- `agent-forge gh <bot> issue comment|label ...` y un commit con autoría del bot en un repo de prueba.
- Lo mismo con el perfil personal.
- Segunda obtención de token pasado el vencimiento: se puede demostrar sin esperar una hora llamando dos veces a `agent-forge token --agent <bot>` (stdout con el token redactado, comparar `expires_at`/valor), pero requiere acuñar tokens reales de los bots; no se hizo.
- Error de autenticación con un perfil **revocado** (clave o instalación revocada): requiere un bot de prueba revocado. No se debe revocar ninguno real.
- `agent-forge gh <orquestador> issue list --label ... --json ...` y cambio de labels sobre un repo de prueba.

## Propuesta (sin validar contra GitHub)

Forma de cada entrada de `profiles`:

```json
"profiles": {
  "author-bot":   { "kind": "forge", "agent": "artanis-agent" },
  "reviewer-bot": { "kind": "forge", "agent": "tassadar-agent" },
  "diego":        { "kind": "gh" }
}
```

Comando exacto para invocar `gh` vía Forge, con `execFile` sin shell y `cwd` en un repo de la instalación correcta:

```
execFile("agent-forge", ["gh", "<agent>", ...ghArgs], { cwd, timeout })
```

Para `kind: "gh"` se ejecuta `gh` directo. `AuthError` se derivaría de exit 1 más stderr que empiece con `■  ` y coincida con `Private key for`, `GitHub API ... 401|403|404` o `Agent not found`; la forma exacta del caso revocado queda sin confirmar. El ejemplo del spec (`"author-bot": {}`) no se cambia hasta confirmar la forma con las pruebas pendientes.

## Para cerrar

Diego debe proveer un repo de prueba privado descartable en el que ambos bots (o uno de prueba) estén instalados, confirmar que se puede actuar con `vemec` ahí, y autorizar el uso de un bot de prueba (revocable) para el caso de error de credenciales revocadas.
