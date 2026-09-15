# PRISMA, the method

PRISMA is a verification method for work that an agent or a person produces. A prism splits one light into separate paths, and that is what the method does. It takes a claim and forces it through independent routes until it survives or falls. You say "this passed PRISMA" or "that does not pass PRISMA".

This page is an English translation, declared as such, of the canonical Spanish block that lives in `docs/es/METHOD.md`, extracted from its source on 2026-09-14. That block is the author's method made generic on purpose, with examples that hold for anyone doing any kind of work, and `hooks/check-canonical-sync.sh` compares your own copies against it at every session start. If the two languages ever disagree, the Spanish block wins and this page is out of date.

## What PRISMA is, in one paragraph

Five lanes, five steps, five gates. Every request is routed first, into one of four lanes by the kind of work, and into the fifth as well when something leaves to a third party; the lanes decide how much verification runs. Only code with logic runs the five steps. Five gates with distinct names decide whether the work leaves the machine. Above all of it sits one rule, that every claim is a hypothesis until it is measured, no matter who wrote it or where it appears.

## Route first

Ask two questions. First, what kind of work is it, and four lanes answer that, query, mechanical change, code with logic and text; the one-line question of each settles it, and when two fit the more expensive one wins. Second, does anything leave to a third party. The fifth lane answers that, and it stacks on whichever lane the first answer chose, adding controls and never replacing them.

| Lane | The one-line question | Example | What runs |
|---|---|---|---|
| **Query** | Does this only answer with data and change nothing? | "How many users signed up in August?" | the claims rule. If the figure goes to a third party, two routes and a `[value \| route \| date-time]` label. No skill |
| **Mechanical change** | Can you PROVE it changes no executable behavior, stored data, permissions, integration or deployment? If you cannot prove it, it is code. A constant is not automatically mechanical and a threshold is a decision | renaming a variable, moving a file, fixing a typo in a string nobody parses | **step 3 only**, run it and look. No skill |
| **Code with logic** | Is it a feature, a bug fix, a migration, or a script someone else will run? | a new endpoint, a query that feeds a chart, a cron | **the five steps**, and the skills are INVOKED, not cited |
| **Data to a third party** | Does a file, a list or a figure leave to someone else? | a spreadsheet, a list or a figure someone else will act on | **adds controls, never replaces them.** The query that produces the file is code and runs its lane; the delivery adds mandatory step 3, opening the file and looking at real rows, the verification protocol, a refuter, and the blind replica on every derived figure |
| **Text** | Is it a page, a PR body, a message, a report, a script to read aloud? | a wiki page, a Slack message, a meeting summary | format gate, refuter, and the claims rule |

**Risk is measured, never size, and the burden of proof is on "mechanical".** A one-line formula can be the most dangerous change of the day. A failure of permissions, integration or deployment touches no decision, formula, metric or interpretation, and still breaks production; a lane cannot depend on a generous reading.

**Two guards.** When in doubt, take the MORE expensive lane, because the agent has an interest in choosing the cheap one. A lane goes up, never silently down; going down is always declared.

## The five steps

| # | Step | What happens | Skill or check | Who triggers it |
|---|---|---|---|---|
| **1** | **Plan** | an interview that sharpens the idea into shared understanding and leaves a record | **invoke NOW** `mattpocock-skills:grilling` (the person, directly, can type `/mattpocock-skills:grill-with-docs`) | the agent starts it; the person answers decisions |
| 1b | the fork | decide whether it fits in ONE session (about 140k tokens of useful context) | no command, it is judgment | the agent estimates it when closing the interview and SAYS SO |
| 1c | only if it does NOT fit | write the destination and the path as session-sized tickets | spec and tickets (the person, directly, `/to-spec` then `/to-tickets`) | the agent |
| **2** | **Build** | run the orchestrator chain | **invoke NOW**, in order: build, then `mattpocock-skills:tdd`, then `mattpocock-skills:code-review` in clean subagents, then commit (the person, directly, `/implement`) | the agent |
| 2b | only if it is broken | diagnose before patching | `mattpocock-skills:diagnosing-bugs` | the agent |
| **3** | **End to end** | run on real data and **LOOK** at the result. Before activating something a person will see, **name the surface where they will see it and look at THAT surface**, not the artifact that produces it. If you cannot name it, do not activate it. Name it BEFORE, because afterwards you name what you already looked at. If what already runs in production shares a configuration and the new thing does not, that difference **is explained before activating**, not noted as optional. If the figure governs a decision, validate the figure AND the decision **on both sides of the threshold**, because a wrong figure can land on the right side by accident | no skill, it is running the real thing | the agent. Two failures of the same functional hypothesis force a return to step 1. An environmental failure is diagnosed and does not count toward that limit |
| **4** | **QA of the QA and format gate** | **falsify the oracle**, do not pick a convenient mutation. Three requirements: reintroduce the EXACT defect, add a semantic counterexample chosen separately, and confirm the test **fails for the expected reason** and not just that something turns red | controlled injection plus `hooks/format-gate.sh --strict` on the text, which stands in for the author's private gate | the agent. The format gate reads no code and does not replace the test |
| **5** | **Verify** | check the exit condition on the real source or surface | if it produces a figure, measure it again by another route, and if it depends on environment state measure it in the normal state **and in the edge state**; if it changes behavior, observe it at the destination | the agent. Neither an earlier run nor a document is cited as a substitute for reality |

The skills named above belong to the `mattpocock-skills` plugin by Matt Pocock. This repository does not copy them; install that plugin next to this one. Without it, run the same sequence by hand, interview in rounds, tests first, a review in a fresh context, commit.

## The five gates have different names

Calling all of them "the judge" was the root of treating an opinion from a bot as a proven fact. Each name says what the gate is responsible for.

- **Fidelity reviewer**, the code review. Decides whether what was agreed got built.
- **Format gate**, `hooks/format-gate.sh`. Reviews how the deliverable is written. It reads no code, finds no bugs and refutes no findings.
- **Refuter**, the adversarial agent. Tries to knock a finding down against code and data.
- **Merge gate**, the CI or bot check on the pull request. Decides whether the PR can merge. Its findings are reproduced before being treated as facts; only what it marks as mandatory forces a fix.
- **Blind replica**, `hooks/blind-replica.sh`. Receives the claim and the sources and NOTHING of the calculation. It is the only gate that can break a premise the other four inherit. Mandatory with derived figures, with operating-system or platform semantics, with ambiguous interpretation of a source, with data that leaves to a third party, and with consequences that are hard to revert. It starts when the claim and the sources are frozen and delivers its result **before** seeing yours.

## Single-model mode

The method was born with two engines. The blind replica ran on a second model because two routes from the same brain share a premise, and a test cannot refute the premise it shares with what it verifies. This repository ships without a second engine, on purpose, so that anyone can run it on a single model.

In single-model mode the blind replica runs in a **subagent with a fresh context** that receives only the claim and the sources. That gives **independence of derivation**, the other route can catch a wrong calculation, but **not independence of engine**, a wrong premise shared by the model survives. The method says so out loud instead of hiding it. `hooks/blind-replica.sh` prints the brief with a label that names this limit, and anyone who does have a second engine plugs it in with `PRISMA_AUDITOR_CMD` and the label goes away.

## Every claim is a hypothesis until it is measured

The five steps are for code; this rule is transversal. A claim stays a hypothesis while whoever reads it cannot re-verify it cheaply **and by an independent route**, or if it will trigger something expensive or irreversible. Repeating the same instrument is not verifying.

It does not matter who wrote it or where it appears. A finding from an agent, a mandatory fix from a bot, a code comment and a line of prose enter through the same door. It gets reproduced against the source or the real surface, and a **refuter** tries to knock it down by looking explicitly for how it could be false. Then an **adjudicator** decides whether the change is worth it, and it decides **value, not truth**; truth was already decided by the refuter and the reproduction. Every figure that leaves gets measured by two routes and every causal claim carries a negative control. If the finding survives, it gets fixed; if it dies, **why it died gets recorded**.

**The instrument comes before the hypothesis.** When the unknown is the environment and not the code, build the meter first and let it speak, instead of listing suspicions from reading. When a gate reports a defect your test did not catch, **fix the test first, without touching the code**, and let the fixed test decide.

## Before saying something outward

Two questions before framing something as a decision to negotiate. Does it need saying, or can it be done and explained afterwards? Does it really move something outside, or is it being treated as risky without having checked? Verify first, then decide whether it is the human's decision or a formality. What always gets confirmed is the irreversible, what reaches an audience, and what costs money.

## How the method grows

A line enters this method only if it is run over its historical case and turns RED with the failed oracle. Citing a dated failure is not enough, because a story can connect any proposal to a real failure without the proposal having caught anything. And entering is not staying, because every control carries what it costs to run, what it catches that no other control catches, and when it gets reviewed. A control that cannot name an exclusive catch at its review leaves.

Sources: translation of the canonical PRISMA block in `docs/es/METHOD.md` and of the method page it comes from, done 2026-09-14. Related: `STYLE.md`, `README.md`.
