---
name: prisma-build
description: Step 2 of PRISMA, the build. Tests first at the seams the plan record agreed, every control seen red before the code that turns it green exists, a fidelity review in a fresh subagent, then a commit. Use when PRISMA reaches step 2, or when the user asks to build, implement or fix something test-first.
---

# PRISMA build, step 2 of five

This is step 2 of the five steps in `METHOD.md`, and it runs only for work in the code with logic lane. It starts from the plan record that step 1 left and it ends with a commit that the fidelity reviewer has already read. If there is no record, go back to step 1; a build without a record has nothing to be faithful to.

Read the repository's glossary or context file when it has one, so test names and interface vocabulary match the project's own words, and respect any decision record in the area you touch.

## Where tests go

A seam is the public boundary where behavior is observed without reaching inside. Tests live at seams and never against internals. The seams come from the plan record; a test at a seam the record did not agree on is not written. If a slice needs a seam the record lacks, stop, add it to the record with the person, and continue. A piece of logic that no agreed seam can reach is declared in the record as untested, never skipped in silence.

Mock only at the system boundary, an external service, the clock, randomness, sometimes the filesystem. Never mock your own modules or internal collaborators. At the boundary, pass the dependency in instead of creating it inside, and prefer one small function per external operation over one generic fetcher, so each mock returns one shape and needs no conditional logic.

## What a good test is

A good test verifies behavior through the public interface and reads like one line of the plan record. It survives a refactor because it does not care about structure. It makes one logical assertion. Its expected value comes from an independent source of truth, a known-good literal, a worked example, a line of the record, never from recomputing the answer the way the code does. Verifying through a side channel, such as querying the database instead of calling the interface, is a test of the storage and not of the behavior.

Three shapes of test are refused.

- **Implementation-coupled.** It mocks an internal collaborator, tests a private method, or asserts on call counts. The tell is that it breaks on a refactor that changed no behavior.
- **Tautological.** The assertion recomputes the expected value the way the code does, or asserts a constant against itself, so it passes by construction and can never disagree with the code.
- **Horizontal.** All the tests are written first and all the code afterwards. Bulk tests verify imagined behavior and lock in structure before it is understood. Work in vertical slices instead, one test, one implementation, repeat, each slice a tracer that responds to what the last one taught.

## The loop, one slice at a time

One seam, one test, one minimal implementation per cycle. Refactoring is not part of the cycle; it waits until the slice is green and is reviewed with the rest.

**Red is seen, not assumed.** Run the new test before any production code exists and read the failure. The failure must be the assertion the slice exists for, not a missing import, a typo or a fixture that failed to load. Quote that failure line in your notes. Only then write enough code to turn it green, and no more. A control that has never been seen red proves nothing, which is the rule this repository applies to its own gates.

Run the type checker after each slice, the touched test file after each slice, and the full suite once before the review. When something breaks in a way the slice does not explain, stop and invoke `prisma-diagnose` before touching code; a patch without a diagnosis is a guess with a commit message. Two failures of the same functional hypothesis send the work back to step 1.

When a later gate reports a defect the tests did not catch, fix the test first, without touching the code, and watch it go red on that defect. Then fix the code and watch it go green.

## The review is the fidelity reviewer

The fidelity reviewer is one of the five gates named in `METHOD.md`, and this is where it runs. Fidelity means the code does what the plan record says, no more and no less, and nothing the record put out of scope.

Spawn a fresh subagent whose whole prompt is the invocation of `prisma-fidelity-review` with three things, the fixed point the diff is measured from, the path of the plan record, and the files that document this repository's standards. It does not receive your account of what you built, your test output, or this conversation, because a reviewer that receives the builder's framing inherits the builder's premise.

Every finding it returns is a hypothesis until you reproduce it, by reading the hunk it quotes and running the test it names. A confirmed absence is built, red first. A confirmed extra is removed, not justified. A finding that dies gets its cause of death written down next to it.

## The commit

Commit to the current branch once the review has been answered. The message says what the record agreed, names the record, and lists what was left out on purpose. Then hand the work to step 3 with the surface the record named, because step 3 looks at that surface and not at the artifact that produces it.
