#!/bin/sh
# Prisma Harness. Documented in README.md, section "command-invokes".
python3 -c '
import re, sys
sys.stdout.write(re.sub(r"'"'"'[^'"'"']*'"'"'|\"[^\"]*\"", " ", sys.stdin.read()))
'
