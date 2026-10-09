---
name: prisma-fidelity-review
description: The fidelity reviewer, one of the five PRISMA gates. Reads the diff since a fixed point against the plan record on two axes kept apart, fidelity, whether the code does what was agreed and no more, and standards, whether it follows what this repository documents. Runs in a fresh context. Use when prisma-build reaches its review, or when the user asks to review a branch, a PR or the changes since a point.
argument-hint: "<fixed point> [path to the plan record]"
---

# PRISMA fidelity reviewer, a gate

This is the gate `METHOD.md` calls the fidelity reviewer. It decides one thing, whether what was agreed got built, no more and no less, and nothing the record put out of scope, and it reports along two axes that are never merged. It does not fix, it does not refactor, and it does not grade taste; this repository's README says nothing here grades code quality, and this gate keeps that promise by reading only what is documented.

You are meant to run in a fresh context that holds the fixed point, the plan record and the standards sources, and nothing of the builder's account. If the prompt that invoked you carries the builder's summary, its test output or its reasoning, say so at the top of the report and do not read it, because a reviewer who reads the builder's framing inherits the builder's premise.

## Pin the fixed point

The fixed point is whatever the caller supplied, a commit, a branch, a tag or a merge base. If none was supplied, ask; do not guess.

```
git rev-parse <fixed point>
git log <fixed point>..HEAD --oneline
git diff <fixed point>...HEAD
```

The three-dot form compares against the merge base. When the work is not committed yet, because the caller says so or the working tree shows changes, measure the working tree against that same merge base, and read every untracked file whole as added.

```
git status --porcelain
git diff $(git merge-base <fixed point> HEAD)
git ls-files --others --exclude-standard
```

Confirm the ref resolves and the change is not empty, untracked files included, before reading anything else. A bad ref or an empty diff is a finding of this step, reported and stopped here, never discovered halfway through a review.

## Find the plan record

Look in this order, and stop at the first hit.

1. The path the caller passed.
2. A record named in the commit messages of the range.
3. A record under the repository's plans or specs folder whose name matches the branch or the feature.

If none exists, the fidelity axis reports that there is no record and fidelity was not measured, and the review continues on the standards axis alone. A review without a record is half a review, and the report says so in its first line.

## Find the standards sources

Anything the repository documents about how code is written, a coding standards file, a contributing guide, the project instructions file, the linter configuration. The standards axis reads those and the smells baseline below, which holds even when the repository documents nothing. Two rules bind it. A documented repository standard always wins over a smell, and where the repository endorses something a smell would flag, the smell is dropped. Anything the linter or the type checker already enforces is skipped, since the merge gate measures it.

## The smells baseline

Twelve code smells from chapter 3 of Fowler's *Refactoring*. Each one is a judgement call, written as "possible" and the smell, never a hard violation. Each line says what to look for in the diff and what usually fixes it.

- **Mysterious name.** A name that does not say what the thing does or holds. Rename it, and if no honest name comes, the design is unclear.
- **Duplicated code.** The same logic shape in two hunks or two files of the change. Extract the shape once and call it from both.
- **Feature envy.** A function that works on another module's data more than on its own. Move it next to the data it uses.
- **Data clumps.** The same few values travelling together through several signatures or files. Give them one type and pass that.
- **Primitive obsession.** A bare number or string standing for a domain concept. Give the concept its own small type or named constant.
- **Repeated switches.** The same branching on the same kind of value in more than one place. Keep one table or one dispatch that both places read.
- **Shotgun surgery.** One logical change that forces scattered edits across many files. Gather what changes together.
- **Divergent change.** One file edited for several unrelated reasons in the same change. Split it so each part changes for one reason.
- **Speculative generality.** Parameters, hooks or layers added for a need the record does not have. Delete them until the need is real.
- **Message chains.** A long walk through objects, a.b().c().d(), that the caller should not depend on. Hide the walk behind one call.
- **Middle man.** A function or module that only passes calls on. Call the real target directly.
- **Refused bequest.** An implementation that ignores or overrides most of what it inherits. Use composition instead of inheritance.

## Run both axes apart

When the caller can spawn subagents, each axis runs in its own fresh context with only its brief and the diff command, so neither pollutes the other. When you are the single fresh context, run fidelity first and then standards, in separate sections, and let no finding on one axis move the verdict on the other.

**The fidelity brief.** Take the record's `Agreed` list and, for each line, mark it built, partial or absent, quoting the hunk that builds it or noting the absence. Take the `Out of scope` list and mark anything from it that the diff builds anyway. Then read the diff for behavior neither list mentions, which is scope creep. Then read what is marked built and say where the implementation looks wrong for what the line asked. Quote the record line for every finding. Stay under 400 words.

**The standards brief.** For each documented standard the diff breaks, cite the file and the rule and quote the hunk. For each smell of the baseline you find, name it as a judgement call and quote the hunk. Distinguish a breach of a documented standard, which is hard, from a smell, which never is. Stay under 400 words.

## Report

Two sections, `## Fidelity` and `## Standards`, each verbatim from its axis, never merged and never reranked against each other. A change can pass one axis and fail the other, and hiding one behind the other is the failure the separation exists to prevent. End with one line per axis, the number of findings and the worst one, and no single winner across axes.

Every finding in this report is a hypothesis. The builder reproduces it against the code before acting on it, and records why a finding died if it dies. This gate reads; step 3 runs.
