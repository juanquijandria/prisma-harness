#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside". Loaded by pr-ready.sh, not run alone.

MERGES_CLEAN=0
MERGE_CONFLICTS=1

OTHER_PRS_JQ='[add[]] | unique_by(.number)[]
| select(.user.login == $author and .number != $number) | by_cutoff(.created_at)
| select(.closed_at == null or ((.closed_at | seconds) > $cutoff))
| [.number, .head.ref, .head.sha, (.head.repo.full_name // "")] | @tsv'

judge_mergeable() {
  [ -z "$AT" ] || { finding note "conflicts: GitHub only knows the mergeable state of now, so it is not judged as of $AT"; return; }
  state=$(ask '.mergeable_state // "unknown"' pull)
  case "$state" in
    dirty) finding fail "conflicts: GitHub says the PR conflicts with its base, mergeable state dirty" ;;
    unknown) finding unmeasured "conflicts: GitHub has not computed the mergeable state yet, run it again in a minute" ;;
    *) finding ok "conflicts: GitHub says the PR merges into its base, mergeable state $state" ;;
  esac
}

inside_clone_of_repo() {
  wanted=$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')
  github_repos_of "$PWD" | grep -qxF "$wanted"
}

read_other_head() {
  other_head="$3"
  [ -z "$AT" ] && return 0
  other_ref=$("$JQ" -rn --arg ref "refs/heads/$2" '$ref | @uri')
  fetch "activity-$1" "repos/${4:-$REPO}/activity?ref=$other_ref&per_page=$PAGE_SIZE" all
  other_head=$("$JQ" -rs --argjson cutoff "$CUTOFF" "$TIME_JQ"' [add[] | select(.activity_type | IN('"$PUSH_EVENTS"')) | by_cutoff(.timestamp)]
    | max_by(.timestamp | seconds) // empty | .after' "$WORK/activity-$1.json")
}

compare_with_other() {
  fetch "files-$1" "repos/$REPO/pulls/$1/files?per_page=$PAGE_SIZE" all
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
  fetch open "repos/$REPO/pulls?state=open&per_page=$PAGE_SIZE" all
  if [ -n "$AT" ]; then fetch closed "repos/$REPO/pulls?state=closed&sort=updated&direction=desc&per_page=$PAGE_SIZE"
  else printf '[]' > "$WORK/closed.json"; fi
  others=$("$JQ" -rs --argjson cutoff "$CUTOFF" --arg author "$author" --argjson number "$NUMBER" "$TIME_JQ $OTHER_PRS_JQ" "$WORK/open.json" "$WORK/closed.json")
  [ -n "$others" ] || { finding ok "conflicts with other PRs: $author had no other open PR"; return; }
  fetch files "repos/$REPO/pulls/$NUMBER/files?per_page=$PAGE_SIZE" all
  compared=0
  while IFS="$TAB" read -r other_number other_branch other_sha other_repo; do
    compare_with_other "$other_number" "$other_branch" "$other_sha" "$other_repo"
  done <<OTHERS
$others
OTHERS
  [ "$compared" -gt 0 ] || finding ok "conflicts with other PRs: no other open PR of $author touches a file this one changes"
}
