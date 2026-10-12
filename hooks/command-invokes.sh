#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside". Same behavior as its source in the author's toolbox, identifiers translated.
if [ "${1:-}" = "--selftest" ]; then . "$(cd "$(dirname "$0")" && pwd)/selftest-env.sh"; fi

SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")

if [ "$1" = "--selftest" ]; then
  . "$(dirname "$SELF")/command-invokes-tests.sh"
fi

if [ "$1" = "--arguments" ]; then
  MODE=arguments; shift
else
  MODE=segments
fi

PROGRAM="${1:?program name required}"
SUBCOMMAND="${2:-}"

PYTHON="${PRISMA_PYTHON-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "WARN: command-invokes.sh needs python3 or python and found neither." >&2; exit 3; }
SHELL_TEXT="$(dirname "$SELF")/shell-text.sh"
[ -r "$SHELL_TEXT" ] || { echo "WARN: command-invokes.sh needs shell-text.sh next to it and did not find it." >&2; exit 3; }
. "$SHELL_TEXT"
ERRFILE=$(mktemp) || { echo "WARN: command-invokes.sh could not create a temporary file, so the command was not parsed." >&2; exit 3; }
trap 'rm -f "$ERRFILE"' EXIT
MODE="$MODE" PROGRAM="$PROGRAM" SUBCOMMAND="$SUBCOMMAND" "$PYTHON" -c "$SHELL_TEXT_CODE"'
import io, os, re, shlex, sys, traceback


def crash(kind, value, trace):
    traceback.print_exception(kind, value, trace)
    sys.stdout.flush()
    os._exit(4)


sys.excepthook = crash
if os.environ.get("PRISMA_PARSER_FAULT"):
    raise RuntimeError("fault injected by PRISMA_PARSER_FAULT")
sys.stdout.reconfigure(newline="\n")

mode = os.environ["MODE"]
program = os.environ["PROGRAM"]
subcommand = os.environ["SUBCOMMAND"]
command = sys.stdin.read()

SHLEX_SEPARATORS = {";", "&", "&&", "|", "||", "(", ")", "{", "}", "\n", "<", ">", ">>"}
PUNCTUATION = "();<>|&\n"
SEPARATORS_INSIDE_PUNCTUATION = set(";&|()")
REDIRECTIONS = {"<", ">", ">>", "<<", "<<<", ">&", "&>", "&>>", ">|"}
HAND_SEPARATORS = ";&|\n(){}<>"
HAND_REDIRECTIONS = "<>"
WHITESPACE = " \t\r"
ENV_ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
VALUE_FLAGS = {"git": ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"),
              "gh": ("-R", "--repo", "--hostname")}
CONTROL_WORDS = {"then", "do", "else", "elif", "fi", "done", "!", "time", "sudo", "command", "exec", "env", "nohup"}
WORD_BOUNDARIES = WHITESPACE + "\n;|()"


def without_stream_numbers(text, quotes=QUOTES):
    kept, quote, i, word_start = [], None, 0, True
    while i < len(text):
        char = text[i]
        step = 2 if char == "\\" and quote != SINGLE_QUOTE and i + 1 < len(text) else 1
        if not quote and step == 1 and word_start and char.isdigit():
            end = i
            while end < len(text) and text[end].isdigit():
                end += 1
            if end < len(text) and text[end] in HAND_REDIRECTIONS:
                i = end
                continue
        if not quote and step == 1 and char in quotes:
            quote = char
        elif quote == char:
            quote = None
        kept.append(text[i:i + step])
        after_separator = char in WORD_BOUNDARIES or (char == "&" and text[i - 1:i] not in HAND_REDIRECTIONS)
        word_start = not quote and step == 1 and after_separator
        i += step
    if quote:
        return without_stream_numbers(text, quotes.replace(quote, ""))
    return "".join(kept)


def punctuation_pieces(token):
    if not ("\n" in token and set(token) <= set(PUNCTUATION)):
        return [token]
    pieces = []
    for part in token.split("\n"):
        if part:
            pieces.append(part)
        pieces.append("\n")
    return pieces[:-1]


def is_separator(piece):
    if piece in SHLEX_SEPARATORS:
        return True
    characters = set(piece)
    return characters <= set(PUNCTUATION) and bool(characters & SEPARATORS_INSIDE_PUNCTUATION)


def segments_with_shlex(text):
    lexer = shlex.shlex(io.StringIO(text), posix=True, punctuation_chars=PUNCTUATION)
    lexer.whitespace = WHITESPACE
    lexer.whitespace_split = True
    lexer.commenters = ""
    current, output, skip = [], [], False
    for token in lexer:
        for piece in punctuation_pieces(token):
            if skip:
                skip = False
            elif piece in REDIRECTIONS:
                skip = True
            elif is_separator(piece):
                output.append(current)
                current = []
                skip = piece[-1] in HAND_REDIRECTIONS
            else:
                current.append(piece)
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


uncommented = without_comments(command, drop_bodies=False)
readable = without_stream_numbers(uncommented)
try:
    segments = segments_with_shlex(readable)
except ValueError:
    segments = segments_by_hand(readable) + segments_reversed(uncommented)

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
        takes_value = rest[i] in VALUE_FLAGS.get(program, ())
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
' 2>"$ERRFILE"
rc=$?
[ -s "$ERRFILE" ] && cat "$ERRFILE" >&2
[ "$rc" = "0" ] || { echo "WARN: command-invokes.sh could not parse the command, so the trigger was not evaluated." >&2; exit 3; }
exit 0
