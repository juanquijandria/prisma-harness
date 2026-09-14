# Prisma Harness

This repository is a Claude Code plugin and the written method it enforces. Read `METHOD.md` before changing anything under `hooks/` or `skills/`, and `STYLE.md` before writing any page.

- Every hook has a `--selftest`. Run `tests/run-selftests.sh` before and after a change; a gate whose selftest never fails is decoration.
- A gate is proven by a positive control, not by silence. Reintroduce the defect it exists for and watch it block, then remove it and watch it pass.
- Code, messages, file names and commits in English. No comments in code, except the shebang and the one-line header pointing to the README section.
- The canonical block in `docs/es/METHOD.md` is the reference every registered copy is compared against. Do not edit it casually.
