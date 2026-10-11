#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside". Loaded by pr-ready.sh, not run alone.

MERGES_CLEAN=0
MERGE_CONFLICTS=1
BASE_MOVES='"push","force_push","branch_creation","pr_merge","merge_queue_merge"'
BRANCH_SHAPE='type == "object" and (.protected | type) == "boolean"'

OTHER_PRS_JQ='[add[]] | unique_by(.number)[]
| select(.user.login == $author and .number != $number) | by_cutoff(.created_at)
| select(.closed_at == null or ((.closed_at | seconds) > $cutoff))
| [.number, .head.ref, .head.sha, (.head.repo.full_name // "")] | @tsv'

MERGED_BASE_JQ='[add[] | select(.head.ref == $base)] as $prs
| if ([$prs[] | by_cutoff(.created_at) | select(.closed_at == null or ((.closed_at | seconds) > $cutoff))] | length) > 0 then empty
  else [$prs[] | select(done_by_cutoff(.merged_at))] | max_by(.merged_at | seconds) // empty | [.number, .head.sha, .base.ref, .merged_at] | @tsv end'

judge_mergeable() {
  [ -z "$AT" ] || { finding note "draft and conflicts: GitHub only knows the draft and mergeable state of now, so they are not judged as of $AT"; return; }
  [ "$(ask '.draft == true or .mergeable_state == "draft"' pull)" != "true" ] || { finding fail "draft: the PR is a draft, mark it ready for review first"; return; }
  state=$(ask '.mergeable_state // "unknown"' pull)
  case "$state" in
    dirty) finding fail "conflicts: GitHub says the PR conflicts with its base, mergeable state dirty" ;;
    blocked) finding fail "merge: GitHub says the PR is blocked, so a required check or review is still missing" ;;
    unknown) finding unmeasured "conflicts: GitHub has not computed the mergeable state yet, run it again in a minute" ;;
    *) finding ok "conflicts: GitHub says the PR merges into its base, mergeable state $state" ;;
  esac
}

inside_clone_of_repo() {
  wanted=$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')
  github_repos_of "$PWD" | grep -qxF "$wanted"
}

fetch_activity() {
  activity_ref=$("$JQ" -rn --arg ref "refs/heads/$3" '$ref | @uri')
  fetch "$1" "repos/$2/activity?ref=$activity_ref&per_page=$PAGE_SIZE" "$LIST_SHAPE" all
}

tip_at_cutoff() {
  "$JQ" -rs --argjson cutoff "$CUTOFF" "$TIME_JQ"' [add[] | select(.activity_type | IN('"$2"')) | by_cutoff(.timestamp)]
    | max_by(.timestamp | seconds) // empty | .after' "$WORK/$1.json"
}

read_other_head() {
  other_head="$3"
  [ -z "$AT" ] && return 0
  fetch_activity "activity-$1" "${4:-$REPO}" "$2"
  other_head=$(tip_at_cutoff "activity-$1" "$PUSH_EVENTS")
}

compare_with_other() {
  fetch "files-$1" "repos/$REPO/pulls/$1/files?per_page=$PAGE_SIZE" "$LIST_SHAPE" all
  shared=$("$JQ" -rn --slurpfile mine "$WORK/files.json" --slurpfile theirs "$WORK/files-$1.json" \
    '($theirs | add | map(.filename)) as $other | [$mine | add | .[].filename | select(. as $f | $other | index($f))] | join(", ")')
  [ -n "$shared" ] || return 0
  compared=$((compared+1))
  read_other_head "$@"
  [ -n "$other_head" ] || { finding unmeasured "conflicts with #$1: its head at that time could not be read"; return; }
  for sha in "$head_sha" "$other_head"; do
    git cat-file -e "$sha^{commit}" 2>/dev/null || { finding unmeasured "conflicts with #$1: commit $sha is not in this clone, git fetch and run it again"; return; }
  done
  clash=$(git merge-tree --write-tree --name-only --no-messages "$head_sha" "$other_head" 2>/dev/null); rc=$?
  case "$rc" in
    "$MERGES_CLEAN") finding ok "conflicts with #$1: both change $shared and git merge-tree merges them clean" ;;
    "$MERGE_CONFLICTS") finding fail "conflicts with #$1: it is open from the same author and git merge-tree finds a conflict in $(printf '%s\n' "$clash" | awk 'NR > 1 { printf "%s%s", separator, $0; separator = " " }')." ;;
    *) finding unmeasured "conflicts with #$1: git merge-tree --write-tree could not run, it needs git 2.38 or newer" ;;
  esac
}

judge_other_prs() {
  inside_clone_of_repo || { finding note "conflicts with other PRs: not checked, this directory is not a clone of $REPO"; return; }
  author=$(ask '.user.login // empty' pull)
  fetch open "repos/$REPO/pulls?state=open&per_page=$PAGE_SIZE" "$LIST_SHAPE" all
  if [ -n "$AT" ]; then fetch closed "repos/$REPO/pulls?state=closed&sort=updated&direction=desc&per_page=$PAGE_SIZE" "$LIST_SHAPE"
  else printf '[]' > "$WORK/closed.json"; fi
  others=$("$JQ" -rs --argjson cutoff "$CUTOFF" --arg author "$author" --argjson number "$NUMBER" "$TIME_JQ $OTHER_PRS_JQ" "$WORK/open.json" "$WORK/closed.json" | tr -d '\r')
  [ -n "$others" ] || { finding ok "conflicts with other PRs: $author had no other open PR"; return; }
  fetch files "repos/$REPO/pulls/$NUMBER/files?per_page=$PAGE_SIZE" "$LIST_SHAPE" all
  compared=0
  while IFS="$TAB" read -r other_number other_branch other_sha other_repo; do
    compare_with_other "$other_number" "$other_branch" "$other_sha" "$other_repo"
  done <<OTHERS
$others
OTHERS
  [ "$compared" -gt 0 ] || finding ok "conflicts with other PRs: no other open PR of $author touches a file this one changes"
}

judge_base() {
  base=$(ask '.base.ref // empty' pull); default_branch=$(ask '.base.repo.default_branch // empty' pull)
  [ -n "$base" ] && [ "$base" != "$default_branch" ] || return 0
  head_param=$("$JQ" -rn --arg head "${REPO%%/*}:$base" '$head | @uri')
  fetch base-prs "repos/$REPO/pulls?state=all&head=$head_param&per_page=$PAGE_SIZE" "$LIST_SHAPE" all
  carrier_line=$("$JQ" -rs --argjson cutoff "$CUTOFF" --arg base "$base" "$TIME_JQ $MERGED_BASE_JQ" "$WORK/base-prs.json" | tr -d '\r')
  [ -n "$carrier_line" ] || { finding ok "base: $base is not the head of a PR that already merged"; return; }
  IFS="$TAB" read -r carrier carried into carried_at <<CARRIER
$carrier_line
CARRIER
  branch_param=$("$JQ" -rn --arg ref "$base" '$ref | @uri')
  fetch base-branch "repos/$REPO/branches/$branch_param" "$BRANCH_SHAPE"
  [ "$(ask '.protected' base-branch)" != "true" ] || { finding ok "base: $base is protected, so it is a long-lived branch"; return; }
  fetch_activity base-activity "$REPO" "$base"
  tip=$(tip_at_cutoff base-activity "$BASE_MOVES")
  [ -n "$tip" ] || { finding unmeasured "base: the activity log of $base shows no push before that time"; return; }
  [ "$tip" = "$carried" ] || { finding ok "base: $base moved after #$carrier merged at $carried_at"; return; }
  finding fail "base: $base points at $(printf "%.${SHORT_SHA_WIDTH}s" "$tip"), the same commit #$carrier already carried into $into at $carried_at. If $base is a work branch, merging here never reaches $default_branch, so change the base to $default_branch first. If it is a long-lived branch, say so when you claim this PR ready"
}
