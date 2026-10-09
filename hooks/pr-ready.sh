#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
if [ "${1:-}" = "--selftest" ]; then . "$(cd "$(dirname "$0")" && pwd)/selftest-env.sh"; fi

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
GH="${PRISMA_GH:-gh}"
JQ=$(command -v jq)
. "$HOOKS_DIR/pr-ready-codes.sh"
SHORT_SHA_WIDTH=7
NO_CUTOFF=999999999999
PAGE_SIZE=100
PUSH_EVENTS='"push","force_push","branch_creation"'
PASSING_CONCLUSIONS='"success","neutral","skipped"'
DEFAULT_REVIEWERS='claude[bot]'
REVIEWERS="${PRISMA_PR_REVIEWERS-$DEFAULT_REVIEWERS}"
FINISHING_BOT='claude[bot]'
FINISHED_MARKER='^[*_ ]*Claude finished @'
DECIDING_REVIEWS='"APPROVED","CHANGES_REQUESTED","DISMISSED"'
COUNTING_REVIEWS='"APPROVED","COMMENTED"'
LIST_SHAPE='type == "array"'
PULL_SHAPE='type == "object" and (.head | type) == "object"'
CHECK_RUNS_SHAPE='type == "object" and (.check_runs | type) == "array"'
TAB=$(printf '\t')
SELFTEST_CASES=50
USAGE='usage: pr-ready.sh <owner/repo> <number> [--at <ISO8601>] | --selftest'

TIME_JQ='def seconds: if . == null then null else
  capture("^(?<y>[0-9]{4})-(?<mo>[0-9]{2})-(?<d>[0-9]{2})T(?<h>[0-9]{2}):(?<mi>[0-9]{2}):(?<s>[0-9]{2})(?:[.][0-9]+)?(?<z>Z|[+-][0-9]{2}:?[0-9]{2})$") as $t
  | ($t.y | tonumber) as $y | ($t.mo | tonumber) as $m | (if $m <= 2 then $y - 1 else $y end) as $yy
  | (($yy * 365 + ($yy / 4 | floor) - ($yy / 100 | floor) + ($yy / 400 | floor)
      + ((153 * (if $m > 2 then $m - 3 else $m + 9 end) + 2) / 5 | floor) + ($t.d | tonumber)) * 86400
     + ($t.h | tonumber) * 3600 + ($t.mi | tonumber) * 60 + ($t.s | tonumber))
  - (if $t.z == "Z" then 0 else ([$t.z[1:3], $t.z[-2:]] | map(tonumber) | .[0] * 3600 + .[1] * 60) * (if $t.z[0:1] == "-" then -1 else 1 end) end)
  end;
def by_cutoff(f): select((f | seconds) as $t | $t == null or $t <= $cutoff);
def done_by_cutoff(f): (f | seconds) as $t | $t != null and $t <= $cutoff;'

CI_JQ='(([$runs[].check_runs[]] | map(by_cutoff(.started_at)) | group_by(.name + "/" + (.app.slug // ""))
    | map(max_by(.started_at | seconds) | {name, state: (if .status == "completed" and done_by_cutoff(.completed_at) then .conclusion else "pending" end)}))
  + ($statuses | add | map(by_cutoff(.created_at)) | group_by(.context)
    | map(max_by([(.created_at | seconds), .id]) | {name: .context, state}))) as $all
| if ($all | length) == 0 then "none" else
  ($all[] | [(if (.state | IN('"$PASSING_CONCLUSIONS"')) then "ok" elif (.state == "pending" or .state == "queued") then "pending" else "failing" end), .name, (.state // "unknown")] | @tsv) end'

REVIEW_JQ='($pushed | seconds) as $after_push
| [($reviews | add)[] | select(.user.login == $login and .submitted_at != null) | by_cutoff(.submitted_at)] as $formal
| ([$formal[] | select(.state | IN('"$DECIDING_REVIEWS"'))] | max_by(.submitted_at | seconds)) as $deciding
| ([$formal[] | select(.commit_id != $head and (.submitted_at | seconds) > $after_push)] | max_by(.submitted_at | seconds)) as $elsewhere
| [($comments | add)[] | select(.user.login == $login) | by_cutoff(.created_at)
    | {started: .created_at, done: (if $login != $bot then .created_at
        elif ((.body // "") | test($marker)) and done_by_cutoff(.updated_at) then .updated_at else null end)}]
  + [$formal[] | select(.commit_id == $head and (.state | IN('"$COUNTING_REVIEWS"'))) | {started: .submitted_at, done: .submitted_at}]
| (map(select((.started | seconds) > $after_push and .done != null)) | min_by(.done | seconds)) as $fresh
| (max_by(.started | seconds)) as $latest
| if $deciding.state == "CHANGES_REQUESTED" then "changes\t\($deciding.submitted_at)"
  elif $fresh then "fresh\t\($fresh.done)" elif $elsewhere then "elsewhere\t\($elsewhere.commit_id)" elif $latest == null then "none\t"
  elif ($latest.started | seconds) <= $after_push then "stale\t\($latest.started)" else "unfinished\t\($latest.started)" end'

unmeasurable() {
  finding unmeasured "$1"
  verdict
}

finding() { printf '%s\t%s\n' "$1" "$2" >> "$WORK/findings"; }

fetch() {
  if [ "${4:-}" = "all" ]; then "$GH" api --paginate "$2" > "$WORK/$1.json" 2>/dev/null
  else "$GH" api "$2" > "$WORK/$1.json" 2>/dev/null; fi || unmeasurable "gh could not read $2"
  "$JQ" -e . "$WORK/$1.json" >/dev/null 2>&1 || unmeasurable "gh returned something that is not JSON for $2"
  "$JQ" -se "length > 0 and all(.[]; $3)" "$WORK/$1.json" >/dev/null 2>&1 || unmeasurable "gh returned JSON of another shape for $2"
}

ask() { "$JQ" -r --argjson cutoff "$CUTOFF" "$TIME_JQ $1" "$WORK/$2.json"; }

judge_lifecycle() {
  born=$(ask 'select(done_by_cutoff(.created_at)) | .created_at' pull)
  [ -n "$born" ] || unmeasurable "the PR did not exist yet at that time"
  merged=$(ask 'select(done_by_cutoff(.merged_at)) | .merged_at' pull)
  [ -z "$merged" ] || { finding ok "merged at $merged, there is nothing left to wait for"; verdict; }
  closed=$(ask 'select(done_by_cutoff(.closed_at)) | .closed_at' pull)
  [ -z "$closed" ] || { finding fail "the PR was closed without merging at $closed"; verdict; }
}

read_head() {
  fetch pull "repos/$REPO/pulls/$NUMBER" "$PULL_SHAPE"
  judge_lifecycle
  head_repo=$(ask '.head.repo.full_name // empty' pull)
  head_ref=$(ask '.head.ref // empty' pull)
  [ -n "$head_repo" ] && [ -n "$head_ref" ] || unmeasurable "the PR names no head branch that can still be read"
  ref_param=$("$JQ" -rn --arg ref "refs/heads/$head_ref" '$ref | @uri')
  fetch activity "repos/$head_repo/activity?ref=$ref_param&per_page=$PAGE_SIZE" "$LIST_SHAPE" all
  last_push=$("$JQ" -rs --argjson cutoff "$CUTOFF" "$TIME_JQ"' [add[] | select(.activity_type | IN('"$PUSH_EVENTS"')) | by_cutoff(.timestamp)]
    | max_by(.timestamp | seconds) // empty | [.timestamp, .after] | @tsv' "$WORK/activity.json")
  [ -n "$last_push" ] || unmeasurable "the activity log of $head_ref shows no push before that time"
  pushed_at=${last_push%"$TAB"*}; head_sha=${last_push#*"$TAB"}
  [ -n "$AT" ] || [ "$head_sha" = "$(ask '.head.sha' pull)" ] || unmeasurable "the activity log does not show the push of the current head yet"
}

judge_ci() {
  fetch runs "repos/$REPO/commits/$head_sha/check-runs?filter=all&per_page=$PAGE_SIZE" "$CHECK_RUNS_SHAPE" all
  fetch statuses "repos/$REPO/commits/$head_sha/statuses?per_page=$PAGE_SIZE" "$LIST_SHAPE" all
  runs=$("$JQ" -rn --argjson cutoff "$CUTOFF" --slurpfile runs "$WORK/runs.json" --slurpfile statuses "$WORK/statuses.json" "$TIME_JQ $CI_JQ")
  short=$(printf "%.${SHORT_SHA_WIDTH}s" "$head_sha")
  [ "$runs" = "none" ] && { finding ok "ci: no CI runs on this PR, nothing to wait for on $short"; return; }
  printf '%s\n' "$runs" | while IFS="$TAB" read -r verdict name state; do
    case "$verdict" in
      ok) finding ok "ci: $name finished as $state on $short" ;;
      pending) finding fail "ci: $name has not finished on $short, it is $state" ;;
      *) finding fail "ci: $name finished as $state on $short" ;;
    esac
  done
}

judge_reviewer() {
  answer=$("$JQ" -rn --argjson cutoff "$CUTOFF" --arg pushed "$pushed_at" --arg head "$head_sha" --arg login "$1" --arg bot "$FINISHING_BOT" --arg marker "$FINISHED_MARKER" \
    --slurpfile comments "$WORK/comments.json" --slurpfile reviews "$WORK/reviews.json" "$TIME_JQ $REVIEW_JQ")
  when=${answer#*"$TAB"}
  case "$answer" in
    changes*) finding fail "reviewer $1: it requested changes at $when and has not approved since" ;;
    fresh*) finding ok "reviewer $1: reviewed at $when, after the last push at $pushed_at" ;;
    elsewhere*) finding fail "reviewer $1: its review after the last push was made on commit $when, not on the head" ;;
    stale*) finding fail "reviewer $1: its latest review started at $when, before the last push at $pushed_at, so it judged an older head" ;;
    unfinished*) finding fail "reviewer $1: the review it started at $when had not finished" ;;
    *) finding fail "reviewer $1: no comment or review from it on this PR after the last push at $pushed_at" ;;
  esac
}

judge_reviewers() {
  set -f
  logins=$(printf '%s' "$REVIEWERS" | tr ',' ' ')
  [ -n "$(printf '%s' "$logins" | tr -d ' ')" ] || { set +f; finding note "reviewers: none required, PRISMA_PR_REVIEWERS is empty"; return; }
  fetch comments "repos/$REPO/issues/$NUMBER/comments?per_page=$PAGE_SIZE" "$LIST_SHAPE" all
  fetch reviews "repos/$REPO/pulls/$NUMBER/reviews?per_page=$PAGE_SIZE" "$LIST_SHAPE" all
  for login in $logins; do judge_reviewer "$login"; done
  set +f
}

verdict() {
  if grep -q "^fail$TAB" "$WORK/findings"; then word="NOT READY"; code=$EXIT_NOT_READY
  elif grep -q "^unmeasured$TAB" "$WORK/findings"; then word="NOT MEASURED"; code=$EXIT_NOT_MEASURED
  else word="READY"; code=$EXIT_READY; fi
  printf '%s: %s#%s as of %s\n' "$word" "$REPO" "$NUMBER" "$AS_OF"
  while IFS="$TAB" read -r kind text; do
    case "$kind" in ok) label=pass ;; fail) label=FAIL ;; unmeasured) label="not measured" ;; *) label=note ;; esac
    printf '  %-12s %s\n' "$label" "$text"
  done < "$WORK/findings"
  exit "$code"
}

usage_error() { printf '%s\n%s\n' "$1" "$USAGE" >&2; exit "$EXIT_USAGE"; }

parse_arguments() {
  REPO="${1:-}"; NUMBER="${2:-}"; AT=""
  [ "$#" -ge 2 ] && shift 2
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --at) [ -n "${2:-}" ] || usage_error "--at needs a time"; AT=$2; shift 2 ;;
      *) usage_error "unknown option $1" ;;
    esac
  done
  case "$REPO" in */*) ;; *) printf '%s\n' "$USAGE" >&2; exit "$EXIT_USAGE" ;; esac
  case "$NUMBER" in ''|*[!0-9]*) printf '%s\n' "$USAGE" >&2; exit "$EXIT_USAGE" ;; esac
  [ -n "$JQ" ] || { echo "NOT MEASURED: jq is missing."; exit "$EXIT_NOT_MEASURED"; }
  AS_OF="${AT:-now}"; CUTOFF=$NO_CUTOFF
  [ -z "$AT" ] && return 0
  CUTOFF=$("$JQ" -rn --arg at "$AT" --argjson cutoff 0 "$TIME_JQ"' $at | seconds' 2>/dev/null)
  case "$CUTOFF" in ''|*[!0-9-]*) printf 'the time after --at is not ISO 8601: %s\n%s\n' "$AT" "$USAGE" >&2; exit "$EXIT_USAGE" ;; esac
}

. "$HOOKS_DIR/github-remote.sh"
. "$HOOKS_DIR/pr-ready-conflicts.sh"

if [ "${1:-}" = "--selftest" ]; then
  . "$HOOKS_DIR/pr-ready-tests.sh"
  selftest; exit $?
fi

parse_arguments "$@"
WORK=$(mktemp -d) || { echo "NOT MEASURED: no temporary directory could be created."; exit "$EXIT_NOT_MEASURED"; }
trap 'rm -rf "$WORK"' EXIT
: > "$WORK/findings"
read_head
judge_ci
judge_reviewers
judge_mergeable
judge_other_prs
verdict
