# Contributing

This repository applies its own method to itself, and a contribution is measured the way the gates measure a push. Reading `METHOD.md` first saves a round trip.

## What a change carries

- **A control that was red first.** Every deciding hook has a `--selftest` or a control under `tests/`. Reintroduce the defect, watch the control fail for the expected reason, then fix, then watch it pass. A pull request that adds a fix without the red run is sent back with that request.
- **No comments in code**, except the shebang and the one-line header that points to the section of `README.md` that documents the file. The comments gate has a ceiling of zero and blocks that header too, so a push that adds a file with one declares `PRISMA_COMMENTS_OK=1` with the reason in the commit body, as this repository's own commits do.
- **English** in code, messages, file names and commits. Spanish belongs under `docs/es/`.
- **No file over 300 lines.** Split it.
- **Counts that match.** A selftest declares `SELFTEST OK: N/N` and the runner compares that against the lines it printed.

## What not to touch casually

The canonical block in `docs/es/METHOD.md` is the source every registered copy is compared against. A change there is a change to the method, and it travels with the reason written in the commit body.

## Before opening a pull request

Run `sh tests/run-selftests.sh`. It runs every selftest, the controls, the format gate over the pages of this repository with the exemptions removed, and a syntax check of every hook. The three systems in `.github/workflows/selftests.yml` run the same thing on every push.

## A gate that opened when it should not have

That is a security report and not a bug report. See `SECURITY.md`.
