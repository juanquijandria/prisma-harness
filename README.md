<p align="center"><img src="assets/prisma.svg" width="180" alt="A pentagonal prism"></p>

<h1 align="center">Prisma Harness</h1>

<p align="center"><em>A prism splits one light into separate paths. PRISMA takes a claim and forces it through independent routes until it survives or falls.</em></p>

<p align="center">
  <img src="https://img.shields.io/badge/works%20with-Claude%20Code-111111?style=flat-square" alt="Works with Claude Code">
  <img src="https://img.shields.io/badge/model-single-111111?style=flat-square" alt="Single model, no second engine">
  <a href="https://github.com/juanquijandria/prisma-harness/actions/workflows/selftests.yml"><img src="https://github.com/juanquijandria/prisma-harness/actions/workflows/selftests.yml/badge.svg" alt="selftests on Ubuntu, macOS and Windows"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-111111?style=flat-square" alt="MIT"></a>
</p>

<p align="center"><sub>English · <a href="README.es.md">Español</a></sub></p>

<p align="center">
  <a href="#install"><b>Install</b></a> ·
  <a href="#the-steps-and-their-skills"><b>The steps</b></a> ·
  <a href="METHOD.md"><b>The method</b></a> ·
  <a href="docs/reference.md"><b>Reference</b></a>
</p>

<p align="center"><img src="assets/prisma-method-map.svg" width="100%" alt="The PRISMA map. A request is routed into one of five lanes, code with logic runs plan, build, end to end, mutation testing and verify, and five gates decide the merge. A demo ticket is sent back three times and approved on the fourth pass."></p>

PRISMA is a verification method for work an agent produces, and this repository packages it as a Claude Code plugin. It routes each request by the kind of work, runs five steps for code with logic, checks the work with five named gates, and blocks with hooks what the method says must not pass. It runs on a single model, with no second engine, no external service and no account.

## Why it exists

An agent writes the code and also the claim that the code works. It picks the tests, reads their output and decides they passed, and a test cannot refute the premise it shares with what it verifies. PRISMA adds the checks an agent cannot give itself, gates that block before a push, a step that makes someone look at the real surface, a refuter that tries to knock a finding down, and a blind replica that gets the claim and the sources but never the reasoning.

This is a gate speaking inside a session, after an agent tried to push a change of 1,202 lines.

```
SIZE GATE: 1202 lines changed, the push is blocked.
This repository blocks a push over 400 changed lines and warns
over 200.
```

## The steps and their skills

You only say "PRISMA". The `prisma` skill routes the request and calls each of the others when its step comes.

| Step | Skill | What it does |
|---|---|---|
| Route | `prisma` | routes the request into one of four lanes, query, mechanical change, code with logic or text, and into data to a third party as well when something leaves to someone else. Only code with logic runs the five steps |
| 1 Plan | `prisma-plan` | an interview in rounds that leaves a written record, says whether the work fits one session, splits it into tickets when it does not, and asks for every other session with its card |
| 2 Build | `prisma-build` | each test seen red before the code that turns it green, then a review by `prisma-fidelity-review` in a fresh subagent, then the commit |
| 2b Diagnose | `prisma-diagnose` | when something is broken, reproduce it before patching, and name the step the defect escaped from |
| 3 End to end | none | run on real data and look at the surface a person sees, not the artifact that produces it |
| 4 Mutation testing | none | reintroduce the exact defect, add a counterexample, check that the test fails for the expected reason, and run the format gate on the text |
| 5 Verify | none | check the exit condition on the real source, and measure a figure again by another route |

One rule holds over every lane, a claim is a hypothesis until it is measured by an independent route. And the method grows under one more, a rule enters only if it turns red on its historical case.

## The five gates

- **Fidelity reviewer**, `prisma-fidelity-review`, checks that what was built is what was agreed, no more and no less.
- **Format gate**, `hooks/format-gate.sh`, checks how a page is written and reads no code.
- **Refuter**, an adversarial agent, tries to knock a finding down against the code and the data.
- **Merge gate**, the CI or bot check on the pull request, says whether it can merge.
- **Blind replica** gets the claim and the sources and nothing of the calculation, in a brief that `hooks/blind-replica.sh` builds. On a single model it runs in a fresh subagent, which gives an independent derivation and not an independent engine.

## Install

First the two tools the gates need, in your terminal. Skip this if you already have them.

```
brew install jq python
```

```
sudo apt install jq python3
```

Then, inside Claude Code, two commands.

```
/plugin marketplace add juanquijandria/prisma-harness
/plugin install prisma-harness@prisma-harness
```

To update, run this in your terminal and open a new session, or turn on auto-update for `prisma-harness` once in `/plugin`.

```
claude plugin marketplace update
claude plugin update prisma-harness@prisma-harness
```

Requirements are `jq`, `python3` or `python`, `git`, `awk`, `cmp`, `bash`, `mktemp`, `find` and `sed`, and PRISMA names any that is missing at session start. On Windows, Claude Code needs Git for Windows so the hooks run under Git Bash, and the tools install with `winget install jqlang.jq Python.Python.3.12`. WSL 2 behaves like Linux.

## How you use it

1. **Install once, then open a new session.** There is no second plugin.
2. **Work as always.** The hooks run on their own, a gate speaks only when something is wrong, and the agent is told what to fix.
3. **Say "PRISMA"** when you want the whole method on a piece of work.
4. **Read [the reference](docs/reference.md)** when you want to know what a gate does, and `METHOD.md` for why the method asks for it.

## What is inside

| Piece | What it does | When it runs |
|---|---|---|
| `METHOD.md`, `docs/es/METHOD.md` | the method, in English and in its canonical Spanish block | you read it |
| `STYLE.md`, `docs/es/STYLE.md` | the writing rules, and which ones the format gate enforces | you read it |
| `skills/` | the five skills named in the table above | when you say "PRISMA" or their step comes |
| `hooks/gate-read-index.sh` | blocks a write under the docs folder before the index is read | `PreToolUse` on Write and Edit |
| `hooks/pre-push-comments.sh`, `pre-push-size.sh`, `pre-push-lint.sh` | the push gates, comment lines in the diff, a size that warns over 200 changed lines and blocks over 400, and the repository's own linter, `php-cs-fixer` or `eslint` | `PreToolUse` on Bash |
| `hooks/shell-traps.sh` | quotes two zsh traps, and blocks a missing `timeout` and a `pkill` that reaches another folder | `PreToolUse` on Bash |
| `hooks/secret-reads.sh` | keeps the lines of a secrets file out of the console and out of searches | `PreToolUse` on Bash |
| `hooks/format-gate.sh` | the format gate over the pages touched today | `Stop` |
| `hooks/claim-ready-gate.sh` | stops a message that calls a PR ready when `pr-ready.sh` says it is not | `Stop` |
| `hooks/paste-block-gate.sh` | stops a block meant to be pasted that still has a hole to fill | `Stop` |
| `hooks/handoff-card-gate.sh` | stops a request for another session that comes without its card | `Stop` |
| `hooks/check-canonical-sync.sh`, `session-voice.sh`, `session-deps.sh` | the sync check of the canonical block, the writing rules and the missing tools | `SessionStart` |
| `hooks/session-size.sh` | says once, past 80% of the context window, to compact | `UserPromptSubmit` |
| `hooks/notes-machinery.sh` | flags code machinery inside a tree meant for notes | `SessionStart` and `Stop` |
| `hooks/pr-ready.sh`, `blind-replica.sh` | whether a PR is ready to merge, and the brief of the blind replica | you call them |
| `hooks/receipt.sh` | one local line per block, rewrite, escape or gap | the gates write it, you read it |
| the other files under `hooks/` | the helpers the gates share, and the tests each gate runs | called by the gates |

Each piece in full, its escape and what it does not catch are in [the reference](docs/reference.md).

## How it is tested

Seventeen pieces have a `--selftest`. The three push gates are covered by 127 controls against a fixture repo in `tests/push-gates-controls.sh`. `tests/push-gates-never-fabricate.sh`, `tests/page-gates-never-fabricate.sh` and `tests/page-gates-receipts.sh` add 99 more on what a gate reports when it did not measure. `tests/skills-controls.sh` adds 45 over the text of the skills and the method, twenty-six of them on mutated copies that must go red. `tests/runner-controls.sh` adds 28 over the suite itself, run from outside it because a runner cannot run itself. The format gate suite, 47 cases, lives in `hooks/format-gate.sh`. All of it runs on Ubuntu, macOS and Windows on every push, and the badge at the top is that run.

## Configure

Every setting is optional. Three of them are here, and [the reference](docs/reference.md) lists the rest with every escape.

| Variable | Default | Meaning |
|---|---|---|
| `PRISMA_VOICE` | 1 | set to 0 to stop the writing rules PRISMA gives every session |
| `PRISMA_COMMENTS_BLOCK` | 0 | set to 1 and the comments gate blocks the push instead of warning |
| `PRISMA_LAUNCH_COMMANDS` | empty | an alias of yours for `claude`, so the handoff card gate reads it |

## Where it sits

Prisma Harness lives in the harness layer, the tools, permissions, state and evaluators around a model. It is not a loop and not a graph, it is not a reviewer of taste, and nothing here grades code quality. It gives the loop its evidence and the graph its gates, and it only speaks when a gate fails. Steps 1 and 2 ship their own skills, which descend from [the engineering skills of Matt Pocock](https://github.com/mattpocock/skills), whose flow ends at the commit. Steps 3, 4 and 5 are the part this harness exists for.

The method has a history of dated failures behind every rule. This repository ships the rules, and the history stays with its author. Contributions enter under the rule the method applies to itself. A new control enters only if it turns red on a real case. License MIT.
