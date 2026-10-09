#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside". Loaded by pr-ready.sh, not run alone.

FAKE_REPO=acme/api
FAKE_NUMBER=7
FAKE_AUTHOR=octo
FAKE_BRANCH=feat/seven
FAKE_HEAD=aaaaaaa1111111111111111111111111111111111
PUSHED=2026-01-10T10:00:00Z
CLAUDE_STARTED=2026-01-10T10:01:00Z
CLAUDE_FINISHED=2026-01-10T10:02:00Z
CLAUDE_DONE_BODY='**Claude finished @octo'"'"'s task in 40s**'
CLAUDE_WORKING_BODY='**Claude Code is working**'

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
  printf '{"number":%s,"state":"%s","user":{"login":"%s"},"head":{"ref":"%s","sha":"%s","repo":{"full_name":"%s"}},"mergeable_state":"%s","created_at":"%s","closed_at":%s,"merged_at":%s}' \
    "$1" "${2:-open}" "${3:-$FAKE_AUTHOR}" "$4" "$5" "$FAKE_REPO" "${6:-clean}" "${7:-2026-01-10T09:00:00Z}" "${8:-null}" "${9:-null}"
}

push_json() { printf '{"activity_type":"push","timestamp":"%s","after":"%s"}' "$1" "$2"; }
comment_json() { printf '{"user":{"login":"%s"},"created_at":"%s","updated_at":"%s","body":"%s"}' "$1" "$2" "$3" "$4"; }
review_json() { printf '{"user":{"login":"%s"},"submitted_at":"%s","state":"COMMENTED"}' "$1" "$2"; }
check_json() { printf '{"name":"%s","app":{"slug":"ci"},"status":"%s","conclusion":%s,"started_at":"%s","completed_at":%s}' "$1" "$2" "$3" "$4" "$5"; }
status_json() { printf '{"id":%s,"context":"%s","state":"%s","created_at":"%s"}' "$1" "$2" "$3" "$4"; }

green_scenario() {
  PR="$(pr_json "$FAKE_NUMBER" open "$FAKE_AUTHOR" "$FAKE_BRANCH" "$FAKE_HEAD")"
  ACTIVITY="[$(push_json "$PUSHED" "$FAKE_HEAD")]"
  COMMENTS="[$(comment_json 'claude[bot]' "$CLAUDE_STARTED" "$CLAUDE_FINISHED" "$CLAUDE_DONE_BODY")]"
  REVIEWS='[]'
  CHECKS='{"check_runs":[]}'
  STATUSES='[]'
  OPEN_PRS="[$PR]"
  CLOSED_PRS='[]'
  FILES='[{"filename":"src/app.ts"}]'
  unset TEST_REVIEWERS OTHER_NUMBER JUDGE_DIR GH_FOR_TEST
}

serve() {
  : > "$FAKE_GH_DIR/routes"; route_count=0
  if [ -n "${OTHER_NUMBER:-}" ]; then
    route "repos/$FAKE_REPO/pulls/$OTHER_NUMBER/files*" "$OTHER_FILES"
    route "repos/$FAKE_REPO/activity?ref=refs%2Fheads%2F$OTHER_BRANCH&*" "$OTHER_ACTIVITY"
  fi
  route "repos/$FAKE_REPO/pulls/$FAKE_NUMBER" "$PR"
  route "repos/$FAKE_REPO/pulls/$FAKE_NUMBER/files*" "$FILES"
  route "repos/$FAKE_REPO/activity*" "$ACTIVITY"
  route "repos/$FAKE_REPO/issues/$FAKE_NUMBER/comments*" "$COMMENTS"
  route "repos/$FAKE_REPO/pulls/$FAKE_NUMBER/reviews*" "$REVIEWS"
  route "repos/$FAKE_REPO/commits/*/check-runs*" "$CHECKS"
  route "repos/$FAKE_REPO/commits/*/statuses*" "$STATUSES"
  route "repos/$FAKE_REPO/pulls?state=open*" "$OPEN_PRS"
  route "repos/$FAKE_REPO/pulls?state=closed*" "$CLOSED_PRS"
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

selftest_ci() {
  green_scenario; STATUSES="[$(status_json 1 deploy pending 2026-01-10T10:00:05Z)]"
  expect "1 a pending status on the head is not ready" "$(judge)" "1 NOT READY"
  green_scenario; SAYS="no CI runs on this PR"
  expect "2 a head with no CI runs is ready and says there were none" "$(judge)$(judge_says)" "0 READYsays"
  green_scenario; CHECKS="{\"check_runs\":[$(check_json test completed '"failure"' "$PUSHED" '"2026-01-10T10:03:00Z"')]}"
  expect "3 a failed check run is not ready" "$(judge)" "1 NOT READY"
  green_scenario; CHECKS="{\"check_runs\":[$(check_json a completed '"success"' "$PUSHED" '"2026-01-10T10:03:00Z"'),$(check_json b completed '"neutral"' "$PUSHED" '"2026-01-10T10:03:00Z"'),$(check_json c completed '"skipped"' "$PUSHED" '"2026-01-10T10:03:00Z"')]}"
  STATUSES="[$(status_json 1 deploy pending 2026-01-10T10:00:05Z),$(status_json 2 deploy success 2026-01-10T10:04:00Z)]"
  expect "4 success, neutral and skipped runs and a status that turned green are ready" "$(judge)" "0 READY"
  green_scenario; CHECKS="{\"check_runs\":[$(check_json build in_progress null "$PUSHED" null)]}"
  expect "5 a check run still in progress is not ready" "$(judge)" "1 NOT READY"
}

selftest_reviewers() {
  green_scenario; COMMENTS="[$(comment_json 'claude[bot]' 2026-01-10T09:59:00Z 2026-01-10T09:59:40Z "$CLAUDE_DONE_BODY")]"; SAYS="before the last push"
  expect "6 a review that started before the last push is not ready and says so" "$(judge)$(judge_says)" "1 NOT READYsays"
  green_scenario; COMMENTS="[$(comment_json 'claude[bot]' "$CLAUDE_STARTED" "$CLAUDE_STARTED" "$CLAUDE_WORKING_BODY")]"
  expect "7 a review the bot is still writing is not ready" "$(judge)" "1 NOT READY"
  green_scenario; TEST_REVIEWERS="octo-reviewer"; COMMENTS='[]'; REVIEWS="[$(review_json octo-reviewer 2026-01-10T10:05:00Z)]"
  expect "8 a submitted review after the push counts for a configured reviewer" "$(judge)" "0 READY"
  green_scenario; TEST_REVIEWERS=""; COMMENTS='[]'
  expect "9 an empty reviewer list asks for no review" "$(judge)" "0 READY"
  green_scenario; COMMENTS='[]'; SAYS="claude[bot]"
  expect "10 a reviewer that never wrote is not ready and is named" "$(judge)$(judge_says)" "1 NOT READYsays"
  green_scenario; TEST_REVIEWERS="claude[bot],octo-reviewer"
  expect "11 every reviewer in a comma list is required" "$(judge)" "1 NOT READY"
}

selftest_at() {
  later_head=bbbbbbb2222222222222222222222222222222222
  green_scenario; PR="$(pr_json "$FAKE_NUMBER" open "$FAKE_AUTHOR" "$FAKE_BRANCH" "$later_head")"
  ACTIVITY="[$(push_json 2026-01-10T11:00:00Z "$later_head"),$(push_json "$PUSHED" "$FAKE_HEAD")]"
  expect "12 a push after --at is ignored, and the same PR now is not ready" "$(judge --at 2026-01-10T10:30:00Z)|$(judge)" "0 READY|1 NOT READY"
  green_scenario
  expect "13 a review that finished after --at did not exist yet" "$(judge --at 2026-01-10T10:01:30Z)" "1 NOT READY"
  green_scenario; STATUSES="[$(status_json 1 deploy pending 2026-01-10T10:00:05Z),$(status_json 2 deploy success 2026-01-10T10:04:00Z)]"
  expect "14 a status is read as it was, on both sides of the moment it turned green" "$(judge --at 2026-01-10T10:03:00Z)|$(judge --at 2026-01-10T10:05:00Z)" "1 NOT READY|0 READY"
  expect "15 an --at with a UTC offset is the same instant" "$(judge --at 2026-01-10T05:03:00-05:00)|$(judge --at 2026-01-10T05:05:00-05:00)" "1 NOT READY|0 READY"
  expect "16 an --at that is not ISO 8601 is a usage error" "$(judge --at yesterday)" "2 the time after --at is not ISO 8601"
}

commit_on_branch() {
  git -C "$CLONE" checkout -q -b "$1" main
  sed "s/^$2\$/$3/" "$CLONE/app.ts" > "$CLONE/app.ts.new" && mv "$CLONE/app.ts.new" "$CLONE/app.ts"
  git -C "$CLONE" -c user.name=t -c user.email=t commit -q -am "$1"
  git -C "$CLONE" rev-parse HEAD
}

build_clone() {
  CLONE="$T/clone"; mkdir -p "$CLONE"
  git -C "$CLONE" init -q && git -C "$CLONE" symbolic-ref HEAD refs/heads/main
  printf 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\n' > "$CLONE/app.ts"
  git -C "$CLONE" add app.ts && git -C "$CLONE" -c user.name=t -c user.email=t commit -q -m base
  git -C "$CLONE" remote add origin "https://github.com/$FAKE_REPO.git"
  SEVEN_HEAD=$(commit_on_branch seven two changed-by-seven)
  CLASHING_HEAD=$(commit_on_branch clashing two changed-by-another)
  APART_HEAD=$(commit_on_branch apart seven changed-far-away)
}

other_pr() {
  green_scenario
  PR="$(pr_json "$FAKE_NUMBER" open "$FAKE_AUTHOR" "$FAKE_BRANCH" "$SEVEN_HEAD")"
  ACTIVITY="[$(push_json "$PUSHED" "$SEVEN_HEAD")]"
  FILES='[{"filename":"app.ts"}]'
  OTHER_NUMBER=8; OTHER_BRANCH=other; OTHER_FILES="${2:-$FILES}"
  OTHER_ACTIVITY="[$(push_json "$PUSHED" "$1")]"
  OPEN_PRS="[$PR,$(pr_json 8 open "$FAKE_AUTHOR" "$OTHER_BRANCH" "$1")]"
  JUDGE_DIR="$CLONE"
}

selftest_conflicts() {
  green_scenario; PR="$(pr_json "$FAKE_NUMBER" open "$FAKE_AUTHOR" "$FAKE_BRANCH" "$FAKE_HEAD" dirty)"
  expect "17 a PR whose mergeable state is dirty is not ready" "$(judge)" "1 NOT READY"
  green_scenario; PR="$(pr_json "$FAKE_NUMBER" open "$FAKE_AUTHOR" "$FAKE_BRANCH" "$FAKE_HEAD" unknown)"
  expect "18 a mergeable state GitHub has not computed is not measured" "$(judge)" "3 NOT MEASURED"
  green_scenario; PR="$(pr_json "$FAKE_NUMBER" open "$FAKE_AUTHOR" "$FAKE_BRANCH" "$FAKE_HEAD" dirty)"; SAYS="not judged as of"
  expect "19 --at does not carry the mergeable state of today into the past, and says so" "$(judge --at 2026-01-10T10:05:00Z)$(judge_says --at 2026-01-10T10:05:00Z)" "0 READYsays"
  if ! git merge-tree --write-tree HEAD HEAD >/dev/null 2>&1; then
    for name in "20 another open PR of the author that conflicts is not ready" "21 another PR that shares a file and merges clean is ready" "22 another PR that touches no shared file is not compared" "23 a PR closed before --at is not compared"; do cases=$((cases+1)); printf 'SKIP %s, this git has no merge-tree --write-tree\n' "$name"; done
  else
    build_clone
    other_pr "$CLASHING_HEAD"; SAYS="finds a conflict in app.ts."
    expect "20 another open PR of the author that conflicts is not ready, and the file is named" "$(judge)$(judge_says)" "1 NOT READYsays"
    other_pr "$APART_HEAD"
    expect "21 another PR that shares a file and merges clean is ready" "$(judge)" "0 READY"
    other_pr "$CLASHING_HEAD" '[{"filename":"docs/other.md"}]'; SAYS="no other open PR of $FAKE_AUTHOR touches a file this one changes"
    expect "22 another PR that touches no shared file is not compared, and that is said" "$(judge)$(judge_says)" "0 READYsays"
    other_pr "$CLASHING_HEAD"; OPEN_PRS="[$PR]"; CLOSED_PRS="[$(pr_json 8 closed "$FAKE_AUTHOR" "$OTHER_BRANCH" "$CLASHING_HEAD" clean 2026-01-10T09:00:00Z '"2026-01-10T10:30:00Z"')]"
    expect "23 a PR closed before --at is not compared, and one closed after it is" "$(judge --at 2026-01-10T10:40:00Z)|$(judge --at 2026-01-10T10:05:00Z)" "0 READY|1 NOT READY"
  fi
  green_scenario; SAYS="not a clone of $FAKE_REPO"
  expect "24 outside a clone of the repo the check between PRs says it did not run" "$(judge_says)" "says"
}

selftest_unmeasured() {
  green_scenario; GH_FOR_TEST="$T/there-is-no-gh-here"
  expect "25 a gh that cannot run gives no verdict" "$(judge)" "3 NOT MEASURED"
  green_scenario; ACTIVITY="[$(push_json "$PUSHED" ccccccc3333333333333333333333333333333333)]"
  expect "26 a head whose push the activity log does not show yet is not measured" "$(judge)" "3 NOT MEASURED"
  green_scenario; STATUSES="[$(status_json 1 deploy pending 2026-01-10T10:00:05Z)]"; COMMENTS='this is not json'
  expect "27 a failure found before a read that fails is still reported" "$(judge)" "1 NOT READY"
  green_scenario; COMMENTS='[]'; PR="$(pr_json "$FAKE_NUMBER" closed "$FAKE_AUTHOR" "$FAKE_BRANCH" "$FAKE_HEAD" unknown 2026-01-10T09:00:00Z '"2026-01-10T11:00:00Z"' '"2026-01-10T11:00:00Z"')"
  expect "28 a merged PR has nothing left to wait for, and before its merge it was judged" "$(judge)|$(judge --at 2026-01-10T10:30:00Z)" "0 READY|1 NOT READY"
  green_scenario; PR="$(pr_json "$FAKE_NUMBER" closed "$FAKE_AUTHOR" "$FAKE_BRANCH" "$FAKE_HEAD" unknown 2026-01-10T09:00:00Z '"2026-01-10T11:00:00Z"')"
  expect "29 a PR closed without merging is not ready" "$(judge)" "1 NOT READY"
  green_scenario
  expect "30 a PR that did not exist yet at --at is not measured" "$(judge --at 2026-01-10T08:00:00Z)" "3 NOT MEASURED"
  green_scenario
  expect "37 --at with no time after it is a usage error, never a verdict about now" "$(judge --at)" "2 --at needs a time"
  green_scenario
  expect "38 an option the gate does not know is a usage error" "$(judge --since 2026-01-10T08:00:00Z)" "2 unknown option --since"
}

claude_review() { comment_json 'claude[bot]' "$1" "$2" "$CLAUDE_DONE_BODY"; }

history_stale_review() {
  green_scenario
  PR="$(pr_json "$FAKE_NUMBER" open "$FAKE_AUTHOR" "$FAKE_BRANCH" d000006 behind 2026-10-06T18:46:58Z)"
  ACTIVITY="[$(push_json 2026-10-08T16:05:05Z d000006),$(push_json 2026-10-08T13:39:19Z d000005),$(push_json 2026-10-07T19:09:22Z d000004),$(push_json 2026-10-06T19:06:35Z d000003),$(push_json 2026-10-06T18:59:11Z d000002),$(push_json 2026-10-06T18:46:01Z d000001)]"
  COMMENTS="[$(claude_review 2026-10-06T18:48:56Z 2026-10-06T18:49:35Z),$(claude_review 2026-10-07T19:37:25Z 2026-10-07T19:38:03Z),$(claude_review 2026-10-08T13:40:28Z 2026-10-08T13:41:03Z),$(claude_review 2026-10-08T16:05:31Z 2026-10-08T16:06:24Z)]"
}

history_fresh_review() {
  green_scenario
  PR="$(pr_json "$FAKE_NUMBER" open "$FAKE_AUTHOR" "$FAKE_BRANCH" e000003 clean 2026-10-06T18:47:30Z)"
  ACTIVITY="[$(push_json 2026-10-08T16:38:11Z e000003),$(push_json 2026-10-08T13:21:38Z e000002),$(push_json 2026-10-06T18:47:30Z e000001)]"
  COMMENTS="[$(claude_review 2026-10-08T13:22:20Z 2026-10-08T13:23:19Z),$(claude_review 2026-10-08T16:38:33Z 2026-10-08T16:39:27Z)]"
}

history_deploy_status() {
  green_scenario; TEST_REVIEWERS=""; COMMENTS='[]'
  PR="$(pr_json "$FAKE_NUMBER" closed "$FAKE_AUTHOR" "$FAKE_BRANCH" "$1" unknown "$2" "\"$6\"" "\"$6\"")"
  ACTIVITY="[$(push_json "$3" "$1")]"
  STATUSES="[$(status_json 2 deploy success "$5"),$(status_json 1 deploy pending "$4")]"
  CHECKS="{\"check_runs\":[$(check_json preview-comments completed '"success"' "$7" "\"$7\"")]}"
}

history_conflict_between_prs() {
  other_pr "$CLASHING_HEAD"
  PR="$(pr_json "$FAKE_NUMBER" open "$FAKE_AUTHOR" "$FAKE_BRANCH" "$SEVEN_HEAD" clean 2026-10-03T02:35:55Z)"
  ACTIVITY="[$(push_json 2026-10-03T13:37:14Z "$SEVEN_HEAD"),$(push_json 2026-10-03T02:06:10Z "$APART_HEAD")]"
  COMMENTS="[$(claude_review 2026-10-03T13:44:56Z 2026-10-03T13:45:31Z)]"
  OTHER_ACTIVITY="[$(push_json 2026-10-03T19:14:03Z "$CLASHING_HEAD"),$(push_json 2026-10-03T16:50:26Z "$APART_HEAD")]"
  OPEN_PRS="[$PR]"
  CLOSED_PRS="[$(pr_json 8 closed "$FAKE_AUTHOR" "$OTHER_BRANCH" "$CLASHING_HEAD" unknown 2026-10-03T16:50:38Z '"2026-10-05T13:54:31Z"' '"2026-10-05T13:54:31Z"')]"
}

selftest_history() {
  history_stale_review
  expect "31 history 2026-10-06, a review older than the merge of main pushed 22 seconds before the claim" "$(judge --at 2026-10-06T14:06:57-05:00)" "1 NOT READY"
  expect "32 history 2026-10-07, the same stale review a day later" "$(judge --at 2026-10-07T14:04:39-05:00)" "1 NOT READY"
  history_fresh_review
  expect "33 history 2026-10-08, a review that started after the last push is ready" "$(judge --at 2026-10-08T11:41:00-05:00)" "0 READY"
  history_deploy_status 1500002 2026-10-06T15:24:32Z 2026-10-06T15:30:43Z 2026-10-06T15:30:45Z 2026-10-06T15:33:05Z 2026-10-06T16:07:56Z 2026-10-06T15:33:08Z
  expect "34 history 2026-10-06, ready claimed while the deploy was pending, and ready once it turned green" "$(judge --at 2026-10-06T10:30:53-05:00)|$(judge --at 2026-10-06T10:33:10-05:00)" "1 NOT READY|0 READY"
  history_deploy_status 8420001 2026-10-06T19:47:23Z 2026-10-06T19:46:19Z 2026-10-06T19:46:21Z 2026-10-06T19:48:30Z 2026-10-06T19:54:36Z 2026-10-06T19:48:33Z
  expect "35 history 2026-10-06, ready claimed nine seconds before the deploy turned green" "$(judge --at 2026-10-06T14:48:21-05:00)|$(judge --at 2026-10-06T14:48:31-05:00)" "1 NOT READY|0 READY"
  if [ -n "${CLONE:-}" ]; then
    history_conflict_between_prs
    expect "36 history 2026-10-05, ready claimed while another PR of the author on the same file was open, and ready before it existed" "$(judge --at 2026-10-05T08:30:00-05:00)|$(judge --at 2026-10-03T09:00:00-05:00)" "1 NOT READY|0 READY"
  else
    cases=$((cases+1)); printf 'SKIP 36 history of a conflict between PRs, this git has no merge-tree --write-tree\n'
  fi
}

selftest() {
  SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  T=$(mktemp -d)
  install_fake_gh "$T"
  ok=1; cases=0; CLONE=""
  selftest_ci
  selftest_reviewers
  selftest_at
  selftest_conflicts
  selftest_unmeasured
  selftest_history
  rm -rf "$T"
  [ "$cases" = "$SELFTEST_CASES" ] || { printf 'FAIL %s cases ran and %s were expected\n' "$cases" "$SELFTEST_CASES"; ok=0; }
  [ "$ok" = "1" ] && printf 'SELFTEST OK: %s/%s\n' "$SELFTEST_CASES" "$SELFTEST_CASES" && return 0
  printf 'SELFTEST FAILED\n'; return 1
}
