#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
PYTHON="${PRISMA_PYTHON-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "WARN: strip-quotes.sh needs python3 or python and found neither, quotes were not stripped." >&2; exit 3; }
stripped=$("$PYTHON" -c '
import re, sys
sys.stdout.reconfigure(newline="\n")
sys.stdout.write(re.sub(r"\x27[^\x27]*\x27|\"(?:[^\"\\]|\\.)*\"", " ", sys.stdin.read(), flags=re.S))
') || { echo "WARN: strip-quotes.sh could not run $PYTHON, quotes were not stripped." >&2; exit 3; }
printf '%s\n' "$stripped"
