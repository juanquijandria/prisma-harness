# Contributing

This repository applies its own method to itself, and a contribution is measured the way the gates measure a push. Reading `METHOD.md` first saves a round trip.

## What a change carries

- **A control that was red first.** Every deciding hook has a `--selftest` or a control under `tests/`. Reintroduce the defect, watch the control fail for the expected reason, then fix, then watch it pass. A pull request that adds a fix without the red run is sent back with that request.
- **No comments in code**, except the shebang and the one-line header that points to the section of `README.md` that documents the file. The comments gate has a ceiling of zero and blocks that header too, so a push that adds a file with one declares `PRISMA_COMMENTS_OK=1` with the reason in the commit body, as this repository's own commits do.
- **English** in code, messages, file names and commits. Spanish belongs under `docs/es/`.
- **No file over 300 lines.** Split it.
- **Counts that match.** A selftest declares `SELFTEST OK: N/N` and the runner compares that against the lines it printed.
- **A selftest sees nothing of the machine it runs on.** Whoever runs the suite may have any `PRISMA_` variable set, a global git configuration, a format configuration in the directory, or a home full of their own pages, and a fixture that inherits any of those is a red run with nothing broken. Every `--selftest` branch loads `hooks/selftest-env.sh` before it reads a setting. That file drops the whole namespace and hands the selftest a fresh sandbox as its home, its temporary directory, its project directory and its receipt. A test that needs a value sets it inline on the command it is testing, which still works because the sandbox is built first.
- **A test reads only what this repository publishes.** The list lives in `tests/shipped.sh` and a test never walks the tree above it, because that tree belongs to whoever installed the plugin and their own notes are not ours to judge.

## What not to touch casually

The canonical block in `docs/es/METHOD.md` is the source every registered copy is compared against. A change there is a change to the method, and it travels with the reason written in the commit body.

## Before opening a pull request

Run `sh tests/run-selftests.sh`. It runs every selftest, the controls, the format gate over the pages this repository publishes with the exemptions removed, and a syntax check of every hook and every test.

Then run `sh tests/runner-controls.sh`, which runs the suite again inside copies of the repository under a poisoned environment, with a hostile home and a format configuration in the tree, with foreign files added, from a path that contains a space, and with one hook silenced to prove that a selftest cannot disappear without being reported. It lives outside the runner because a runner cannot run itself. The three systems in `.github/workflows/selftests.yml` run both on every push.

## A gate that opened when it should not have

That is a security report and not a bug report. See `SECURITY.md`.
