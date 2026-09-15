#!/bin/sh
# Prisma Harness. Documented in README.md, section "escape-declared".

escape_declared() {
  token="$1"
  printf '%s' "$2" | tr ';&|' '\n\n\n' | sed 's/#.*$//' \
    | grep -qE "^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*${token}([[:space:]]|\$)"
}

escape_selftest() {
  ok=1
  case_check() {
    if escape_declared PRISMA_SIZE_OK=1 "$2"; then got=yes; else got=no; fi
    if [ "$got" = "$3" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s, expected %s got %s\n' "$1" "$3" "$got"; ok=0; fi
  }
  case_check "1 the escape in front of the command counts" "PRISMA_SIZE_OK=1 git push origin main" yes
  case_check "2 the escape after another assignment counts" "FOO=bar PRISMA_SIZE_OK=1 git push origin main" yes
  case_check "3 the escape in a trailing comment does not count" "git push origin main # PRISMA_SIZE_OK=1 because" no
  case_check "4 the escape as an argument of another command does not count" "echo PRISMA_SIZE_OK=1 reason && git push origin main" no
  case_check "5 the escape on its own segment counts" "ls; PRISMA_SIZE_OK=1 git push origin main" yes
  case_check "6 no escape at all" "git push origin main" no
  case_check "7 a similar token that is not the escape does not count" "PRISMA_SIZE_OK=10 git push origin main" no
  [ "$ok" = "1" ] && printf 'SELFTEST OK: 7/7\n' && exit 0
  printf 'SELFTEST FAILED\n'; exit 1
}

[ "${PRISMA_ESCAPE_SOURCED:-0}" = "1" ] && return 0
[ "$1" = "--selftest" ] && escape_selftest
printf 'usage: escape-declared.sh --selftest, or source it and call escape_declared <token> <command>\n' >&2
exit 2
