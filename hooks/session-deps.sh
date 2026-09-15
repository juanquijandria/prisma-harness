#!/bin/sh
# Prisma Harness. Documented in README.md, section "session-deps".

INSTALLED="${PRISMA_INSTALLED_PLUGINS:-$HOME/.claude/plugins/installed_plugins.json}"
REQUIRED_TOOLS=$(printf '%s' "${PRISMA_REQUIRED_TOOLS:-jq python3 git awk cmp bash}" | tr ',' ' ')
POCOCK_ID="mattpocock-skills@claude-plugins-official"

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

pocock_present() {
  [ -r "$INSTALLED" ] && grep -q "\"mattpocock-skills@" "$INSTALLED"
}

report() {
  tools=$(missing_tools)
  pocock_ok=1; pocock_present || pocock_ok=0
  [ -z "$tools" ] && [ "$pocock_ok" = "1" ] && return 0
  printf 'PRISMA DEPENDENCIES, checked at session start. Tell the person what is missing and offer the install command. Never install anything without their explicit yes.\n'
  if [ -n "$tools" ]; then
    printf -- '- Missing on this machine: %s. Without them the gates cannot measure, and they pass with a warning instead of blocking.\n' "$tools"
    case " $tools " in *" command-line-tools "*) printf '  macOS Command Line Tools, which bring git and python3: xcode-select --install\n' ;; esac
    printf '  macOS with Homebrew: brew install %s\n' "$(printf '%s' "$tools" | sed 's/command-line-tools//; s/^ *//')"
    printf '  Debian or Ubuntu: sudo apt install %s\n' "$(printf '%s' "$tools" | sed 's/command-line-tools//; s/^ *//')"
  fi
  if [ "$pocock_ok" = "0" ]; then
    printf -- '- The plugin mattpocock-skills is not installed. Steps 1 and 2 of PRISMA invoke its skills. Install it once with /plugin install %s, or run the same sequence by hand as METHOD.md describes.\n' "$POCOCK_ID"
  fi
}

if [ "$1" = "--selftest" ]; then
  SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")
  ok=1; T=$(mktemp -d)
  printf '{"plugins":{"%s":[{}]}}' "$POCOCK_ID" > "$T/present.json"
  printf '{"plugins":{"other@x":[{}]}}' > "$T/absent.json"
  run() { printf '{}' | PRISMA_INSTALLED_PLUGINS="$1" PRISMA_REQUIRED_TOOLS="$2" sh "$SELF"; }
  out=$(run "$T/present.json" "sh")
  if [ -z "$out" ]; then printf 'PASS quiet when every tool and the plugin are present\n'; else printf 'FAIL expected silence, got: %s\n' "$out"; ok=0; fi
  out=$(run "$T/absent.json" "sh")
  if printf '%s' "$out" | grep -q "mattpocock-skills is not installed" && ! printf '%s' "$out" | grep -q "Missing on this machine"; then printf 'PASS names only the plugin when only the plugin is missing\n'; else printf 'FAIL plugin case: %s\n' "$out"; ok=0; fi
  out=$(run "$T/present.json" "sh,no-such-tool-alpha,no-such-tool-beta")
  if printf '%s' "$out" | grep -q "Missing on this machine: no-such-tool-alpha no-such-tool-beta" && printf '%s' "$out" | grep -q "brew install no-such-tool-alpha no-such-tool-beta"; then printf 'PASS names the missing tools with the install command\n'; else printf 'FAIL tools case: %s\n' "$out"; ok=0; fi
  if printf '%s' "$out" | grep -q "Never install anything without their explicit yes"; then printf 'PASS tells the agent to ask before installing\n'; else printf 'FAIL no consent line\n'; ok=0; fi
  out=$(printf '{}' | PRISMA_INSTALLED_PLUGINS="$T/absent.json" PRISMA_DEPS_CHECK=0 sh "$SELF")
  if [ -z "$out" ]; then printf 'PASS PRISMA_DEPS_CHECK=0 switches it off\n'; else printf 'FAIL switch: %s\n' "$out"; ok=0; fi
  rm -rf "$T"
  [ "$ok" = "1" ] && printf 'SELFTEST OK: 5/5\n' && exit 0
  printf 'SELFTEST FAILED\n'; exit 1
fi

[ "${PRISMA_DEPS_CHECK:-1}" = "1" ] || exit 0
cat >/dev/null
report
exit 0
