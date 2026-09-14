#!/bin/sh
# Prisma Harness. Documented in README.md, section "session-deps".

SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")
INSTALLED="${PRISMA_INSTALLED_PLUGINS:-$HOME/.claude/plugins/installed_plugins.json}"
DEP_NAME="mattpocock-skills"
DEP_INSTALL="/plugin install mattpocock-skills@claude-plugins-official"

dep_present() {
  [ -r "$INSTALLED" ] && grep -q "\"$DEP_NAME@" "$INSTALLED"
}

message() {
  cat <<MSG
PRISMA DEPENDENCY: the plugin $DEP_NAME is not installed in this Claude Code. Steps 1 and 2 of PRISMA invoke its skills (grilling, tdd, code-review, diagnosing-bugs). Install it once with $DEP_INSTALL, or run the same sequence by hand as METHOD.md describes: interview in rounds, tests first, a review in a fresh context, commit.
MSG
}

if [ "$1" = "--selftest" ]; then
  ok=1; T=$(mktemp -d)
  printf '{"plugins":{"other@x":[{}]}}' > "$T/absent.json"
  printf '{"plugins":{"mattpocock-skills@claude-plugins-official":[{}]}}' > "$T/present.json"
  out=$(printf '{}' | PRISMA_INSTALLED_PLUGINS="$T/absent.json" /bin/sh "$SELF")
  if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("not installed")' >/dev/null 2>&1; then printf 'PASS warns when the dependency is absent\n'; else printf 'FAIL absent: %s\n' "$out"; ok=0; fi
  out=$(printf '{}' | PRISMA_INSTALLED_PLUGINS="$T/present.json" /bin/sh "$SELF")
  if [ -z "$out" ]; then printf 'PASS quiet when the dependency is present\n'; else printf 'FAIL present: %s\n' "$out"; ok=0; fi
  out=$(printf '{}' | PRISMA_INSTALLED_PLUGINS="$T/missing.json" /bin/sh "$SELF")
  if printf '%s' "$out" | grep -q "not installed"; then printf 'PASS warns when no plugin registry exists at all\n'; else printf 'FAIL missing registry: %s\n' "$out"; ok=0; fi
  out=$(printf '{}' | PRISMA_INSTALLED_PLUGINS="$T/absent.json" PRISMA_DEPS_CHECK=0 /bin/sh "$SELF")
  if [ -z "$out" ]; then printf 'PASS PRISMA_DEPS_CHECK=0 switches it off\n'; else printf 'FAIL switch: %s\n' "$out"; ok=0; fi
  rm -rf "$T"
  [ "$ok" = "1" ] && printf 'SELFTEST OK: 4/4\n' && exit 0
  printf 'SELFTEST FAILED\n'; exit 1
fi

[ "${PRISMA_DEPS_CHECK:-1}" = "1" ] || exit 0
cat >/dev/null
dep_present && exit 0
command -v jq >/dev/null 2>&1 || exit 0
message | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'
exit 0
