---
name: prisma-diagnose
description: Step 2b of PRISMA, diagnose before patching. Builds a feedback loop that goes red on the exact defect, reproduces and minimises it, tests ranked falsifiable hypotheses one variable at a time, fixes with a regression test seen red first, and ends by naming which of the five steps the defect escaped from. Use when something is broken, throwing, failing or slow, or when the user says diagnose or debug.
---

# PRISMA diagnose, step 2b of five

This is step 2b in `METHOD.md`, the branch step 2 takes when something is broken, and the branch step 3 takes when a run fails. The method has a rule for it, the instrument comes before the hypothesis. When the unknown is the environment and not the code, build the meter first and let it speak, instead of listing suspicions from reading. This skill is that rule made executable.

Redact every secret before showing a command, an output or a captured artifact, and build loops against environment variables so the credential never appears in what you show. If the redacted output is not enough to diagnose, say so and ask.

## First, the loop

This is the whole skill; the rest is mechanical. A tight pass or fail signal that goes red on this defect finds the cause, because bisection, hypothesis testing and instrumentation only consume it. Without one, no amount of reading code will save you. Spend the effort here, be creative, refuse to give up.

Ways to build one, in roughly this order.

1. A failing test at whatever seam reaches the defect.
2. An HTTP call against a running development server.
3. A command line invocation with a fixture, diffed against a known-good output.
4. A headless browser script that drives the surface and asserts on the page, the console or the network.
5. A captured real request, payload or event log, replayed through the code path in isolation.
6. A throwaway harness, the smallest subset of the system that reaches the defect with one call.
7. A property or fuzz loop, a thousand random inputs, when the symptom is "sometimes wrong".
8. A bisection harness, when the defect appeared between two known states, so the search can be automated.
9. A differential loop, the same input through the old and the new version, and a diff of the outputs.
10. A script that drives a person through the clicks only they can make and prints what they saw, the last resort.

Then tighten it. Make it faster by caching setup and narrowing scope. Make the signal sharper by asserting on the exact symptom and never on "did not crash". Make it deterministic by pinning time, seeding randomness, isolating the filesystem and freezing the network. A thirty-second flaky loop is barely better than none; a two-second deterministic one is the instrument.

For a defect that does not always reproduce, the goal is a higher rate and not a clean repro. Loop the trigger a hundred times, run it in parallel, add stress, narrow the timing window, until the rate is high enough to work against.

When you cannot build a loop, stop and say so, list what you tried, and ask for one of three things, access to the environment that reproduces it, a redacted captured artifact, or permission to add temporary instrumentation. Do not hypothesise without a loop.

**The loop is done when** you can name one command, already run at least once with its output shown, that reaches the defect's code path, asserts the person's exact symptom, gives the same verdict every run, finishes in seconds, and runs unattended. If you catch yourself reading code to build a theory before that command exists, stop, because that is the failure this skill exists to prevent.

## Reproduce and minimise

Run the loop and watch it go red. Confirm it produces the failure the person described and not a neighbor, that it reproduces across runs, and that the exact symptom is captured so the fix can later be checked against it. Then cut inputs, callers, configuration, data and steps one at a time, re-running after each cut, until every remaining element is load-bearing and removing any one of them turns the loop green. The minimal repro shrinks the hypothesis space and becomes the regression test.

Declare here whether the failure is functional or environmental. An environmental failure is diagnosed and fixed but does not count toward the two-failure limit of step 3; a functional one does.

## Hypothesise, then instrument one variable at a time

Write three to five ranked hypotheses before testing any, because a single hypothesis anchors on the first plausible idea. Each one states the prediction it makes, in the form "if X is the cause, changing Y makes the symptom disappear, and changing Z makes it worse". A hypothesis with no prediction is a vibe and gets sharpened or dropped. Show the ranked list to the person before testing, since they often re-rank it in one line, and proceed with your ranking if they are away.

Each probe maps to one prediction and changes one variable. Prefer a debugger or a REPL when the environment allows it, then targeted logs at the boundaries that separate hypotheses, and never log everything and grep. Tag every temporary log with one unique prefix so cleanup is a single grep. For a performance regression, logs are usually wrong; measure a baseline with a timing harness, a profiler or a query plan, then bisect. Measure first, fix second.

## Fix with the regression test seen red first

Write the regression test before the fix, at a seam where it exercises the real defect pattern as it occurs at the call site. If the only available seam is too shallow to replicate the chain that triggered it, a test there gives false confidence, and the absence of a correct seam is itself a finding to record. When a correct seam exists, turn the minimised repro into a failing test there, watch it fail for the expected reason, apply the fix, watch it pass, and re-run the original un-minimised loop.

## Close, and name the step it escaped from

Before declaring done, confirm the original loop no longer reproduces, the regression test passes or the missing seam is recorded, every tagged log is gone, every throwaway harness is deleted or marked, and the hypothesis that turned out right is stated in the commit message so the next person learns.

Then answer one question the method insists on. Which of the five steps let this defect through? Write the answer in the commit message and in the plan record, in this form.

```
Escaped from: step 2, the seam had no test that could go red on this
```

The options, with what each one means.

- **Step 1, the plan.** The interview never asked, or the shared understanding was wrong.
- **Step 2, the build.** No test at that seam, a test that could not go red on it, or a review that passed it.
- **Step 3, end to end.** The surface was not looked at, or the wrong surface was.
- **Step 4, QA of the QA.** The oracle was never falsified with this defect; the mutation chosen was a convenient one.
- **Step 5, verify.** The exit condition was checked by the same route, or an earlier run was cited instead of reality.
- **The route.** The work took a cheaper lane than it deserved and never ran the steps.

Naming the step is what turns a fixed bug into a control. If the answer points at an architectural cause, no seam, tangled callers, hidden coupling, say so after the fix is in, not before, because you know more now than when you started.
