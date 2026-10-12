# Prisma Harness. Documented in README.md, section "What is inside". Loaded by command-invokes.sh, not run alone.
ok=1
case_check() {
  if [ "$2" = "$3" ]; then echo "PASS case $1"; else echo "FAIL case $1, expected [$3] and got [$2]"; ok=0; fi
}
PATHS="notes/Meeting 1 of 5
archive/x"
balanced='mv "notes/Meeting 1 of 5" archive/x'
heredoc="mv \"notes/Meeting 1 of 5\" archive/x && cat >> log.md <<'EOF'
a quote from O'Reilly
EOF"
second_mv="cat >> log.md <<'EOF'
a quote from O'Reilly
EOF
mv \"notes/Meeting 1 of 5\" archive/x"
case_check "1 balanced quotes" "$(printf '%s' "$balanced" | "$SELF" --arguments mv)" "$PATHS"
case_check "2 APOSTROPHE in a heredoc, the origin is not lost" "$(printf '%s' "$heredoc" | "$SELF" --arguments mv)" "$PATHS"
case_check "3 APOSTROPHE before the mv, still detected" "$(printf '%s' "$second_mv" | "$SELF" --arguments mv)" "$PATHS"
case_check "4 a quoted command is not an invocation" "$(printf '%s' 'echo "mv inbox/a archive/x"' | "$SELF" --arguments mv; echo "exit=$?")" "exit=0"
case_check "5 a real separator splits the command" "$(printf '%s' 'ls; mv "notes/Meeting 1 of 5" archive/x' | "$SELF" --arguments mv)" "$PATHS"
case_check "6 env assignment before the program" "$(printf '%s' 'IMAGES="3 informative, 0 reference" mv "notes/Meeting 1 of 5" archive/x' | "$SELF" --arguments mv)" "$PATHS"
case_check "7 a separator inside quotes does not split" "$(printf '%s' 'git commit -m "do not touch; mv a b"' | "$SELF" --arguments mv; echo "exit=$?")" "exit=0"
case_check "8 subcommand after flags that take a value" "$(printf '%s' 'git -C /tmp push origin main' | "$SELF" git push)" "git -C /tmp push origin main"
case_check "17 a repository flag of another program takes its value too" "$(printf '%s' 'gh -R owner/name pr create --fill' | "$SELF" gh pr)" "gh -R owner/name pr create --fill"
case_check "18 the long form of that flag as well" "$(printf '%s' 'gh --repo owner/name pr create --fill' | "$SELF" gh pr)" "gh --repo owner/name pr create --fill"
case_check "9 trailing comment" "$(printf '%s' 'mv "notes/Meeting 1 of 5" archive/x # a note' | "$SELF" --arguments mv)" "$PATHS"
case_check "10 program absent" "$(printf '%s' 'ls -la' | "$SELF" --arguments mv; echo "exit=$?")" "exit=0"
apostrophes_around="cat >/dev/null <<'A'
x'y
A
mv \"notes/Meeting 1 of 5\" archive/x
cat >/dev/null <<B
close'
unmatched'
B"
case_check "11 APOSTROPHES enclosing the mv, still detected" "$(printf '%s' "$apostrophes_around" | "$SELF" --arguments mv)" "$PATHS"
case_check "12 REDIRECTION before the program, still detected" "$(printf '%s' '>/dev/null mv "notes/Meeting 1 of 5" archive/x' | "$SELF" --arguments mv)" "$PATHS"
case_check "13 a redirection target is not a program" "$(printf '%s' 'echo hola > mv' | "$SELF" --arguments mv; echo "exit=$?")" "exit=0"
case_check "14 redirection after the arguments" "$(printf '%s' 'mv "notes/Meeting 1 of 5" archive/x >/dev/null' | "$SELF" --arguments mv)" "$PATHS"
stray_double="cat >> log.md <<'EOF'
the table says 5\" wide
EOF
mv \"notes/Meeting 1 of 5\" archive/x"
stray_single="cat >> log.md <<'EOF'
a quote from O'Reilly
EOF
mv 'notes/Meeting 1 of 5' archive/x"
case_contains() {
  case "$2" in *"$3"*) echo "PASS case $1";; *) echo "FAIL case $1, expected it to contain [$3] and got [$2]"; ok=0;; esac
}
case_contains "15 stray DOUBLE QUOTE with the path in double quotes" "$(printf '%s' "$stray_double" | "$SELF" --arguments mv)" "$PATHS"
case_contains "16 stray APOSTROPHE with the path in single quotes" "$(printf '%s' "$stray_single" | "$SELF" --arguments mv)" "$PATHS"
case_check "19 ARITHMETIC glued to a semicolon does not hide the push" "$(printf '%s' 'n=$((n+1)); git push origin main' | "$SELF" git push)" "git push origin main"
case_check "20 SUBSTITUTION glued to a semicolon does not hide the push" "$(printf '%s' 'x=$(date); git push origin main' | "$SELF" git push)" "git push origin main"
case_check "21 SUBSTITUTION glued to a pipe does not hide the push" "$(printf '%s' 'echo $(date)|git push origin main' | "$SELF" git push)" "git push origin main"
case_check "22 REDIRECTION glued to a separator skips its target" "$(printf '%s' 'ls;>/dev/null git push origin main' | "$SELF" git push)" "git push origin main"
case_check "23 a quoted push after the arithmetic is not an invocation" "$(printf '%s' 'n=$((n+1)); echo "git push origin main"' | "$SELF" git push; echo "exit=$?")" "exit=0"
case_check "24 an append of both streams is a redirection and not a separator" "$(printf '%s' 'ls &>>log git push origin main' | "$SELF" git push; echo "exit=$?")" "exit=0"
case_check "25 a STREAM NUMBER glued to a redirection is not an argument" "$(printf '%s' 'git push origin main 2>&1 | tail -8' | "$SELF" git push)" "git push origin main"
case_check "26 a number SEPARATED from the redirection is an argument" "$(printf '%s' 'git push origin main 2 >log' | "$SELF" git push)" "git push origin main 2"
case_check "27 a QUOTED number before a redirection is an argument" "$(printf '%s' 'git push origin main "2">log' | "$SELF" git push)" "git push origin main 2"
apostrophe_before_stream="cat >> log.md <<'EOF'
the review's own fixture
EOF
git push origin main 2>&1"
case_check "28 APOSTROPHE in a heredoc does not keep the stream number" "$(printf '%s' "$apostrophe_before_stream" | "$SELF" git push)" "git push origin main"
case_check "29 an APPEND and a stream number one are redirections too" "$(printf '%s' 'git push origin main 2>>err 1>out' | "$SELF" git push)" "git push origin main"
case_check "30 a push on the line after a COMMENT is still seen" "$(printf 'echo a # n\ngit push origin main' | "$SELF" git push)" "git push origin main"
case_check "31 a COMMENT on the last line invents no command" "$(printf 'ls # git push origin main' | "$SELF" git push; echo "exit=$?")" "exit=0"
case_check "32 a COMMENT after the push lends it no words from the next line" "$(printf 'git push origin main # n\necho a' | "$SELF" git push)" "git push origin main"
case_check "33 a # inside double or single quotes is not a comment" "$(printf '%s\n%s' 'git push origin "a # b"' "git push origin 'a # c'" | "$SELF" git push)" "git push origin a # b
git push origin a # c"
case_check "34 a # glued to a word is part of the word" "$(printf 'git push origin a#b' | "$SELF" git push)" "git push origin a#b"
case_check "35 a # glued to a word does not hide the push on the next line" "$(printf 'echo a#b\ngit push origin main' | "$SELF" git push)" "git push origin main"
case_check "36 a push inside a heredoc body fed to sh still counts" "$(printf 'sh <<EOF\ngit push origin main\nEOF' | "$SELF" git push)" "git push origin main"
case_check "37 a COMMENT inside that body does not hide the push below it" "$(printf 'sh <<EOF\necho a # c\ngit push origin main\nEOF' | "$SELF" git push)" "git push origin main"
case_check "38 a COMMENT after an APOSTROPHE in a heredoc does not hide the push" "$(printf "cat <<'EOF'\nO'Reilly\nEOF\n# a note\ngit push origin main # done" | "$SELF" git push)" "git push origin main"
case_check "39 a # that counts or measures a parameter is not a comment" "$(printf 'echo $# ${#x}\ngit push origin main' | "$SELF" git push)" "git push origin main"
lonely_dir=$(mktemp -d); cp "$SELF" "$lonely_dir/"
case_check "40 without shell-text.sh beside it the parser says it could not parse" "$(printf 'ls' | sh "$lonely_dir/$(basename "$SELF")" git push 2>/dev/null; echo "exit=$?")" "exit=3"
rm -rf "$lonely_dir"
[ "$ok" = "1" ] && echo "SELFTEST OK: 40/40" && exit 0
echo "SELFTEST FAILED"; exit 1
