#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside". Loaded by pr-ready-tests.sh and claim-ready-gate-tests.sh, not run alone.

FAKE_REPO=acme/api
FAKE_NUMBER=7
FAKE_AUTHOR=octo
FAKE_BRANCH=feat/seven
FAKE_DEFAULT_BRANCH=main
FAKE_HEAD=aaaaaaa1111111111111111111111111111111111
OLDER_HEAD=fffffff9999999999999999999999999999999999
PUSHED=2026-01-10T10:00:00Z
CLAUDE_STARTED=2026-01-10T10:01:00Z
CLAUDE_FINISHED=2026-01-10T10:02:00Z
CLAUDE_DONE_BODY='**Claude finished @octo'"'"'s task in 40s**'
CLAUDE_WORKING_BODY='**Claude Code is working**'
CI_FINISHED=2026-01-10T10:00:30Z
ACTIVE_WORKFLOW='{"path":".github/workflows/ci.yml","state":"active"}'

install_fake_gh() {
  FAKE_GH_DIR="$1"
  cat > "$FAKE_GH_DIR/gh" <<'FAKE'
#!/bin/sh
for arg in "$@"; do case "$arg" in repos/*) endpoint=$arg ;; esac; done
while IFS='|' read -r pattern file; do
  [ -n "$pattern" ] || continue
  case "$endpoint" in $pattern) cat "$FAKE_GH_DIR/$file"; exit 0 ;; esac
done < "$FAKE_GH_DIR/routes"
echo "fake gh has no fixture for $endpoint" >&2
exit 1
FAKE
  chmod +x "$FAKE_GH_DIR/gh"
  export FAKE_GH_DIR
}

route() {
  route_count=$((route_count+1))
  printf '%s' "$2" > "$FAKE_GH_DIR/fixture-$route_count.json"
  printf '%s|fixture-%s.json\n' "$1" "$route_count" >> "$FAKE_GH_DIR/routes"
}

pr_json() {
  printf '{"number":%s,"state":"%s","user":{"login":"%s"},"head":{"ref":"%s","sha":"%s","repo":{"full_name":"%s"}},"base":{"ref":"%s","repo":{"default_branch":"%s"}},"mergeable_state":"%s","created_at":"%s","closed_at":%s,"merged_at":%s}' \
    "$1" "${2:-open}" "${3:-$FAKE_AUTHOR}" "$4" "$5" "$FAKE_REPO" "${10:-$FAKE_DEFAULT_BRANCH}" "$FAKE_DEFAULT_BRANCH" "${6:-clean}" "${7:-2026-01-10T09:00:00Z}" "${8:-null}" "${9:-null}"
}

push_json() { printf '{"activity_type":"%s","timestamp":"%s","after":"%s"}' "${3:-push}" "$1" "$2"; }
comment_json() { printf '{"user":{"login":"%s"},"created_at":"%s","updated_at":"%s","body":"%s"}' "$1" "$2" "$3" "$4"; }
review_json() { printf '{"user":{"login":"%s"},"submitted_at":"%s","state":"%s","commit_id":"%s"}' "$1" "$2" "${3:-COMMENTED}" "${4:-$FAKE_HEAD}"; }
check_json() { printf '{"name":"%s","app":{"slug":"ci"},"status":"%s","conclusion":%s,"started_at":"%s","completed_at":%s}' "$1" "$2" "$3" "$4" "$5"; }
status_json() { printf '{"id":%s,"context":"%s","state":"%s","created_at":"%s"}' "$1" "$2" "$3" "$4"; }

green_scenario() {
  PR="$(pr_json "$FAKE_NUMBER" open "$FAKE_AUTHOR" "$FAKE_BRANCH" "$FAKE_HEAD")"
  ACTIVITY="[$(push_json "$PUSHED" "$FAKE_HEAD")]"
  COMMENTS="[$(comment_json 'claude[bot]' "$CLAUDE_STARTED" "$CLAUDE_FINISHED" "$CLAUDE_DONE_BODY")]"
  REVIEWS='[]'
  CHECKS="{\"check_runs\":[$(check_json test completed '"success"' "$PUSHED" "\"$CI_FINISHED\"")]}"
  WORKFLOWS="{\"total_count\":1,\"workflows\":[$ACTIVE_WORKFLOW]}"
  STATUSES='[]'
  OPEN_PRS="[$PR]"
  CLOSED_PRS='[]'
  FILES='[{"filename":"src/app.ts"}]'
  BASE_PRS='[]'; BASE_BRANCH='{"protected":false}'; BASE_ACTIVITY='[]'
  unset TEST_REVIEWERS SECOND_PR BASE_REF OTHER_NUMBER SECOND_OTHER_NUMBER JUDGE_DIR GH_FOR_TEST
}

serve_second_pr() {
  second_branch=eight; second_head=bbbbbbb8888888888888888888888888888888888
  route "repos/$FAKE_REPO/pulls/$SECOND_PR" "$(pr_json "$SECOND_PR" open "$FAKE_AUTHOR" "$second_branch" "$second_head")"
  route "repos/$FAKE_REPO/activity?ref=refs%2Fheads%2F$second_branch&*" "[$(push_json "$PUSHED" "$second_head")]"
  route "repos/$FAKE_REPO/commits/$second_head/check-runs*" "{\"check_runs\":[$(check_json test completed '"success"' "$PUSHED" "\"$CI_FINISHED\"")]}"
  route "repos/$FAKE_REPO/issues/$SECOND_PR/comments*" '[]'
  route "repos/$FAKE_REPO/pulls/$SECOND_PR/reviews*" '[]'
  route "repos/$FAKE_REPO/pulls/$SECOND_PR/files*" '[{"filename":"docs/eight.md"}]'
}

serve() {
  : > "$FAKE_GH_DIR/routes"; route_count=0
  [ -z "${SECOND_PR:-}" ] || serve_second_pr
  if [ -n "${OTHER_NUMBER:-}" ]; then
    route "repos/$FAKE_REPO/pulls/$OTHER_NUMBER/files*" "$OTHER_FILES"
    route "repos/$FAKE_REPO/activity?ref=refs%2Fheads%2F$OTHER_BRANCH&*" "$OTHER_ACTIVITY"
  fi
  [ -z "${BASE_REF:-}" ] || route "repos/$FAKE_REPO/activity?ref=refs%2Fheads%2F$(printf '%s' "$BASE_REF" | sed 's,/,%2F,g')&*" "$BASE_ACTIVITY"
  [ -z "${SECOND_OTHER_NUMBER:-}" ] || route "repos/$FAKE_REPO/pulls/$SECOND_OTHER_NUMBER/files*" '[{"filename":"docs/other.md"}]'
  route "repos/$FAKE_REPO/pulls/$FAKE_NUMBER" "$PR"
  route "repos/$FAKE_REPO/pulls/$FAKE_NUMBER/files*" "$FILES"
  route "repos/$FAKE_REPO/activity*" "$ACTIVITY"
  route "repos/$FAKE_REPO/issues/$FAKE_NUMBER/comments*" "$COMMENTS"
  route "repos/$FAKE_REPO/pulls/$FAKE_NUMBER/reviews*" "$REVIEWS"
  route "repos/$FAKE_REPO/commits/*/check-runs*" "$CHECKS"
  route "repos/$FAKE_REPO/commits/*/statuses*" "$STATUSES"
  route "repos/$FAKE_REPO/actions/workflows*" "$WORKFLOWS"
  route "repos/$FAKE_REPO/pulls?state=open*" "$OPEN_PRS"
  route "repos/$FAKE_REPO/pulls?state=closed*" "$CLOSED_PRS"
  route "repos/$FAKE_REPO/pulls?state=all&head=*" "$BASE_PRS"
  route "repos/$FAKE_REPO/branches/*" "$BASE_BRANCH"
}

run_hook() {
  serve
  if [ "${TEST_REVIEWERS+set}" = set ]; then
    (cd "${JUDGE_DIR:-$FAKE_GH_DIR}" && PRISMA_PR_REVIEWERS="$TEST_REVIEWERS" PRISMA_GH="${GH_FOR_TEST:-$FAKE_GH_DIR/gh}" sh "$SELF" "$FAKE_REPO" "$FAKE_NUMBER" "$@" 2>&1)
  else
    (cd "${JUDGE_DIR:-$FAKE_GH_DIR}" && PRISMA_GH="${GH_FOR_TEST:-$FAKE_GH_DIR/gh}" sh "$SELF" "$FAKE_REPO" "$FAKE_NUMBER" "$@" 2>&1)
  fi
}

judge() {
  out=$(run_hook "$@"); rc=$?
  printf '%s %s' "$rc" "$(printf '%s\n' "$out" | head -1 | sed 's/:.*//')"
}

judge_says() { run_hook "$@" | grep -F -- "$SAYS" >/dev/null && echo says || echo silent; }

expect() {
  cases=$((cases+1))
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s, expected [%s] and got [%s]\n' "$1" "$3" "$2"; ok=0; fi
}
