#!/bin/sh
# Prisma Harness. Documented in README.md, section "command-invokes". Same behavior as its source in the author's toolbox, identifiers translated.

SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")

if [ "$1" = "--selftest" ]; then
  ok=1
  case_check() {
    if [ "$2" = "$3" ]; then echo "PASS case $1"; else echo "FAIL case $1, expected [$3] and got [$2]"; ok=0; fi
  }
  PATHS="inbox/Reunion HI LUCA 1 DE 5
raw/x"
  balanced='mv "inbox/Reunion HI LUCA 1 DE 5" raw/x'
  heredoc="mv \"inbox/Reunion HI LUCA 1 DE 5\" raw/x && cat >> log.md <<'EOF'
el clip de O'Reilly
EOF"
  second_mv="cat >> log.md <<'EOF'
el clip de O'Reilly
EOF
mv \"inbox/Reunion HI LUCA 1 DE 5\" raw/x"
  case_check "1 balanced quotes" "$(printf '%s' "$balanced" | "$SELF" --arguments mv)" "$PATHS"
  case_check "2 APOSTROPHE in a heredoc, the origin is not lost" "$(printf '%s' "$heredoc" | "$SELF" --arguments mv)" "$PATHS"
  case_check "3 APOSTROPHE before the mv, still detected" "$(printf '%s' "$second_mv" | "$SELF" --arguments mv)" "$PATHS"
  case_check "4 a quoted command is not an invocation" "$(printf '%s' 'echo "mv inbox/a raw/x"' | "$SELF" --arguments mv; echo "exit=$?")" "exit=1"
  case_check "5 a real separator splits the command" "$(printf '%s' 'ls; mv "inbox/Reunion HI LUCA 1 DE 5" raw/x' | "$SELF" --arguments mv)" "$PATHS"
  case_check "6 env assignment before the program" "$(printf '%s' 'IMAGENES="3 informativas, 0 referenciales" mv "inbox/Reunion HI LUCA 1 DE 5" raw/x' | "$SELF" --arguments mv)" "$PATHS"
  case_check "7 a separator inside quotes does not split" "$(printf '%s' 'git commit -m "no toca; mv a b"' | "$SELF" --arguments mv; echo "exit=$?")" "exit=1"
  case_check "8 subcommand after flags that take a value" "$(printf '%s' 'git -C /tmp push origin main' | "$SELF" git push)" "git -C /tmp push origin main"
  case_check "9 trailing comment" "$(printf '%s' 'mv "inbox/Reunion HI LUCA 1 DE 5" raw/x # nota' | "$SELF" --arguments mv)" "$PATHS"
  case_check "10 program absent" "$(printf '%s' 'ls -la' | "$SELF" --arguments mv; echo "exit=$?")" "exit=1"
  apostrophes_around="cat >/dev/null <<'A'
x'y
A
mv \"inbox/Reunion HI LUCA 1 DE 5\" raw/x
cat >/dev/null <<B
close'
unmatched'
B"
  case_check "11 APOSTROPHES enclosing the mv, still detected" "$(printf '%s' "$apostrophes_around" | "$SELF" --arguments mv)" "$PATHS"
  case_check "12 REDIRECTION before the program, still detected" "$(printf '%s' '>/dev/null mv "inbox/Reunion HI LUCA 1 DE 5" raw/x' | "$SELF" --arguments mv)" "$PATHS"
  case_check "13 a redirection target is not a program" "$(printf '%s' 'echo hola > mv' | "$SELF" --arguments mv; echo "exit=$?")" "exit=1"
  case_check "14 redirection after the arguments" "$(printf '%s' 'mv "inbox/Reunion HI LUCA 1 DE 5" raw/x >/dev/null' | "$SELF" --arguments mv)" "$PATHS"
  stray_double="cat >> log.md <<'EOF'
la tabla dice 5\" de ancho
EOF
mv \"inbox/Reunion HI LUCA 1 DE 5\" raw/x"
  stray_single="cat >> log.md <<'EOF'
el clip de O'Reilly
EOF
mv 'inbox/Reunion HI LUCA 1 DE 5' raw/x"
  case_contains() {
    case "$2" in *"$3"*) echo "PASS case $1";; *) echo "FAIL case $1, expected it to contain [$3] and got [$2]"; ok=0;; esac
  }
  case_contains "15 stray DOUBLE QUOTE with the path in double quotes" "$(printf '%s' "$stray_double" | "$SELF" --arguments mv)" "$PATHS"
  case_contains "16 stray APOSTROPHE with the path in single quotes" "$(printf '%s' "$stray_single" | "$SELF" --arguments mv)" "$PATHS"
  [ "$ok" = "1" ] && echo "SELFTEST OK: 16/16" && exit 0
  echo "SELFTEST FAILED"; exit 1
fi

if [ "$1" = "--arguments" ]; then
  MODE=arguments; shift
else
  MODE=segments
fi

PROGRAM="${1:?program name required}"
SUBCOMMAND="${2:-}"

PYTHON=$(command -v python3 || command -v python)
[ -n "$PYTHON" ] || { echo "WARN: command-invokes.sh needs python3 or python and found neither." >&2; exit 3; }
MODE="$MODE" PROGRAM="$PROGRAM" SUBCOMMAND="$SUBCOMMAND" "$PYTHON" -c '
import io, os, re, shlex, sys
sys.stdout.reconfigure(newline="\n")

mode = os.environ["MODE"]
program = os.environ["PROGRAM"]
subcommand = os.environ["SUBCOMMAND"]
command = sys.stdin.read()

SHLEX_SEPARATORS = {";", "&", "&&", "|", "||", "(", ")", "{", "}", "\n", "<", ">", ">>"}
REDIRECTIONS = {"<", ">", ">>", "<<", "<<<", ">&", "&>", ">|"}
HAND_SEPARATORS = ";&|\n(){}<>"
HAND_REDIRECTIONS = "<>"
QUOTES = "\"'"'"'"
WHITESPACE = " \t\r"
ENV_ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
CONTROL_WORDS = {"then", "do", "else", "elif", "fi", "done", "!", "time", "sudo", "command", "exec", "env", "nohup"}


def segments_with_shlex(text):
    lexer = shlex.shlex(io.StringIO(text), posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    current, output, skip = [], [], False
    for token in lexer:
        if skip:
            skip = False
        elif token in REDIRECTIONS:
            skip = True
        elif token in SHLEX_SEPARATORS:
            output.append(current)
            current = []
        else:
            current.append(token)
    output.append(current)
    return output


def segments_by_hand(text, quotes=QUOTES):
    output, current, token = [], [], ""
    quote, i, skip = None, 0, False
    while i < len(text):
        char = text[i]
        if quote:
            if char == quote:
                quote = None
            elif char == "\\" and quote == "\"" and i + 1 < len(text):
                i += 1
                token += text[i]
            else:
                token += char
        elif char in quotes:
            quote = char
        elif char == "\\" and i + 1 < len(text):
            i += 1
            token += text[i]
        elif char == "#" and not token:
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        elif char in WHITESPACE:
            if token:
                if skip:
                    skip = False
                else:
                    current.append(token)
                token = ""
        elif char in HAND_SEPARATORS:
            if token:
                if skip:
                    skip = False
                else:
                    current.append(token)
                token = ""
            if char in HAND_REDIRECTIONS:
                skip = True
            else:
                output.append(current)
                current = []
        else:
            token += char
        i += 1
    if token and not skip:
        current.append(token)
    output.append(current)
    if quote:
        output.extend(segments_by_hand(text, quotes.replace(quote, "")))
    return output


def segments_reversed(text):
    inverted = segments_by_hand(text[::-1])
    return [[token[::-1] for token in reversed(tokens)] for tokens in reversed(inverted)]


try:
    segments = segments_with_shlex(command)
except ValueError:
    segments = segments_by_hand(command) + segments_reversed(command)

found = []
for tokens in segments:
    tokens = list(tokens)
    while tokens and (ENV_ASSIGNMENT.match(tokens[0]) or tokens[0] in CONTROL_WORDS):
        tokens.pop(0)
    if not tokens:
        continue
    if tokens[0].rsplit("/", 1)[-1] != program:
        continue
    if not subcommand:
        found.append(tokens)
        continue
    rest = tokens[1:]
    i = 0
    while i < len(rest) and rest[i].startswith("-"):
        takes_value = rest[i] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path")
        i += 2 if takes_value else 1
    if i < len(rest) and rest[i] == subcommand:
        found.append(tokens)

unique, seen = [], set()
for tokens in found:
    key = tuple(tokens)
    if key not in seen:
        seen.add(key)
        unique.append(tokens)

for tokens in unique:
    if mode == "arguments":
        for token in tokens[1:]:
            print(token)
    else:
        print(" ".join(tokens))

sys.exit(0 if found else 1)
'
