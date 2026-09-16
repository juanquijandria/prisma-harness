#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
if [ "${1:-}" = "--selftest" ]; then . "$(cd "$(dirname "$0")" && pwd)/selftest-env.sh"; fi

REQUIRED_TOOLS=$(printf '%s' "${PRISMA_REQUIRED_TOOLS:-jq python3 git awk cmp bash mktemp find sed}" | tr ',' ' ')

missing_tools() {
  missing=""
  if command -v xcode-select >/dev/null 2>&1 && ! xcode-select -p >/dev/null 2>&1; then
    missing="command-line-tools"
  fi
  for tool in $REQUIRED_TOOLS; do
    case "$tool" in
      python3) command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || missing="$missing python3" ;;
      *) command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool" ;;
    esac
  done
  printf '%s' "$missing" | sed 's/^ *//'
}

report() {
  tools=$(missing_tools)
  [ -z "$tools" ] && return 0
  printf 'PRISMA DEPENDENCIES, checked at session start. Tell the person what is missing and offer the install command. Never install anything without their explicit yes.\n'
  if [ -n "$tools" ]; then
    printf -- '- Missing on this machine: %s. Without them the gates cannot measure, and they pass with a warning instead of blocking.\n' "$tools"
    case " $tools " in *" command-line-tools "*) printf '  macOS Command Line Tools, which bring git and python3: xcode-select --install\n' ;; esac
    printf '  macOS with Homebrew: brew install %s\n' "$(printf '%s' "$tools" | sed 's/command-line-tools//; s/^ *//')"
    printf '  Debian or Ubuntu: sudo apt install %s\n' "$(printf '%s' "$tools" | sed 's/command-line-tools//; s/^ *//')"
    case "${PRISMA_UNAME:-$(uname -s 2>/dev/null)}" in MINGW*|MSYS*|CYGWIN*) printf '  Windows with Git Bash: winget install jqlang.jq Python.Python.3.12\n' ;; esac
  fi
}

if [ "$1" = "--selftest" ]; then
  SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")
  ok=1; T=$(mktemp -d)
  run() { printf '{}' | PRISMA_REQUIRED_TOOLS="$1" sh "$SELF"; }
  out=$(run "sh")
  if [ -z "$out" ]; then printf 'PASS quiet when every tool is present\n'; else printf 'FAIL expected silence, got: %s\n' "$out"; ok=0; fi
  out=$(run "sh,no-such-tool-alpha,no-such-tool-beta")
  if printf '%s' "$out" | grep -q "Missing on this machine: no-such-tool-alpha no-such-tool-beta" && printf '%s' "$out" | grep -q "brew install no-such-tool-alpha no-such-tool-beta"; then printf 'PASS names the missing tools with the install command\n'; else printf 'FAIL tools case: %s\n' "$out"; ok=0; fi
  if printf '%s' "$out" | grep -q "Never install anything without their explicit yes"; then printf 'PASS tells the agent to ask before installing\n'; else printf 'FAIL no consent line\n'; ok=0; fi
  out=$(printf '{}' | PRISMA_REQUIRED_TOOLS="no-such-tool-alpha" PRISMA_UNAME="MINGW64_NT-10.0" sh "$SELF")
  if printf '%s' "$out" | grep -q "winget install"; then printf 'PASS on Windows it offers the winget command\n'; else printf 'FAIL no winget line: %s\n' "$out"; ok=0; fi
  out=$(printf '{}' | PRISMA_REQUIRED_TOOLS="no-such-tool-alpha" PRISMA_UNAME="Darwin" sh "$SELF")
  if ! printf '%s' "$out" | grep -q "winget install"; then printf 'PASS off Windows it does not offer winget\n'; else printf 'FAIL winget offered on Darwin\n'; ok=0; fi
  out=$(printf '{}' | PRISMA_REQUIRED_TOOLS="no-such-tool-alpha" PRISMA_DEPS_CHECK=0 sh "$SELF")
  if [ -z "$out" ]; then printf 'PASS PRISMA_DEPS_CHECK=0 switches it off\n'; else printf 'FAIL switch: %s\n' "$out"; ok=0; fi
  rm -rf "$T"
  [ "$ok" = "1" ] && printf 'SELFTEST OK: 6/6\n' && exit 0
  printf 'SELFTEST FAILED\n'; exit 1
fi

[ "${PRISMA_DEPS_CHECK:-1}" = "1" ] || exit 0
cat >/dev/null
report
exit 0
