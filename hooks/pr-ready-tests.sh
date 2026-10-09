#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside". Loaded by pr-ready.sh, not run alone.

. "$HOOKS_DIR/pr-ready-fixtures.sh"

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
  green_scenario; CHECKS="{\"check_runs\":[$(check_json lint completed '"failure"' "$PUSHED" '"2026-01-10T10:03:00Z"'),$(check_json test completed '"success"' "$PUSHED" '"2026-01-10T10:03:00Z"')]}"; SAYS="ci: lint finished as failure on aaaaaaa"
  expect "49 a run that is not the last line jq writes still reads whole" "$(judge)$(judge_says)" "1 NOT READYsays"
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
  formal_review CHANGES_REQUESTED; SAYS="requested changes at 2026-01-10T10:05:00Z"
  expect "42 a review that requests changes is not ready, and says so" "$(judge)$(judge_says)" "1 NOT READYsays"
  formal_review COMMENTED "$OLDER_HEAD"; SAYS="made on commit $OLDER_HEAD"
  expect "43 a review made on another commit than the head does not count, and says so" "$(judge)$(judge_says)" "1 NOT READYsays"
  formal_review DISMISSED
  expect "44 a dismissed review does not count" "$(judge)" "1 NOT READY"
  formal_review CHANGES_REQUESTED; REVIEWS="[$(review_json octo-reviewer 2026-01-10T10:04:00Z CHANGES_REQUESTED),$(review_json octo-reviewer 2026-01-10T10:06:00Z APPROVED)]"
  expect "45 an approval after a request for changes is ready" "$(judge)" "0 READY"
  formal_review CHANGES_REQUESTED; REVIEWS="[$(review_json octo-reviewer 2026-01-10T10:04:00Z CHANGES_REQUESTED),$(review_json octo-reviewer 2026-01-10T10:06:00Z COMMENTED)]"
  expect "46 a comment after a request for changes does not lift it" "$(judge)" "1 NOT READY"
}

formal_review() {
  green_scenario; TEST_REVIEWERS="octo-reviewer"; COMMENTS='[]'
  REVIEWS="[$(review_json octo-reviewer 2026-01-10T10:05:00Z "$1" "${2:-$FAKE_HEAD}")]"
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
    for name in "20 another open PR of the author that conflicts is not ready" "21 another PR that shares a file and merges clean is ready" "22 another PR that touches no shared file is not compared" "23 a PR closed before --at is not compared" "50 with --at, an open PR that is not the last line jq writes is still compared"; do cases=$((cases+1)); printf 'SKIP %s, this git has no merge-tree --write-tree\n' "$name"; done
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
    other_pr "$CLASHING_HEAD"; SECOND_OTHER_NUMBER=9; OPEN_PRS="[$PR,$(pr_json 8 open "$FAKE_AUTHOR" "$OTHER_BRANCH" "$CLASHING_HEAD"),$(pr_json 9 open "$FAKE_AUTHOR" nine "$APART_HEAD")]"
    expect "50 with --at, an open PR that is not the last line jq writes is still compared" "$(judge --at 2026-01-10T10:05:00Z)" "1 NOT READY"
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
  green_scenario; CHECKS='{"message":"Not Found"}'; SAYS="JSON of another shape"
  expect "47 check runs that come back as JSON of another shape are not measured, never a failed CI" "$(judge)$(judge_says)" "3 NOT MEASUREDsays"
  green_scenario; COMMENTS='{"message":"Not Found"}'
  expect "48 comments that come back as an object are not measured, never a missing review" "$(judge)" "3 NOT MEASURED"
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

selftest_merge_state() {
  green_scenario; PR=$(printf '%s' "$PR" | "$JQ" -c '.draft = true'); SAYS="the PR is a draft"
  expect "39 a PR in draft is not ready, and says it is a draft" "$(judge)$(judge_says)" "1 NOT READYsays"
  green_scenario; PR="$(pr_json "$FAKE_NUMBER" open "$FAKE_AUTHOR" "$FAKE_BRANCH" "$FAKE_HEAD" draft)"; SAYS="the PR is a draft"
  expect "40 a mergeable state of draft is a draft too" "$(judge)$(judge_says)" "1 NOT READYsays"
  green_scenario; PR="$(pr_json "$FAKE_NUMBER" open "$FAKE_AUTHOR" "$FAKE_BRANCH" "$FAKE_HEAD" blocked)"; SAYS="a required check or review is still missing"
  expect "41 a PR whose mergeable state is blocked is not ready, and says what blocks it" "$(judge)$(judge_says)" "1 NOT READYsays"
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
  selftest_merge_state
  rm -rf "$T"
  [ "$cases" = "$SELFTEST_CASES" ] || { printf 'FAIL %s cases ran and %s were expected\n' "$cases" "$SELFTEST_CASES"; ok=0; }
  [ "$ok" = "1" ] && printf 'SELFTEST OK: %s/%s\n' "$SELFTEST_CASES" "$SELFTEST_CASES" && return 0
  printf 'SELFTEST FAILED\n'; return 1
}
