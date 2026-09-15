<h1 align="center">Prisma Harness</h1>

<p align="center"><em>A prism splits one light into separate paths. PRISMA takes a claim and forces it through independent routes until it survives or falls.</em></p>

<p align="center">
  <img src="https://img.shields.io/badge/works%20with-Claude%20Code-111111?style=flat-square" alt="Works with Claude Code">
  <img src="https://img.shields.io/badge/model-single-111111?style=flat-square" alt="Single model, no second engine">
  <img src="https://img.shields.io/badge/selftests-passing-111111?style=flat-square" alt="Every deciding hook has a selftest">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-111111?style=flat-square" alt="MIT"></a>
</p>

<p align="center"><sub>English · <a href="README.es.md">Español</a></sub></p>

<p align="center">
  <a href="#install"><b>Install</b></a> ·
  <a href="METHOD.md"><b>The method</b></a> ·
  <a href="STYLE.md"><b>The writing rules</b></a> ·
  <a href="#how-a-person-uses-it"><b>How it is used</b></a> ·
  <a href="#configure"><b>Configure</b></a>
</p>

## Why it exists

An agent writes the code and also writes the claim that the code works. It picks the tests, reads their output and decides they passed. That loop has no way out from the inside, because a test cannot refute the premise it shares with what it verifies. The failures that reach production are the ones every check agreed about, and green usually means the checks never covered the thing that broke.

PRISMA adds the checks an agent cannot give itself. Gates that block mechanically before a push, a step that forces someone to look at the real surface, a refuter whose job is to knock the finding down, and a blind replica that gets the claim and the sources but never the reasoning. Every rule in it was paid for by a real failure, and a new one only enters if it turns red on the case that pays for it.

This is what it looks like inside a session. The agent tried to write a documentation page without opening the index, and then tried to push a change of 1,202 lines.

```
INDEX GATE: you are about to write a page under wiki/ without having opened
index.md in this session. Read <docs root>/index.md first so you do not create
a duplicate page or leave the index stale, then retry.

SIZE GATE: 1202 lines changed, the push is blocked.
Over 1000 lines, defect detection in review drops below half.
```

PRISMA is a verification method for work that an agent produces, and this repository is the method packaged as a Claude Code plugin. Five lanes decide how much verification a request needs, five steps run for code with logic, and five gates with distinct names decide whether the work leaves the machine. The hooks block what the method says must not pass; the skill runs the steps; the written method says why.

It runs on a single model. There is no second engine, no external service, no account. The one place where the method was born with two engines, the blind replica, is declared as single-model and stays honest about what that costs.

## The method in one drawing

![PRISMA: route first into one of five lanes; code with logic runs five steps across four swimlanes, the person, the agent, the gates and the blind replica; five gates cross lanes and block](assets/method-map.png)

Three rules hold over every lane and are not another step.

1. Every claim is a hypothesis until measured by an independent route.
2. The instrument is calibrated on the real corpus, and whoever calibrates says what was not tested.
3. A line enters the method only if it turns red on its historical case.

The order the agent follows is written, not drawn. It lives in `METHOD.md` and in `skills/prisma/SKILL.md`, which is what runs when you say PRISMA.

## How a person uses it

1. **Install once**, the two commands below.
2. **Open a new session and work as always.** You do not call anything. The gates run on their own and speak only when something is wrong. A write to your docs without opening the index is blocked and the agent is told what to read. A push with stray comments, over a thousand changed lines or a red linter is blocked and the agent is told what to do. A page with an em-dash or voseo keeps the agent from closing its turn until it is fixed. The writing rules arrive at session start, so the agent writes that way without being asked.
3. **Say "PRISMA"** when you want the whole method on a piece of work. That is the only thing you ever call. The skill routes the request into one of the five lanes and runs what the lane requires, up to the five steps and five gates.
4. **Read `METHOD.md`** when you want to know why a gate did what it did.
5. **Update** with `claude plugin update prisma-harness`, or turn on auto-update for this marketplace once in `/plugin` and forget about it.

## Install

Inside Claude Code, two commands.

```
/plugin marketplace add juanquijandria/prisma-harness
/plugin install prisma-harness@prisma-harness
```

Steps 1 and 2 use the skills of Matt Pocock's plugin. Install it next to this one; if it is missing, PRISMA tells you at session start.

```
/plugin install mattpocock-skills@claude-plugins-official
```

To update both, run this in your terminal and open a new session.

```
claude plugin marketplace update
claude plugin update prisma-harness@prisma-harness
claude plugin update mattpocock-skills@claude-plugins-official
```

To never think about it again, open `/plugin` inside Claude Code, go to Marketplaces, pick `prisma-harness` and turn on auto-update.

Requirements: `jq`, `python3` or `python`, `git`, `awk`, `cmp`, `bash`. If any is missing, PRISMA tells you at session start with the install command and asks before installing anything.

Tested on macOS. The scripts are POSIX shell and every selftest passes under `dash`, the shell of Debian, Ubuntu and WSL, but no Linux machine has run them yet. On Windows, Claude Code needs Git for Windows so that the hooks run under Git Bash; install `jq` and Python with `winget install jqlang.jq Python.Python.3.12`, then run `sh tests/run-selftests.sh` from Git Bash and send the output if anything fails. WSL 2 behaves like Linux.

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
| `hooks/session-voice.sh` | injects the eight writing rules of `STYLE.md` into every session, so the agent writes that way without being asked. `PRISMA_VOICE=0` switches it off | `SessionStart` |
| `hooks/session-deps.sh` | at session start, tells the agent which required tools or which plugin are missing, with the install command, and to ask before installing. Silent when nothing is missing. `PRISMA_DEPS_CHECK=0` switches it off | `SessionStart` |
| `hooks/blind-replica.sh` | builds the blind brief, claim and sources only, for the fifth gate | you call it |
| `hooks/measure-comments.sh`, `measure-diff-size.sh`, `compare-base.sh`, `command-invokes.sh`, `strip-quotes.sh` | the helpers the gates share | called by the gates |

The six hooks that act on their own, the index gate, the format gate, the sync check, the blind replica, the session voice and the dependency check, have a `--selftest`, and so does the command parser, with 16 cases. The three push gates are tested by positive and negative control against a fixture repo in `tests/push-gates-controls.sh`. `tests/run-selftests.sh` runs all of it. A gate whose tests never fail is decoration.

## Configure

Environment variables, all optional.

| Variable | Default | Meaning |
|---|---|---|
| `PRISMA_DOCS_ROOT` | the project directory | where your documentation lives |
| `PRISMA_DOCS_DIR` | `wiki` | the pages folder under the root that the index gate and the format gate watch |
| `PRISMA_INDEX_FILE` | `index.md` | the file a session must read before writing a page |
| `PRISMA_FORMAT_CONFIG` | `<docs root>/.prisma-format.conf` | rule switches, see `STYLE.md` and `.prisma-format.conf.example` |
| `PRISMA_CANONICAL`, `PRISMA_CANONICAL_COPIES` | the plugin's Spanish block, and `~/.claude/CLAUDE.md` plus the project `CLAUDE.md` when they carry the markers | what the sync check compares |
| `PRISMA_SIZE_WARN_OVER`, `PRISMA_SIZE_BLOCK_OVER` | 400, 1000 | the size gate thresholds |
| `PRISMA_COMMENTS_MAX_PCT`, `PRISMA_COMMENTS_MAX_BLOCK` | 0, 0 | the comments gate ceilings |
| `PRISMA_SKIP_REPOS` | empty | absolute paths where the push gates do not apply |
| `PRISMA_AUDITOR_CMD` | empty | a command that receives the blind brief on stdin and answers as a second engine |
| `PRISMA_VOICE` | 1 | set to 0 to stop injecting the writing rules at session start |
| `PRISMA_DEPS_CHECK` | 1 | set to 0 to stop the dependency notice at session start |

The three push gates have a declared escape, `PRISMA_COMMENTS_OK=1`, `PRISMA_SIZE_OK=1`, `PRISMA_LINT_OK=1`, placed in front of the command. The reason goes in the change description. An escape used by default is not a gate. The index gate has no escape, reading the index is the fix. The format gate has no escape either; a rule you do not want is switched off in its config.

## What not to change without writing the reason

- **The canonical block in `docs/es/METHOD.md`.** Every registered copy is compared against it; editing it here makes every copy drift on purpose.
- **A gate's exit codes.** As a hook, `0` passes and `2` blocks; a gate that cannot measure prints a `WARN` and exits `0`. On the command line the format gate exits `1` on failures. A gate that fails silently fabricates a verdict.
- **The selftests.** Change a gate, reintroduce the exact defect it exists for, watch it block, remove it, watch it pass. Silence proves nothing.

## Gotchas

- **A hook registered in this session does not run in this session.** Settings are read at startup. Test a new hook in a new session.
- **`hooks/hooks.json` and `skills/` load by convention.** Naming them again in `plugin.json` makes Claude Code refuse the plugin as a duplicate. Measured on 2026-09-14 installing from GitHub, where the local `--plugin-dir` load had not complained.
- **The comments gate skips files whose extension it does not know**, and it counts only lines your diff adds.
- **`--changed` in the format gate finds pages modified today** by file time, not by git.
- **The command parser, `command-invokes.sh`, is not a shell parser.** It respects quotes, escapes, comments and redirections, and it never drops content. It does not resolve expansions, aliases, `eval` or globbing. When a command leaves a quote unbalanced the reading is ambiguous, and it returns the UNION of the plausible readings instead of one, so a gate may block a command it did not need to block; the fix is to split the command in two. It is rare, and deterministic when it happens.
- **The size gate measures HEAD**, not the ref you are pushing. If you push another branch from `main`, it prints a `WARN` and does not measure.

## Where it sits

Remove the model from the diagram of an agent system and what remains is the harness, the tools, permissions, state and evaluators around it. Prisma Harness lives in that layer. It is not a loop, it does not retry work until something passes, and it is not a graph, it does not decide which step runs next. It gives the loop its evidence and the graph its gates, and it only speaks when a gate fails. Steps 1 and 2 of the method use the skills of Matt Pocock, the interview, test-first build and code review; steps 3, 4 and 5 are the part his flow ends before, and the part that this harness exists for.

## What Prisma Harness refuses to be

- **Not an eval framework.** No datasets, no scores, no dashboards. Five gates with names, each with the case that pays for it.
- **Not a second model watching the first.** It runs on one model and says out loud what that costs.
- **Not a reviewer of taste.** The format gate reads how a page is written; nothing here grades code quality.
- **Not silent.** A gate that cannot measure prints a warning. Silence never means clean.

## Where the rest is

The method has a history of dated failures behind every rule. This repository ships the rules; the history stays with its author. Contributions are welcome under the same rule the method applies to itself. A new control enters only if it turns red on a real case.

License MIT.
