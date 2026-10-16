# Repo de prueba `AshuLab/carrier-sandbox`

Repo privado y descartable para probar Carrier y los skills de Solve de punta a punta (spike #8; el slice #33 lo reutiliza para sembrar sus propias épicas). Rama por defecto `main`. Los dos bots de Forge (`artanis-agent`, `tassadar-agent`) tienen acceso. Solo se escribe ahí: nada de esto toca otro repo.

## Qué contiene

- Un proyecto Node sin dependencias: `package.json` (`"type": "module"`, `test` = `node --test`), `greet.js` + `greet.test.js`, `.gitignore` (`node_modules`), `AGENTS.md` (convenciones y bloque `## solve skills`) y `README.md` con una sección `## Functions` (una línea por función; es el punto de conflicto deliberado entre épicas).
- `docs/agents/solve.md` y `docs/agents/solve-flow.md`, escritos por el skill `setup` real: GitHub Issues, tipo de rama `feat`, base y destino `main`, Worktrees **on**, path `<raíz>/worktrees/<repo>/<feature>/` (absoluto, con `<repo>` y `<feature>` literales), sin bootstrap.
- Etiquetas: `solve:epic`, `solve:ticket`, `solve:refined`, `solve:raw` (las crea `setup`) y `solve:epic:ready` (a mano, `#fbca04`).
- Dos épicas de ejemplo, con sus specs en `docs/specs/farewell.md` y `docs/specs/shout.md`, comiteadas en `main` antes de poner `ready`: `#1 Farewell` (slices `#3` y `#4`, `#4` bloqueado por `#3`) y `#2 Shout` (`#5` y `#6`, `#6` bloqueado por `#5`). Más `#13`, un slice extra de `#1` para probar la reutilización. Sus PR (slices mergeados, integración `#11` y `#12` en borrador) y ramas `feat/farewell/epic`, `feat/shout/epic` quedan como evidencia; ver [shared-root.md](shared-root.md) §6.
- Commits de `main`: `89d89a4` (proyecto + `AGENTS.md`), `2fe4983` (`setup`), `c423756` (specs).

## Cómo se sembró

`<root>` es un directorio que elegís (la corrida real usó un `mktemp -d` fuera de `~/.solve`). Node 26 y `pnpm`; `gh` con login y permiso de escritura en el repo, sin tokens en el clon.

```sh
R=AshuLab/carrier-sandbox; ROOT=$(mktemp -d)/solve-root
mkdir -p $ROOT/repos/AshuLab && cd $ROOT/repos/AshuLab && gh repo clone $R && cd carrier-sandbox

# 1. Proyecto: package.json, greet.js, greet.test.js, AGENTS.md, .gitignore y la sección ## Functions del README
#    (los archivos están en `main`: git show 89d89a4)
git add -A && git commit -m "chore: seed sandbox project (greet + test, AGENTS.md)" && git push origin main

# 2. setup real de Solve, sin preguntas: las respuestas van en el prompt (31 s, ~USD 0,20 con Sonnet)
~/.local/bin/claude -p "/solve:setup Run non-interactively, nobody can answer questions; use exactly these answers. GitHub remote is $R. Context file: AGENTS.md (already exists). Anything particular: nothing. Worktrees: mode ON, path $ROOT/worktrees/<repo>/<feature>/ (absolute, keep <repo> and <feature> as literal tokens), bootstrap: none (no dependencies), linked config: none. Branch type: feat. Base and destination: main. Repo notes: none. I confirm the final values. Commit the files on main as 'chore: set up the solve skills' and push to origin main. Create the labels in GitHub too." \
  --model sonnet --permission-mode bypassPermissions --output-format json </dev/null

# 3. La etiqueta que Solve todavía no crea
gh label create solve:epic:ready --repo $R --color fbca04 --description "Epic ready for Carrier (set by hand until Solve adds it)" --force
```

Para el `claude` usar el binario real (`~/.local/bin/claude`), no el wrapper de Superset del `PATH`.

## Crear una épica de prueba nueva

Lo mismo que producen `to-spec` y `to-tickets`, escrito a mano para que sea determinista:

1. Spec en `docs/specs/<feature>.md` con `Status: spec` y las secciones Problem, Solution, Scope, Decisions, Out of scope. Comitearlo y pushearlo a `main` **antes** de poner `ready` (si no, el workspace no lo ve; ver [shared-root.md](shared-root.md) §3).
2. Épica: `gh issue create --repo $R --title "<Feature>" --body-file <spec sin H1 ni Status> --label solve:epic`. El `<feature>` de las ramas y del worktree sale del título (slug en minúsculas).
3. Slices en orden topológico, cada uno con `# NNN - título`, Goal, Context, **Definition of done** (cada casilla verificable con `pnpm test` o mirando un archivo) y Blocked by: `gh issue create --repo $R --title "<título>" --body-file <ticket> --label solve:ticket,solve:refined --parent <épica> [--blocked-by <n>]`. Esperar un par de segundos entre `create` para no chocar con el rate limit.
4. Ponerla en cola de Carrier con `gh issue edit <épica> --repo $R --add-label solve:epic:ready`.
5. Para probar solo `ship`, sin Carrier, desde el clon (cada épica en su proceso, en paralelo si querés):

```sh
cd $ROOT/repos/AshuLab/carrier-sandbox && ~/.local/bin/claude -p "/solve:ship drain epic #<n> of AshuLab/carrier-sandbox (the repo in the current directory). Worktree this epic. Run unattended: nobody can answer questions, decide from the skill's own rules. Leave the integration PR as a draft and do not merge it." \
  --model sonnet --permission-mode bypassPermissions --output-format stream-json --verbose --max-budget-usd 4 </dev/null
```

Una épica de 2 slices triviales tarda unos 3 min y cuesta ~USD 0,5. Para que dos épicas choquen a propósito, que ambas agreguen una línea a `## Functions` del README: nada falla en el drenaje, el conflicto sale al integrarlas.

## Reiniciarlo

No se corrió: el estado de la corrida de #8 se dejó como evidencia. Es descartable, así que se puede forzar. Cada paso solo toca este repo.

```sh
R=AshuLab/carrier-sandbox
# PR abiertos y ramas de las épicas
gh pr list --repo $R --state open --json number --jq '.[].number' | xargs -I{} gh pr close {} --repo $R --delete-branch
git ls-remote --heads https://github.com/$R.git 'refs/heads/feat/*' | awk '{sub("refs/heads/","",$2); print $2}' | xargs -I{} git push origin --delete {}
# issues: borrarlos (hace falta admin) o cerrarlos
gh issue list --repo $R --state all --limit 200 --json number --jq '.[].number' | xargs -I{} gh issue delete {} --repo $R --yes
# main vuelve a la siembra + setup (sin specs)
git fetch origin && git push --force origin 2fe4983:main
```

Después, en un clon nuevo: **editar la línea `path` de `## Worktrees` en `docs/agents/solve.md`** para que apunte al `<root>` nuevo (`sed -i '' "s#^- \*\*path\*\* - .*#- **path** - \`$ROOT/worktrees/<repo>/<feature>/\`#" docs/agents/solve.md`), comitear y pushear a `main` (`ship` corta las épicas desde `origin/main`), y seguir con [Crear una épica de prueba nueva](#crear-una-épica-de-prueba-nueva). El path es absoluto y vive en el `solve.md` versionado, así que un `<root>` distinto necesita ese commit; un temporal borrado deja una ruta muerta, no un error: `ship` simplemente crea el worktree ahí.
