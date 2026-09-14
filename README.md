# Prisma Harness

**English** below. **Español** más abajo, en [la segunda mitad](#prisma-harness-español).

PRISMA is a verification method for work that an agent produces, and this repository is the method packaged as a Claude Code plugin. Five lanes decide how much verification a request needs, five steps run for code with logic, and five gates with distinct names decide whether the work leaves the machine. The hooks block what the method says must not pass; the skill runs the steps; the written method says why.

It runs on a single model. There is no second engine, no external service, no account. The one place where the method was born with two engines, the blind replica, is declared as single-model and stays honest about what that costs.

## Install

Inside Claude Code, two commands. Updates arrive with `claude plugin update prisma-harness`, or automatically if you enable auto-update for this marketplace in `/plugin`.

```
/plugin marketplace add <github-owner>/prisma-harness
/plugin install prisma-harness@prisma-harness
```

Steps 1 and 2 of the method invoke skills from Matt Pocock's `mattpocock-skills` plugin. They are not copied here. Install that plugin next to this one, or run the same sequence by hand as `METHOD.md` describes.

Requirements, measured on macOS on 2026-09-14: `sh`, `jq`, `awk`, `git`, and `python3` for the command parser. Linux is not tested yet.

## What is inside

| Piece | What it does | When it runs |
|---|---|---|
| `METHOD.md` | the method in English, lanes, steps, gates, single-model mode | you read it |
| `docs/es/METHOD.md` | the canonical block in Spanish, the reference this plugin ships | `check-canonical-sync.sh` compares your copies against it at session start |
| `STYLE.md`, `docs/es/STYLE.md` | the writing rules and which ones the format gate enforces | you read it |
| `skills/prisma/SKILL.md` | the operating order of the method, invoked as `prisma` | when you say "PRISMA" |
| `hooks/gate-read-index.sh` | blocks a write under the docs dir if the session never read the index | `PreToolUse` on Write and Edit |
| `hooks/pre-push-comments.sh` | blocks a push or PR whose diff adds comment lines, figures in comments, or `file:line` references | `PreToolUse` on Bash |
| `hooks/pre-push-size.sh` | warns over 400 changed lines, blocks over 1000, and tells a stale branch apart from a big change | `PreToolUse` on Bash |
| `hooks/pre-push-lint.sh` | runs the repo's own linter, `php-cs-fixer` or `eslint`, on the diff before the push | `PreToolUse` on Bash |
| `hooks/format-gate.sh` | the format gate over pages touched today, rules in `.prisma-format.conf` | `Stop` |
| `hooks/check-canonical-sync.sh` | compares the canonical block across every registered copy, never edits | `SessionStart` |
| `hooks/blind-replica.sh` | builds the blind brief, claim and sources only, for the fifth gate | you call it |
| `hooks/measure-comments.sh`, `measure-diff-size.sh`, `compare-base.sh`, `command-invokes.sh`, `strip-quotes.sh` | the helpers the gates share | called by the gates |

Every hook that decides something has a `--selftest`, and `tests/run-selftests.sh` runs them all. A gate whose selftest never fails is decoration.

## Configure

Environment variables, all optional.

| Variable | Default | Meaning |
|---|---|---|
| `PRISMA_DOCS_ROOT` | the project directory | where your documentation lives |
| `PRISMA_DOCS_DIR` | `wiki` | the pages folder under the root that the index gate and the format gate watch |
| `PRISMA_INDEX_FILE` | `index.md` | the file a session must read before writing a page |
| `PRISMA_FORMAT_CONFIG` | `<docs root>/.prisma-format.conf` | rule switches, see `STYLE.md` and `.prisma-format.conf.example` |
| `PRISMA_CANONICAL`, `PRISMA_CANONICAL_COPIES` | the plugin's Spanish block, and any `CLAUDE.md` that carries the markers | what the sync check compares |
| `PRISMA_SIZE_WARN_OVER`, `PRISMA_SIZE_BLOCK_OVER` | 400, 1000 | the size gate thresholds |
| `PRISMA_COMMENTS_MAX_PCT`, `PRISMA_COMMENTS_MAX_BLOCK` | 0, 0 | the comments gate ceilings |
| `PRISMA_SKIP_REPOS` | empty | absolute paths where the push gates do not apply |
| `PRISMA_AUDITOR_CMD` | empty | a command that receives the blind brief on stdin and answers as a second engine |

Every gate has a declared escape, `PRISMA_COMMENTS_OK=1`, `PRISMA_SIZE_OK=1`, `PRISMA_LINT_OK=1`, placed in front of the command. The reason goes in the change description. An escape used by default is not a gate.

## What not to change without writing the reason

- **The canonical block in `docs/es/METHOD.md`.** Every registered copy is compared against it; editing it here makes every copy drift on purpose.
- **A gate's exit codes.** `0` passes, `2` blocks, and a gate that cannot measure says so and exits `0`. A gate that fails silently fabricates a verdict.
- **The selftests.** Change a gate, reintroduce the exact defect it exists for, watch it block, remove it, watch it pass. Silence proves nothing.

## Things that will bite you

- **A hook registered in this session does not run in this session.** Settings are read at startup. Test a new hook in a new session.
- **The comments gate skips files whose extension it does not know**, and it counts only lines your diff adds.
- **`--changed` in the format gate finds pages modified today** by file time, not by git.
- **The size gate measures HEAD**, not the ref you are pushing. If you push another branch from `main`, it says so and does not measure.

## Where the rest is

The method has a history of dated failures behind every rule. This repository ships the rules; the history stays with its author. Contributions are welcome under the same rule the method applies to itself. A new control enters only if it turns red on a real case.

License MIT.

---

# Prisma Harness (español)

PRISMA es un método de verificación para el trabajo que produce un agente, y este repositorio es el método empaquetado como plugin de Claude Code. Cinco carriles deciden cuánta verificación necesita un pedido, cinco pasos corren para el código con lógica, y cinco puertas con nombres distintos deciden si el trabajo sale de la máquina. Los hooks frenan lo que el método dice que no debe pasar; la skill corre los pasos; el método escrito dice por qué.

Corre con un solo modelo. No hay segundo motor, ni servicio externo, ni cuenta. El único lugar donde el método nació con dos motores, la réplica ciega, se declara de un solo modelo y dice con claridad lo que eso cuesta.

## Instalar

Dentro de Claude Code, dos comandos. Las actualizaciones llegan con `claude plugin update prisma-harness`, o solas si activas el auto-update de este marketplace en `/plugin`.

```
/plugin marketplace add <github-owner>/prisma-harness
/plugin install prisma-harness@prisma-harness
```

Los pasos 1 y 2 del método invocan skills del plugin `mattpocock-skills` de Matt Pocock. No están copiadas acá. Instala ese plugin junto a este, o corre la misma secuencia a mano como describe `METHOD.md`.

Requisitos, medidos en macOS el 14/09/2026: `sh`, `jq`, `awk`, `git`, y `python3` para el parser de comandos. Linux no está probado todavía.

## Qué hay adentro

| Pieza | Qué hace | Cuándo corre |
|---|---|---|
| `METHOD.md` | el método en inglés, carriles, pasos, puertas, modo de un solo modelo | lo lees |
| `docs/es/METHOD.md` | el bloque canónico en español, la referencia que trae este plugin | `check-canonical-sync.sh` compara tus copias contra él al arrancar la sesión |
| `STYLE.md`, `docs/es/STYLE.md` | las reglas de escritura y cuáles hace cumplir el gate de formato | lo lees |
| `skills/prisma/SKILL.md` | el orden operativo del método, se invoca como `prisma` | cuando dices "PRISMA" |
| `hooks/gate-read-index.sh` | frena una escritura bajo la carpeta de docs si la sesión nunca leyó el índice | `PreToolUse` en Write y Edit |
| `hooks/pre-push-comments.sh` | frena un push o PR cuyo diff agrega comentarios, cifras en comentarios o referencias `archivo:línea` | `PreToolUse` en Bash |
| `hooks/pre-push-size.sh` | avisa sobre 400 líneas cambiadas, frena sobre 1000, y distingue rama vieja de cambio grande | `PreToolUse` en Bash |
| `hooks/pre-push-lint.sh` | corre el linter del propio repo, `php-cs-fixer` o `eslint`, sobre el diff antes del push | `PreToolUse` en Bash |
| `hooks/format-gate.sh` | el gate de formato sobre las páginas tocadas hoy, reglas en `.prisma-format.conf` | `Stop` |
| `hooks/check-canonical-sync.sh` | compara el bloque canónico en toda copia registrada, nunca edita | `SessionStart` |
| `hooks/blind-replica.sh` | arma el brief ciego, solo afirmación y fuentes, para la quinta puerta | lo llamas tú |
| `hooks/measure-comments.sh`, `measure-diff-size.sh`, `compare-base.sh`, `command-invokes.sh`, `strip-quotes.sh` | los ayudantes que comparten las puertas | los llaman las puertas |

Todo hook que decide algo tiene `--selftest`, y `tests/run-selftests.sh` los corre todos. Una puerta cuyo selftest nunca falla es decoración.

## Configurar

Variables de entorno, todas opcionales. La tabla en inglés de arriba las lista con su default; las claves son las mismas. Toda puerta tiene un escape declarado, `PRISMA_COMMENTS_OK=1`, `PRISMA_SIZE_OK=1`, `PRISMA_LINT_OK=1`, puesto delante del comando, y el porqué va en la descripción del cambio. Un escape que se usa por defecto no es una puerta.

## Lo que no se toca sin escribir la razón

- **El bloque canónico en `docs/es/METHOD.md`.** Toda copia registrada se compara contra él; editarlo acá hace derivar todas las copias a propósito.
- **Los códigos de salida de una puerta.** `0` pasa, `2` frena, y una puerta que no puede medir lo dice y sale `0`. Una puerta que falla callada fabrica un veredicto.
- **Los selftests.** Cambias una puerta, reintroduces el defecto exacto por el que existe, la ves frenar, lo quitas, la ves pasar. El silencio no prueba nada.

## Cosas que te van a morder

- **Un hook registrado en esta sesión no corre en esta sesión.** La configuración se lee al arrancar. Prueba un hook nuevo en una sesión nueva.
- **La puerta de comentarios salta los archivos cuya extensión no conoce**, y cuenta solo las líneas que tu diff agrega.
- **`--changed` en el gate de formato encuentra páginas modificadas hoy** por fecha de archivo, no por git.
- **La puerta de tamaño mide HEAD**, no el ref que empujas. Si empujas otra rama desde `main`, lo dice y no mide.

## Dónde está el resto

Detrás de cada regla del método hay una falla fechada. Este repositorio trae las reglas; la historia se queda con su autor. Las contribuciones entran con la misma regla que el método se aplica a sí mismo. Un control nuevo entra solo si da rojo sobre un caso real.

Licencia MIT.
