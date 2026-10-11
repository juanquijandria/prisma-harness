# Prisma Harness. Documented in README.md, section "What is inside". Loaded by shell-traps-tests.sh, not run alone.

run_without_lsof() {
  payload_in "$1" "$2" | PRISMA_LSOF="$MISSING_TOOL" SHELL="$ZSH" sh "$SELF" >/dev/null 2>&1
  echo "$?"
}

run_without_pgrep() {
  payload_in "$1" "$2" | PRISMA_PGREP="$MISSING_TOOL" SHELL="$ZSH" sh "$SELF" >/dev/null 2>&1
  echo "$?"
}

selftest_kills() {
  other_dir=$(mktemp -d); own_dir=$(mktemp -d)
  ln -s "$(command -v sleep)" "$other_dir/$KILL_PROBE_NAME"
  (cd "$other_dir" && exec "./$KILL_PROBE_NAME" "$KILL_PROBE_SECONDS") &
  foreign_pid=$!
  (cd "$other_dir" && exec "$KILL_PYTHON" -c "$KILL_SLEEPER" "$KILL_PROBE_SECONDS" "$REDIRECTION") &
  redirection_pid=$!
  sleep "$PROBE_START_SECONDS"
  expect_measured "36 pkill whose pattern reaches a process in another folder blocks" "$(run_payload_in "pkill -f $KILL_PROBE_NAME" "$own_dir")" 2
  expect_measured "37 killall of a name that runs in another folder blocks" "$(run_payload_in "killall $KILL_PROBE_NAME" "$own_dir")" 2
  expect_measured "72 a killall of another long name that shares the first 15 letters passes" "$(run_payload_in "killall $KILL_PROBE_NAME-other" "$own_dir")" 0
  expect_measured "38 the same pkill from the folder that owns the process passes" "$(run_payload_in "pkill -f $KILL_PROBE_NAME" "$other_dir")" 0
  expect_measured "39 a pkill that matches nothing passes" "$(run_payload_in "pkill -f no-such-process-$KILL_PROBE_SECONDS" "$own_dir")" 0
  expect "40 a pkill only mentioned inside quotes passes" "$(run_payload_in "echo \"pkill -f $KILL_PROBE_NAME\"" "$own_dir")" 0
  expect_measured "41 the escape lets a foreign pkill through" "$(run_payload_in "$ESCAPE pkill -f $KILL_PROBE_NAME" "$own_dir")" 0
  foreign_block=$(run_payload_in_stderr "pkill -f $KILL_PROBE_NAME" "$own_dir")
  expect_measured "42 the block names the foreign folder" "$(printf '%s' "$foreign_block" | grep -c "$other_dir")" 1
  expect_measured "67 the block says the processes run in another folder, never that another session started them" "$(printf '%s' "$foreign_block" | grep -c 'another session') $(printf '%s' "$foreign_block" | grep -c 'another folder')" "0 1"
  expect_measured "43 a foreign pkill after an own pkill on the same line still blocks" "$(run_payload_in "pkill -x $KILL_OWN_NAME; pkill -f $KILL_PROBE_NAME" "$own_dir")" 2
  expect_measured "68 a pkill with a redirection still blocks a process in another folder" "$(run_payload_in "pkill -f $KILL_PROBE_NAME $REDIRECTION" "$own_dir") $(run_payload_in "pkill -f $KILL_PROBE_NAME > out.log" "$own_dir") $(run_payload_in "killall $KILL_OWN_NAME $REDIRECTION; pkill -f $KILL_PROBE_NAME 2>&1" "$own_dir")" "2 2 2"
  expect_measured "69 a redirection is not a pattern, so it never reaches a process whose command line holds it" "$(run_payload_in "pkill -f no-such-process-$KILL_PROBE_SECONDS $REDIRECTION" "$own_dir")" 0
  expect_measured "74 a redirection glued to the pattern is not part of it" "$(run_payload_in "pkill -f $KILL_PROBE_NAME>/dev/null" "$own_dir")" 2
  expect_measured "75 a quoted pattern that holds a > stays a pattern" "$(run_payload_in "pkill -f '$KILL_PROBE_SECONDS $REDIRECTION'" "$own_dir")" 2
  expect_measured "80 a pattern that is only a quoted > is a pattern, so it still reaches a process whose command line holds it" "$(run_payload_in "pkill -f '>'" "$own_dir")" 2
  expect_measured "81 an escaped > is a pattern too" "$(run_payload_in "pkill -f \\>" "$own_dir")" 2
  expect_where_proc "70 without lsof the folder is read from /proc, so a foreign pkill still blocks" "$(run_without_lsof "pkill -f $KILL_PROBE_NAME" "$own_dir")" 2
  : > "$PRISMA_RECEIPT_FILE"
  expect_without_proc "71 a process whose folder neither lsof nor /proc can read is let through and recorded as not measured" "$(run_without_lsof "pkill -f $KILL_PROBE_NAME" "$own_dir") $(grep -c "	$GATE_NAME	.*	not-measured$" "$PRISMA_RECEIPT_FILE")" "0 1"
  expect_measured "44 the flags of one pkill do not leak into the next" "$(run_payload_in "pkill -f $KILL_OWN_NAME; pkill -9 -f no-such-process-$KILL_PROBE_SECONDS" "$own_dir")" 0
  : > "$PRISMA_RECEIPT_FILE"
  expect "73 where pgrep is missing a pkill is let through and recorded as not measured" "$(run_without_pgrep "pkill -f $KILL_PROBE_NAME" "$own_dir") $(grep -c "	$GATE_NAME	.*	not-measured$" "$PRISMA_RECEIPT_FILE")" "0 1"
  receipt="$PRISMA_RECEIPT_FILE"; : > "$receipt"
  printf '{"tool_name":"Bash","tool_input":{"command":"pkill -f %s"}}' "$KILL_PROBE_NAME" | SHELL="$ZSH" sh "$SELF" >/dev/null 2>&1
  expect "45 a pkill without a session folder is let through and recorded as not measured" "$? $(grep -c "	$GATE_NAME	.*	not-measured$" "$receipt")" "0 1"
  kill "$foreign_pid" "$redirection_pid" 2>/dev/null
  wait "$foreign_pid" "$redirection_pid" 2>/dev/null
  rm -rf "$other_dir" "$own_dir"
}

receipt_states() {
  states=$(grep "	$GATE_NAME	" "$PRISMA_RECEIPT_FILE" 2>/dev/null | awk -F '\t' '{ print $NF }' | tr '\n' ' ')
  printf '%s' "${states% }"
  [ -n "$states" ] || printf 'none'
}

run_with_pgrep() {
  : > "$PRISMA_RECEIPT_FILE"; : > "$pgrep_args"
  payload_in "$1" "$2" | FAKE_PGREP_PIDS="$3" FAKE_PGREP_ARGS="$pgrep_args" PRISMA_PGREP="$fake_pgrep" PRISMA_LSOF="${4:-}" PRISMA_REQUIRED_WRAPPERS="${5:-$DEFAULT_WRAPPERS}" SHELL="$ZSH" sh "$SELF" >/dev/null 2>&1
  printf '%s %s' "$?" "$(receipt_states)"
}

pgrep_received() { cat "$pgrep_args"; }

expect_unprivileged() {
  if [ "$(id -u)" = "0" ]; then skip_case "$1" "root reads the folder of every process"; else expect_measured "$@"; fi
}

kill_probe_constants() {
  VANISHED_PID=2147483646
  UNREADABLE_PID=1
  UNREADABLE_LSOF_FOLDER='/proc/1/cwd (readlink: Permission denied)'
  CROWDED_PRIVATE_USE='import sys; sys.stdout.buffer.write(("pkill -f %s" % "".join(map(chr, range(0xE001, 0xF900)))).encode("utf-8"))'
  PRIVATE_FIRST=$(printf '\356\200\200')
  PRIVATE_SECOND=$(printf '\356\200\201')
}

selftest_kill_probes() {
  kill_probe_constants
  probe_bin=$(mktemp -d); fake_pgrep="$probe_bin/pgrep"; pgrep_args="$probe_bin/pgrep-args"
  fake_lsof="$probe_bin/lsof"
  printf '#!/bin/sh\nprintf "p%%s\\nfcwd\\nn%%s\\n" "%s" "%s"\n' "$UNREADABLE_PID" "$UNREADABLE_LSOF_FOLDER" > "$fake_lsof"; chmod +x "$fake_lsof"
  printf '#!/bin/sh\nprintf "%%s" "$*" > "$FAKE_PGREP_ARGS"\n[ -n "$FAKE_PGREP_PIDS" ] || exit 1\nprintf "%%s\\n" $FAKE_PGREP_PIDS\n' > "$fake_pgrep"; chmod +x "$fake_pgrep"
  session_dir=$(mktemp -d); foreign_dir=$(mktemp -d); shifted=""
  (cd "$session_dir" && exec sleep "$KILL_PROBE_SECONDS") &
  own_sleeper=$!
  (cd "$foreign_dir" && exec sleep "$KILL_PROBE_SECONDS") &
  foreign_sleeper=$!
  sleep "$PROBE_START_SECONDS"
  expect_measured "83 a quoted < is a pattern too, so the pkill is measured" "$(run_with_pgrep "pkill -f '<'" "$session_dir" "$own_sleeper") $(pgrep_received)" "0 none -f <"
  expect_measured "87 a block with an unreadable process next to a foreign one leaves one line, blocked" "$(run_with_pgrep "pkill -f $KILL_PROBE_NAME" "$session_dir" "$foreign_sleeper $UNREADABLE_PID")" "2 blocked"
  run_with_pgrep "pkill -f '<$PRIVATE_FIRST>$PRIVATE_SECOND'" "$probe_bin" "" >/dev/null
  expect_measured "84 a private use character already in the command reaches pgrep as written" "$(pgrep_received)" "-f <$PRIVATE_FIRST>$PRIVATE_SECOND"
  expect_measured "85 a process that ended before its folder was read is not a gap in the measure" "$(run_with_pgrep "pkill -f $KILL_PROBE_NAME" "$probe_bin" "$VANISHED_PID" "$MISSING_TOOL")" "0 none"
  expect_unprivileged "86 a live process whose folder cannot be read is still a gap in the measure" "$(run_with_pgrep "pkill -f $KILL_PROBE_NAME" "$probe_bin" "$UNREADABLE_PID" "$MISSING_TOOL")" "0 not-measured"
  expect_unprivileged "91 an lsof line that is not a folder is a gap in the measure, never a foreign folder" "$(run_with_pgrep "pkill -f $KILL_PROBE_NAME" "$probe_bin" "$UNREADABLE_PID" "$fake_lsof")" "0 not-measured"
  expect_measured "92 a block from another trap on the line of an unmeasured pkill leaves one line, blocked" "$(run_with_pgrep "pkill -f $KILL_PROBE_NAME; $MISSING_WRAPPER 5 ls" "$session_dir" "$UNREADABLE_PID" "$MISSING_TOOL" "$MISSING_WRAPPER")" "2 blocked"
  expect_measured "93 a rewrite on the line of an unmeasured pkill lets it through and says both" "$(run_with_pgrep "pkill -f $KILL_PROBE_NAME; grep -rn --include=*.md foo ." "$session_dir" "$UNREADABLE_PID" "$MISSING_TOOL")" "0 rewritten not-measured"
  body_only=$(printf "cat <<'EOF'\npkill -f %s\nEOF" "$KILL_PROBE_NAME")
  expect_measured "94 a pkill written inside a heredoc body is data and passes" "$(run_with_pgrep "$body_only" "$session_dir" "$foreign_sleeper")" "0 none"
  after_body=$(printf '%s\npkill -f %s' "$body_only" "$KILL_PROBE_NAME")
  after_herestring=$(printf "cat <<<'x'\npkill -f %s" "$KILL_PROBE_NAME")
  after_quoted=$(printf "echo '<<EOF'\npkill -f %s" "$KILL_PROBE_NAME")
  expect_measured "95 a pkill after the body, after a herestring or after a quoted << still blocks" "$(run_with_pgrep "$after_body" "$session_dir" "$foreign_sleeper"), $(run_with_pgrep "$after_herestring" "$session_dir" "$foreign_sleeper"), $(run_with_pgrep "$after_quoted" "$session_dir" "$foreign_sleeper")" "2 blocked, 2 blocked, 2 blocked"
  after_comment=$(printf 'pkill -f %s # a note\npkill -f %s' "$KILL_OWN_NAME" "$KILL_PROBE_NAME")
  run_with_pgrep "$after_comment" "$session_dir" "" >/dev/null
  expect_measured "96 the pattern of a pkill on the line after a comment still reaches pgrep" "$(pgrep_received)" "-f $KILL_PROBE_NAME"
  for hidden in 'echo $((1<<2))' '(( n = 1<<3 ))' 'x=`cat <<E`'; do
    run_with_pgrep "$(printf '%s\npkill -f %s' "$hidden" "$KILL_PROBE_NAME")" "$session_dir" "" >/dev/null
    shifted="$shifted$(pgrep_received),"
  done
  expect_measured "97 a << inside arithmetic or backticks opens no heredoc, so the pkill below it is read" "$shifted" "-f $KILL_PROBE_NAME,-f $KILL_PROBE_NAME,-f $KILL_PROBE_NAME,"
  expect_measured "88 a command that leaves no private use character free is let through and recorded as not measured" "$(run_with_pgrep "$("$KILL_PYTHON" -c "$CROWDED_PRIVATE_USE")" "$session_dir" "")" "0 not-measured"
  kill "$own_sleeper" "$foreign_sleeper" 2>/dev/null
  wait "$own_sleeper" "$foreign_sleeper" 2>/dev/null
  rm -rf "$probe_bin" "$session_dir" "$foreign_dir"
}
