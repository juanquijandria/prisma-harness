#!/bin/sh
# Prisma Harness. Documented in README.md, section "command-invokes".
PYTHON=$(command -v python3 || command -v python)
[ -n "$PYTHON" ] || { cat; exit 0; }
"$PYTHON" -c '
import re, sys
sys.stdout.write(re.sub(r"'"'"'[^'"'"']*'"'"'|\"[^\"]*\"", " ", sys.stdin.read()))
'
