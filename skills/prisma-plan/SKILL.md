---
name: prisma-plan
description: Step 1 of PRISMA, the plan. An interview in rounds that sharpens a request into shared understanding, leaves a written record, and closes by declaring the lane and whether the work fits in one session. Use when PRISMA routes work into code with logic, or when the user asks to plan, grill, stress-test or sharpen a piece of work before building it.
---

# PRISMA plan, step 1 of five

This is step 1 of the five steps in `METHOD.md`. It ends with a record that step 2 builds from, that the fidelity reviewer reads, and that steps 3 and 5 check against. Nothing gets built while this skill is open.

## The interview is a tree worked in rounds

Every decision branches into the decisions that hang off it. The frontier is the set of decisions whose prerequisites are already settled, so they can be asked now without guessing at an answer nobody has given. Ask the whole frontier in one round, numbered, each question with the answer you would pick and why in one line. Then wait. A question whose answer depends on another question still open in this round belongs to a later round.

Each question looks like this.

```
Q3  Where does the exported file land
    Options are the shared drive the team already reads, or an attachment in the message.
    Recommended: the shared drive, because the thread is not searchable and step 3 needs a surface to look at.
```

Facts are your job. When a question needs a fact from the repository, the filesystem or a tool, look it up or send a subagent to look it up, and never ask the person for something you could read. Do not block the round on it. A running lookup is an unsettled prerequisite, so only the questions downstream of it wait; ask the rest of the frontier now.

Each answered round reshapes the tree. Settled decisions push the frontier outward and unblock what depended on them. Recompute and ask the next round. The interview is over when the frontier is empty, every branch visited and nothing silently assumed.

**Not every open choice is the person's.** A question goes to the person only when a different answer would change what gets built, spend someone's money, be hard to undo, or reach an audience. Every other choice is a default you pick, say in one plain sentence, and record under Decisions with yourself as who decided, so the person can veto it. Open the first round with the answer to what the person actually asked, and explain in the same sentence any term the person did not use.

## What the interview must settle before it can close

These are the questions the later steps will ask, and they are cheaper to answer here than to discover at step 3.

- **The agreed behavior and the explicit exclusions.** The fidelity reviewer will check the code against both lists, no more and no less, so what is out of scope is written down, not implied.
- **The seams under test.** Step 2 writes tests only at seams agreed here, the public boundaries where behavior is observed without reaching inside. Agree on which seams carry the critical path and the complex logic, since not everything gets a test.
- **The surface where a person will see the result.** Step 3 requires naming it before looking, because afterwards one names what one already looked at. If no surface can be named, that is a finding of the plan, and the work does not activate anything.
- **The exit condition and its second route.** Step 5 checks the exit condition on the real source or surface and measures a figure again by another route. Name the condition and the second route now.
- **What is irreversible, what reaches an audience, and what costs money.** Those always get confirmed by the person, so mark them in the record.

## Closing the interview

Two declarations close the interview, and both are said out loud to the person, not only written.

**The lane.** Restate the lane the work was routed into and whether the interview moved it. A lane goes up when the interview uncovers stored data, permissions, integration or deployment that a cheaper lane would have missed. A lane never goes down in silence; going down is declared with the reason.

**The session estimate.** Say whether the work fits in one session, which is about 140k tokens of useful context. Count what the session will have to read, the files it touches and their neighbors, what the tests will print, the review round trip, and every unknown that still needs exploration. Work that touches more than about a dozen files, or that depends on more than one unknown, does not fit. If it does not fit, split it into session-sized tickets before anything is built. Each ticket carries the destination, what this ticket builds, its own exit condition, and what it depends on.

**The facts a transversal rule touches.** When the interview adopts a rule that applies to the whole system, list every fact that rule touches and review the list whole before anything is built. A rule applied only to the facts that already failed leaves the next one out.

```
Ticket 2 of 4: the import endpoint
Destination: the nightly file lands in the table and the chart reads it
This ticket builds: the endpoint and its validation, nothing of the scheduler
Exit condition: a real file from last night loads with zero rejected rows, counted by two routes
Depends on: ticket 1
```

## The record

Write the record where the repository already keeps plans or specs. If it keeps none, pick a folder next to the code, say which in one sentence, and reuse it for the session. The record has these fields, in this order, because the fidelity reviewer reads them by name.

```
# Plan record: <name in kebab-case>
Lane: <lane, and whether it moved during the interview>
Agreed: <the behavior, one line per item>
Out of scope: <what was asked about and left out, one line per item>
Seams under test: <one line per seam>
Surface: <where a person will see it>
Exit condition: <the condition, and the second route that measures it>
Fits one session: <yes, or no with the ticket list>
Decisions: <one line each, with the question number and who decided>
```

Do not start step 2 until the person confirms that the record is the shared understanding. Confirmation is a yes from the person, not the absence of a no.
