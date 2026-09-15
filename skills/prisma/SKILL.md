---
name: prisma
description: Run PRISMA on a piece of work. Routes the request to one of five lanes (query, mechanical change, code with logic, data to a third party, text) and runs what that lane requires, up to the five steps and five gates. Use when the user says "PRISMA", "pass this through PRISMA", or asks to verify work before it leaves the machine.
---

# PRISMA

Read `METHOD.md` at the plugin root once per session before applying this skill. It is the source; this file is the operating order.

## 1. Route first

Ask two questions. First, what kind of work is it, and four lanes answer it, query, mechanical change, code with logic and text, the more expensive one winning when two fit. Second, does anything leave to a third party, and the fifth lane stacks on the first answer, adding controls and never replacing them.

| Lane | The question | What runs |
|---|---|---|
| Query | Does this only answer with data and change nothing? | the claims rule. A figure that leaves the machine gets two routes and a `[value \| route \| date-time]` label |
| Mechanical change | Can you PROVE it changes no executable behavior, stored data, permissions, integration or deployment? | step 3 only, run it and look |
| Code with logic | Is it a feature, a bug fix, a migration, or a script someone else will run? | the five steps |
| Data to a third party | Does a file, list or figure leave to someone else? | the producing query is code and runs its lane, plus step 3 on the real rows, the verification protocol, and a refuter |
| Text | Is it a page, a PR body, a message, a report, a script to read aloud? | the format gate, a refuter, the claims rule |

Two guards. When in doubt, take the MORE expensive lane, because the agent has an interest in choosing the cheap one. A lane goes up, never silently down; going down is declared.

## 2. The five steps, for code with logic

1. **Plan.** Invoke `prisma-plan`. It interviews in rounds with a recommended answer per question, leaves a record with the agreed behavior, the exclusions, the seams, the surface and the exit condition, and closes by declaring the lane and whether the work fits in one session, about 140k tokens of useful context. If it does not fit, it splits the work into session-sized tickets before anything is built.
2. **Build.** Invoke `prisma-build`. Tests first at the agreed seams, every control seen red before the code that turns it green exists, then `prisma-fidelity-review` in a fresh subagent that receives the record and the fixed point and nothing of the builder's account, then commit. If something is broken along the way, invoke `prisma-diagnose` before patching; it ends by naming the step the defect escaped from.
3. **End to end.** Run it on real data and LOOK at the result. Name the surface where a person will see it BEFORE looking, then look at THAT surface, not the artifact that produces it. Two failures of the same functional hypothesis send you back to step 1.
4. **QA of the QA and format gate.** Reintroduce the EXACT defect and confirm the test fails for the expected reason. Add a semantic counterexample chosen separately. Run `hooks/format-gate.sh --strict` on every text you deliver.
5. **Verify.** Check the exit condition on the real source or surface. A figure gets measured again by a second route, in the normal state and in the edge state. A behavior change gets observed at the destination. Never cite an earlier run as a substitute.

## 3. The five gates, by name

- **Fidelity reviewer**, `prisma-fidelity-review` in a fresh subagent. Did we build what the record agreed, no more and no less?
- **Format gate**, `hooks/format-gate.sh`. Is the deliverable written to the rules? It reads no code and finds no bugs.
- **Refuter**, an adversarial agent whose job is to knock the finding down against code and data.
- **Merge gate**, the CI or bot check on the PR. It says whether the PR can merge. Its findings are reproduced before being repeated as facts.
- **Blind replica**, `hooks/blind-replica.sh`. Receives the claim and the sources and NOTHING of the calculation. Mandatory for derived figures, platform semantics, ambiguous sources, data to third parties, and hard-to-revert consequences. In single-model mode it runs in a fresh-context subagent and declares that it gives independence of derivation, not of engine. Write the claim and its sources to a file and run `sh hooks/blind-replica.sh <file>`. Without `PRISMA_AUDITOR_CMD` it prints the brief for a fresh subagent and exits 6; with it, the exit code is the verdict, 0 confirmed, 5 refuted, 4 none.

## 4. Every claim is a hypothesis until measured

A finding from an agent, a bot comment, a code comment and a line of prose enter through the same door. Reproduce against the source, let a refuter try to kill it, then an adjudicator decides value and not truth. Every figure that leaves gets two routes; every causal claim gets a negative control. If a finding dies, record why.

## 5. Before saying something outward

Does it need saying, or can it be done and explained after? Does it really move something outside, or is it being treated as risky without checking? Verify first, then decide whether it is a decision for the human or a formality. What always gets confirmed is the irreversible, what reaches an audience, and what costs money.
