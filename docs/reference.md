# Prisma Harness reference

Everything the README leaves out, each piece in full, every setting and escape, what each gate holds and what it does not catch.

## What is inside


| Piece | What it does | When it runs |
|---|---|---|
| `METHOD.md` | the method in English, lanes, steps, gates, single-model mode | you read it |
| `docs/es/METHOD.md` | the canonical block in Spanish, the reference this plugin ships | `check-canonical-sync.sh` compares your copies against it at session start |
| `STYLE.md`, `docs/es/STYLE.md` | the writing rules and which ones the format gate enforces | you read it |
| `skills/prisma/SKILL.md` | the operating order of the method, invoked as `prisma` | when you say "PRISMA" |
| `skills/prisma-plan/SKILL.md` | step 1, the interview in rounds that leaves a record and closes with the lane and the session estimate | when `prisma` reaches step 1 |
| `skills/prisma-build/SKILL.md` | step 2, tests first at the agreed seams, every control seen red before the code, then the review, then the commit | when `prisma` reaches step 2 |
| `skills/prisma-fidelity-review/SKILL.md` | the fidelity reviewer, two axes kept apart, run in a fresh subagent against the plan record | when `prisma-build` reaches its review, or when you ask for a review |
| `skills/prisma-diagnose/SKILL.md` | step 2b, the loop before the hypothesis, and the step the defect escaped from at the end | when something is broken |
| `hooks/gate-read-index.sh` | blocks a write under the docs dir if the session never read the index | `PreToolUse` on Write and Edit |
| `hooks/pre-push-comments.sh` | measures whether a push or PR adds comment lines, figures in comments, or `file:line` references, and blocks when `PRISMA_COMMENTS_BLOCK=1` | `PreToolUse` on Bash |
| `hooks/pre-push-size.sh` | warns over 200 changed lines, blocks over 400, and tells a stale branch apart from a big change | `PreToolUse` on Bash |
| `hooks/pre-push-lint.sh` | runs the repo's own linter, `php-cs-fixer` or `eslint`, on the diff before the push | `PreToolUse` on Bash |
| `hooks/shell-traps.sh` | catches four commands that fail or hurt without saying so. Under zsh a `grep --include` pattern left unquoted, which zsh aborts with no match while the rest of the line goes on, and a word that starts with `==`, which zsh reads as the path of a command and stops with `= not found`, get quoted by the gate itself and the quoted command runs, with `hooks/quote-zsh-words.sh` doing the quoting, and the same rewrite leaves files named `.env` out of a search over a folder, so it matches the one of `hooks/secret-reads.sh` whichever of the two Claude Code applies; when that cannot be done safely, as with nested braces or a `$` inside the word, the gate blocks. A `timeout` that is not installed blocks, since the command it wraps never runs. A fourth trap is a `pkill` or `killall` whose pattern reaches a process whose working folder is outside the folder of the session, and the gate compares folders, not sessions; `hooks/kill-targets.sh` lists what the pattern matches and the gate blocks naming each process. `PRISMA_SHELL_TRAPS_OK=1` lets one through | `PreToolUse` on Bash |
| `hooks/secret-reads.sh` | keeps the lines of a secrets file out of the console, where they would stay in the transcript. A secrets file is `.env`, `.env.<anything>` or a name ending in `.env`, and `.env.example`, `.env.sample` and `.env.template` can be read directly, while a search over a folder leaves them out with the other `.env` files. Reading one with `cat`, `head`, `tail`, `less`, `more`, `bat`, `sed`, `awk`, `xxd`, `diff`, `strings`, `nl`, `sort`, `uniq`, `tac`, `rev`, `fold`, `paste`, `column`, `od`, `hexdump`, `base64` or `cut` past its first field, or searching one by name with `grep`, `rg`, `git grep`, `git diff`, `git show` or `git log -p`, blocks, and so does a `grep --include` or an `rg -g` that reaches one, since it would beat the exclusion, and the message says how to see only the names. An input redirection from one blocks with any program, and so does `xargs` or `find -exec` running a reader when the command names a secrets file. A search over a folder is not blocked, it runs with the secrets files excluded, `--exclude` for `grep -r`, `-g` for `rg` and a pathspec for `git grep`, `git diff`, `git show` and `git log -p`. The agent is told what ran, so it does not read the missing lines as absent. Listing names with `-l` or counting with `-c` passes untouched. `hooks/secret-args.sh` places the exclusion and `hooks/secret-names.sh` reads the arguments, and a command it cannot read passes and is written down as unmeasured. `PRISMA_SECRET_READS_OK=1` lets one through | `PreToolUse` on Bash |
| `hooks/format-gate.sh` | the format gate over pages touched today, rules in `.prisma-format.conf`. It blocks a stop once, and lets through the stop Claude Code marks as already continued | `Stop` |
| `hooks/claim-ready-gate.sh` | reads the last message of the agent, and when a sentence says a PR is ready to merge or green and names it, by link or by number, it runs `pr-ready.sh` on that PR and blocks the stop with what is missing. A claim that is denied or asked is not a claim, and green is not a claim in a sentence that denies the PR is ready. When it cannot measure it lets the stop through and says so in the receipt | `Stop` |
| `hooks/paste-block-gate.sh` | reads the last message of the agent, and when a block between two lines of `═` carries a hole to fill, a value cut short as `=TEST…` or one that names itself as a placeholder such as `YOUR_TOKEN_HERE`, a marker such as `<your token>` or `[name]`, or a word such as `TODO`, it blocks the stop naming the hole, because that block is pasted as it is. A template variable such as `{{name}}`, dots inside a sentence, a quotation and a hole outside the block do not count. `PRISMA_PASTE_OK=1` on a line of its own outside the block lets one through, and when it cannot measure it lets the stop through and says so in the receipt | `Stop` |
| `hooks/handoff-card-gate.sh` | reads the code blocks of the last message of the agent, and when one launches another session with `claude` or a command named in `PRISMA_LAUNCH_COMMANDS`, it blocks the stop unless that launch carries its card, a name after `-n` and a row in a table outside the code whose first cell names it and whose six cells each carry a letter or a digit, the session, why, what it delivers, its order, who it reports to and when it closes. A headless run with `-p`, a session reopened with `--resume` or `--continue`, a subcommand such as `claude plugin update`, and `--version` or `--help` do not count. A first argument that is a bare lowercase word is read as a subcommand, so a prompt goes in quotes. The words of the header are not read, so a card works in any language. `PRISMA_HANDOFF_OK=1` on a line of its own outside the code lets one through, and when it cannot measure it lets the stop through and says so in the receipt | `Stop` |
| `hooks/pr-ready.sh` | says whether a PR is ready to merge from what GitHub shows, now or as it stood at a past moment with `--at`. Every CI run on the head finished as success, neutral or skipped, with at least one real success, and a head with no run at all counts only when the repository has no active workflow under `.github/workflows/`, so a repository whose only workflow runs on a schedule leaves every PR without runs not measured. Every reviewer in `PRISMA_PR_REVIEWERS` wrote after the last push, no reviewer, listed or not, has a request for changes standing since their last approval, the PR is not a draft, GitHub does not call it blocked, it does not conflict with its base, and inside a clone of the repository it does not conflict with another open PR of the same author on a shared file, which `hooks/pr-ready-conflicts.sh` measures with `git merge-tree`. A base that is not the default branch is not the head of a merged PR that still points at the commit that PR carried, unless the branch is protected, since merging there never reaches the default branch. A formal review counts only when it approves or comments on the head itself. An answer from GitHub of another shape than the endpoint returns is not measured. It exits 0 ready, 1 not ready and 3 when it could not measure | you call it, and the claim gate calls it |
| `hooks/check-canonical-sync.sh` | compares the canonical block across every registered copy, never edits | `SessionStart` |
| `hooks/session-voice.sh` | injects the writing rules of `STYLE.md` into every session, says so once per project, and `PRISMA_VOICE=0` switches it off | `SessionStart` |
| `hooks/session-size.sh` | tells the agent once per session, when the context passes 80% of its window, how many thousand tokens every call rereads and which share of the window that is, and to recommend /compact. It never proposes a new session. The window is 1M unless `PRISMA_CONTEXT_WINDOW` or `CLAUDE_CODE_DISABLE_1M_CONTEXT` says otherwise, and a smaller `CLAUDE_CODE_AUTO_COMPACT_WINDOW` rules. `PRISMA_SESSION_SIZE=0` switches it off | `UserPromptSubmit` |
| `hooks/session-deps.sh` | names the required tools that are missing, with the install command, and tells the agent to ask before installing. Silent when nothing is missing. `PRISMA_DEPS_CHECK=0` switches it off | `SessionStart` |
| `hooks/notes-machinery.sh` | reports a git repository, a package manifest, a module folder or a virtual environment nested inside a tree meant to hold information and no code. It needs `PRISMA_NOTES_ROOT` | `SessionStart` and `Stop` |
| `hooks/blind-replica.sh` | builds the blind brief, claim and sources only, for the fifth gate, and with an auditor configured its exit code is the verdict | you call it |
| `hooks/receipt.sh` | one local line per block, rewrite, escape, warning, or gate that could not measure, and a summary you paste to whoever asks | the gates write it, you read it |
| `hooks/measure-comments.sh`, `measure-diff-size.sh`, `compare-base.sh`, `command-invokes.sh`, `strip-quotes.sh`, `escape-declared.sh`, `github-remote.sh` | the helpers the gates share | called by the gates |

## What the suite checks

The push gate controls block a real defect and then let the corrected diff through. The never-fabricate suites check that a gate that did not measure never reports a verdict and that it leaves its line in the receipt. A session is sized against its context window, and a control fails if the old fixed size comes back. `tests/run-selftests.sh` runs all of it, checks that the pages this repository publishes obey the rules it ships, and fails any suite whose printed cases do not match the count it claims, or that prints no count at all. A gate whose tests never fail is decoration. The counts themselves live in the README, where the suite reads them.

## The writing rules, and how to turn them off

This plugin sets writing rules at the start of every session, and it tells you so in the first session of each project. If you want the verification and not the prose style, put this in your Claude Code settings.

```json
{ "env": { "PRISMA_VOICE": "0" } }
```

Or say it in your own words to your agent, which is shorter.

```
Turn off the PRISMA writing rules for this project.
```

## Two things that read as heavier than they are

**Something broken does not go through the interview.** `skills/prisma-diagnose/SKILL.md` has its own trigger and asks for no plan record. Step 1 is for work that is being decided, not for a defect that is being reproduced.

**The comments gate does not block until you ask it to.** Out of the box it measures the diff and says what it found. `PRISMA_COMMENTS_BLOCK=1` turns that measurement into a block.

## What is enforced, and by what

"It passed PRISMA" means three different things depending on the promise. A hook blocks on its own. The agent is asked, and the transcript and the receipt are the evidence. A person, or evidence from outside the machine, decides the rest, and this repository enforces none of that third kind. The push gates measure the checked-out HEAD against its base, so a branch pushed from elsewhere is not measured and the gate says so, and a repository listed in `PRISMA_SKIP_REPOS` is never measured.

| Promise | Held by | How you know |
|---|---|---|
| no page under the docs dir is written **with Write or Edit** without reading the index | hook | the index gate blocks, and it has no escape. A page written by a shell command is outside it |
| no push from a watched repository carries comment lines, figures in comments or file and line references | hook, once `PRISMA_COMMENTS_BLOCK=1` | the comments gate blocks HEAD or says it measured nothing, and an escape is recorded in the receipt. Without the setting it only warns |
| no push from a watched repository passes the size ceiling | hook | the size gate blocks HEAD, and an escape is recorded |
| a push from a watched repository passes its own linter | hook | the lint gate blocks HEAD or says it measured nothing, and an escape is recorded |
| a page touched today follows the writing rules | hook | the format gate blocks the stop, and a rule switches off in config |
| no session ends saying a PR is ready to merge while its CI has not finished, a reviewer wrote before the last push, or it conflicts | hook | the claim gate blocks the stop with what is missing, and a stop it could not measure is in the receipt. A claim it cannot read, or one made in an earlier message, is outside it |
| the canonical block matches every registered copy | agent | the sync check reports drift at session start and never blocks |
| the five steps run for code with logic | agent | the skill orders them, and the transcript shows whether they ran |
| a finding is reproduced before it is repeated as a fact | agent | the transcript |
| a figure is measured by a second route | agent | `blind-replica.sh` builds the brief and reads the verdict, and it does not judge its truth |
| the result was looked at on the surface a person sees | person | step 3, and nobody else can do it |
| the exit condition holds where the work landed | outside evidence | step 5, on the real source |
| the gates reduce escaped defects | outside evidence | the receipt counts blocks, not whether each block was right |

## Configure

Environment variables, all optional.

| Variable | Default | Meaning |
|---|---|---|
| `PRISMA_DOCS_ROOT` | the project directory | where your documentation lives |
| `PRISMA_DOCS_DIR` | `wiki` | the pages folder under the root that the index gate and the format gate watch |
| `PRISMA_INDEX_FILE` | `index.md` | the file a session must read before writing a page |
| `PRISMA_FORMAT_CONFIG` | `<docs root>/.prisma-format.conf` | rule switches, see `STYLE.md` and `.prisma-format.conf.example` |
| `PRISMA_CANONICAL`, `PRISMA_CANONICAL_COPIES` | the plugin's Spanish block, and `~/.claude/CLAUDE.md` plus the project `CLAUDE.md` when they carry the markers | what the sync check compares |
| `PRISMA_SIZE_WARN_OVER`, `PRISMA_SIZE_BLOCK_OVER` | 200, 400 | the size gate thresholds |
| `PRISMA_COMMENTS_MAX_PCT`, `PRISMA_COMMENTS_MAX_BLOCK` | 0, 0 | the comments gate ceilings |
| `PRISMA_COMMENTS_BLOCK` | 0 | the comments gate measures and warns. Set it to 1 and the ceiling blocks the push |
| `PRISMA_SKIP_REPOS` | empty | absolute paths where the push gates do not apply |
| `PRISMA_AUDITOR_CMD` | empty | a command that receives the blind brief on stdin and answers as a second engine |
| `PRISMA_VOICE` | 1 | set to 0 to stop injecting the writing rules at session start |
| `PRISMA_SESSION_SIZE` | 1 | set to 0 to stop the warning when a session passes 80% of its context window |
| `PRISMA_CONTEXT_WINDOW` | 1000000, or 200000 with `CLAUDE_CODE_DISABLE_1M_CONTEXT` | the context window of your model in tokens. No hook receives it from Claude Code, so a model with a 200k window needs this set, or the size warning stays quiet |
| `PRISMA_DEPS_CHECK` | 1 | set to 0 to stop the dependency notice at session start |
| `PRISMA_NOTES_ROOT` | empty | the tree that holds information and no code. Without it the machinery detector says nothing |
| `PRISMA_MACHINERY_MARKERS`, `PRISMA_MACHINERY_SKIP` | `.git node_modules package.json .venv venv`, `.obsidian raw Clippings archive` | what that detector counts as machinery, and the folders it does not walk into |
| `PRISMA_LAUNCH_COMMANDS` | empty | more commands the handoff card gate reads as launching another session, besides `claude`, such as an alias of yours |
| `PRISMA_RECEIPT` | 1 | set to 0 to stop writing the receipt |
| `PRISMA_RECEIPT_FILE` | `~/.prisma-harness/receipts.log` | where the receipt is written |
| `PRISMA_REQUIRED_TOOLS` | the requirements in the README, under Install | what the dependency check looks for, spaces or commas |
| `PRISMA_PR_REVIEWERS` | `claude[bot]` | the reviewers `pr-ready.sh` waits for, by login, spaces or commas. Each one needs a comment, or a review on the head that approves or comments, after the last push, and `claude[bot]` counts only once its comment says it finished. Empty asks for none |
| `PRISMA_GH` | `gh` | the GitHub CLI that `pr-ready.sh` calls, the seam its selftest uses to answer with fixtures |
| `PRISMA_REQUIRED_WRAPPERS` | `timeout` | the programs that wrap another command, which the shell traps gate blocks when one is invoked and not installed |
| `PRISMA_HOOKS_DIR` | the folder of the running hook | where a gate looks for its siblings |
| `PRISMA_UNAME` | the real one | the seam the dependency check uses to test itself |
| `PRISMA_PYTHON`, `PRISMA_JQ`, `PRISMA_LSOF`, `PRISMA_PGREP`, `PRISMA_TMPDIR`, `PRISMA_PARSER_FAULT` | the real ones, and no fault | seams the gates use to test what they do when a tool, a directory or the parser fails |

The three push gates have a declared escape, `PRISMA_COMMENTS_OK=1`, `PRISMA_SIZE_OK=1`, `PRISMA_LINT_OK=1`, placed in front of the command, and the shell traps gate has `PRISMA_SHELL_TRAPS_OK=1` the same way. The paste block gate has `PRISMA_PASTE_OK=1`, on a line of its own in the message and outside the block, since inside it would be pasted. The secret reads gate has `PRISMA_SECRET_READS_OK=1` at the start of the command, and with it the files of secrets stay in the search. The reason goes in the change description. An escape used by default is not a gate. The index gate has no escape, reading the index is the fix. The format gate has no escape either; a rule you do not want is switched off in its config.

**Where 200 and 400 come from.** They are this repository's policy, shaped by one source, [a ten-month case study of 2,500 reviews](https://static1.smartbear.co/support/media/resources/cc/book/code-review-cisco-case-study.pdf) in one product group at Cisco, run and written in 2006 by the vendor of the review tool it measured. It concludes that lines under review should be under 200 and should not exceed 400.

Read it before trusting the defaults. Its defect counts come from a hand-coded sample of 300 of those reviews, not from all 2,500. It sets aside a fifth of the reviews as uninteresting. Its own footnote flags the assumption the whole inference rests on, that true defect density is constant across large and small changes. Its summary advice is narrower, between 100 and 300 lines at a time. And it never says whether its lines under review are the lines a diff counts, which is what this gate measures. That is the only claim this repository makes about the literature. The numbers are yours to change, and the gate prints the policy and never the study.

## The receipt

Every time a gate blocks something, corrects a command and lets it run, gets passed with an escape where it would have blocked, measures something it was not asked to block, or cannot measure at all, one line lands in `~/.prisma-harness/receipts.log` with the date and time, the gate, the repository, and which of those five it was, and nothing else. A push gate leaves that line only when the command looks like a push, so a broken parser does not write one on every Bash command. A repository with no linter leaves no line from the lint gate, because there was nothing to measure. A gate that finds `receipt.sh` or `push-names-head.sh` missing prints its `WARN` and leaves no line, because the code that writes the line is the code that is missing. A gate that could not measure did not pass anything, so the summary counts each kind in its own column. The file never leaves your machine unless you paste it, and the hooks and the terminal command share it on purpose.

```
sh hooks/receipt.sh --summary
```

That prints one row per gate with blocks, rewrites, escapes and the first and last day, ready to paste into a chat. It shows which gates catch things in your work and which never fire. It counts blocks, not whether each block was right, and it cannot see what no gate caught. `PRISMA_RECEIPT=0` switches it off, `--path` shows where the file is, `--reset` empties it after asking.

## What not to change without writing the reason

- **The canonical block in `docs/es/METHOD.md`.** Every registered copy is compared against it; editing it here makes every copy drift on purpose.
- **A gate's exit codes.** As a hook, `0` passes and `2` blocks; a gate that cannot measure prints a `WARN` and exits `0`. On the command line the format gate exits `1` on failures. A gate that fails silently fabricates a verdict. `hooks/blind-replica.sh` is a command and not a hook, and its codes are its own, `0` the auditor confirmed, `5` it refuted, `4` no verdict, `6` no auditor is configured and only the brief was printed, `2` the brief itself could not be read. `hooks/pr-ready.sh` is a command too, `0` ready, `1` not ready, `3` it could not measure, `2` the arguments could not be read.
- **The selftests.** Change a gate, reintroduce the exact defect it exists for, watch it block, remove it, watch it pass. Silence proves nothing.

## Gotchas

- **A hook registered in this session does not run in this session.** Settings are read at startup. Test a new hook in a new session.
- **`hooks/hooks.json` and `skills/` load by convention.** Naming them again in `plugin.json` makes Claude Code refuse the plugin as a duplicate, even where a local `--plugin-dir` load did not complain.
- **The comments gate skips files whose extension it does not know**, and it counts only lines your diff adds.
- **The index gate watches Write and Edit, not the shell.** A page created with `cat > page.md` or a redirect never reaches it, so an agent that writes through the shell walks past it. Only a Read of the index that did not error opens it, since Claude Code lets a Write replace a file that was never read.
- **The command parser, `command-invokes.sh`, is not a shell parser.** It respects quotes, escapes, comments and redirections and never drops content, but it does not resolve expansions, aliases, `eval` or globbing. It reads a heredoc body as commands, so a `git push` inside one counts as a push. When a quote is left unbalanced it returns the union of the plausible readings instead of one. Either way a gate may block a command it did not need to block, and the fix is to split the command in two. It is rare, and deterministic when it happens.
- **The kill trap judges a process by its working folder.** A process that runs inside the folder of the session counts as its own, so a session opened in a parent folder of another terminal is not stopped from killing that terminal's processes. On macOS `killall` matches the process name and the gate looks with `pgrep -x`, which also matches the first argument, so it can block a `killall` that would have hit nothing. Where there is no `pgrep`, as in Git Bash on Windows, the gate measures nothing and lets the command through with a not-measured line in the receipt.
- **The shell traps gate knows four traps, and it reads the shell from `$SHELL`.** It rewrites the command through the `updatedInput` field of a `PreToolUse` hook, and the receipt records that as `rewritten`. A pattern or a word inside a heredoc body, a comment, a quoted string, `[[ ]]`, `(( ))` or the patterns of a `case` stays as written, because zsh does not expand it there. A command substitution written with backticks stays as written too, because the gate does not read inside it, so a trap there is not caught. A heredoc ends only on a line equal to its delimiter, as in the shell. The `--include` and `==` traps only act under zsh, and a zsh with `nomatch` switched off never has the first, so there the quotes were not needed, and they do not change what the command does. A single `=name` is the expansion zsh means and is left alone. A search run through `xargs`, `eval`, `bash -c` or a script file is outside it, and so is a `timeout` written inside a quoted string.
- **The claim gate reads one message, one sentence at a time.** It judges the last message of the agent, and only a sentence that names the PR by a GitHub link, by `owner/repo#number`, or by `#number` inside a clone whose `origin` is on GitHub. A list of PRs under a heading that says they are ready names them on other lines and is not read. A no or a not in the three words before the claim, inside its own clause, denies it. With `--at`, `pr-ready.sh` cannot see the draft and mergeable state of the past and says so, it reads each review in the state it has today, so one dismissed after that moment no longer counts, it compares PRs on the heads they had then but on the files they touch today, and it reads the list of workflows, the base of the PR and whether that base is protected as they are today.
- **On Windows, Git Bash rewrites a path handed to a native program.** An argument that looks like a Unix path becomes a Windows one, so `jq --arg some_path /tmp/x` reaches jq as `C:/.../tmp/x` while the JSON it reads still says `/tmp/x`, and the comparison silently fails. A hook here compares paths in the shell and never hands one to jq as data.
- **Claude Code can compact a long session on its own when it sits idle for about an hour.** `"idleCompaction": false` in your Claude Code settings switches that off.
- **`--changed` in the format gate finds pages modified today** by file time, not by git.
- **The size gate measures HEAD**, not the ref you are pushing. If you push another branch from `main`, it prints a `WARN` and does not measure. It reads HEAD when the hook runs, before the command, so a command that switches branch or rewrites the last commit before its push is measured on the HEAD it started from.
- **The lint and comments gates check exactly what the push sends, or say they did not.** They read the commits, with the diff settings of the git configuration switched off. The lint gate runs the linter on the files and the configuration on disk, so it measures only when no tracked file has uncommitted changes, and otherwise prints a `WARN`. Every git call in the command has to be one known to leave the commits alone, push, status, log, diff, show, rev-parse, merge-base, ls-files, ls-remote, describe, fetch, add, tag, branch, blame, shortlog, rev-list, cat-file or for-each-ref. Any other, or one the gate cannot read such as one with `-C`, makes both print a `WARN` and measure nothing. Push in a command of its own to have it measured. No push gate measures a push without a refspec when `push.default` is `matching` or `nothing`, when a push refspec or a mirror is configured, or when the command sets push or remote settings itself. A push that sends only tags or deletes a branch is measured by none of the three.
- **What the push gates cannot see.** A commit or a change of branch that the command parser does not reach, inside `$( )`, backticks, `eval`, `xargs`, `sh -c`, an alias, a wrapper such as `nice`, an `if`, `while` or `until` condition, or another program such as `npm version`. A `cd` that is not the first thing in the command, so a gate may read the repository the session stands in. `gh pr create --head` and `gh pr ready` with a number are read as the local HEAD. Tags that go out together with a branch. A fetch into the checked-out branch with `--update-head-ok`, and a git option that runs another program, such as `--upload-pack`. Replace refs, files marked skip-worktree or assume-unchanged, an untracked or ignored file the linter reads, and line endings that `core.autocrlf` rewrites on disk.

## What Prisma Harness refuses to be

- **Not an eval framework.** No datasets, no scores, no dashboards. Five gates with names, each with the case that pays for it.
- **Not a second model watching the first.** It runs on one model and says out loud what that costs.
- **Not a reviewer of taste.** The format gate reads how a page is written; nothing here grades code quality.
- **Not silent.** A gate that cannot measure prints a warning. Silence never means clean.
