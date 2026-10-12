#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
MISSING_PIECE=3
HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
PYTHON="${PRISMA_PYTHON-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "WARN: secret-args.sh needs python3 or python and found neither." >&2; exit "$MISSING_PIECE"; }
for piece in shell-text.sh secret-names.sh; do
  [ -r "$HERE/$piece" ] || { echo "WARN: secret-args.sh needs $piece next to it and did not find it." >&2; exit "$MISSING_PIECE"; }
  . "$HERE/$piece"
done
CODE=$(cat <<'PY'
import os
import sys

UNREADABLE = 5
UNREADABLE_MARKS = ("\x60", "\x24(", "<<")
REDIRECTION_OPERATOR = "<>&|"
ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")
LEADING_WORDS = {"then", "do", "else", "elif", "!", "{", "time", "sudo", "command", "exec", "env", "nohup"}
WHOLE_COMMAND = "SECRET_COMMAND"
INPUT_REDIRECTION = "<"
NOT_A_FILE_AFTER_INPUT = "(&"
SUBSTITUTION = "\x24("
MENTION_SPLIT = re.compile(r"[\s;&|()<>'\"]+")
REDIRECTED_VERDICT = BLOCK + "\t" + INPUT_REDIRECTION + " "


def mentions_a_secret(command):
    return any(names_secrets(word) for word in MENTION_SPLIT.split(without_comments(command, True)))


def input_target(text, index):
    following = text[index + 1:index + 2]
    if text[index - 1:index] == INPUT_REDIRECTION or (following and following in NOT_A_FILE_AFTER_INPUT):
        return ""
    start = index + 1
    while start < len(text) and text[start] in BLANKS:
        start += 1
    try:
        return read_word(text, start)[0]
    except Unreadable:
        return ""


def substitutions(quoted):
    parts, index = [], quoted.find(SUBSTITUTION)
    while index >= 0:
        end = balanced_end(quoted, index + 1)
        parts.append(quoted[index + len(SUBSTITUTION):end - 1])
        index = quoted.find(SUBSTITUTION, end)
    return " ; ".join(parts)


def code_view(text):
    kept, index = [], 0
    while index < len(text):
        character = text[index]
        if character in QUOTES:
            end = quoted_end(text, index)
            kept.append(" " + (substitutions(text[index + 1:end - 1]) if character == DOUBLE_QUOTE else "") + " ")
            index = end
        elif character == BACKTICK:
            kept.append(" ")
            index += 1
        elif character == BACKSLASH:
            kept.append("  ")
            index += 2
        else:
            kept.append(character)
            index += 1
    return "".join(kept)


def redirected_secrets(command):
    text = code_view(without_comments(command, True))
    targets = [input_target(text, index) for index, character in enumerate(text) if character == INPUT_REDIRECTION]
    return [target for target in targets if names_secrets(target)]


def finds_read_whole(command, mentions):
    try:
        commands = simple_commands(command)
    except Unreadable:
        return []
    words = [[value for value, _, _ in without_leading_words(tokens)] for tokens, _ in commands]
    return [" ".join(found) for found in words if found and program_name(found[0]) == FIND and classify(found, mentions) == BLOCK]


def classify_lines(text, command):
    mentions = mentions_a_secret(command)
    for line in text.splitlines():
        tokens = line.split()
        if tokens:
            print(classify(tokens, mentions) + "\t" + line)
    for found in finds_read_whole(command, mentions):
        print(BLOCK + "\t" + found)
    for target in redirected_secrets(command):
        print(REDIRECTED_VERDICT + target)


def skip_redirection(text, index):
    while index < len(text) and text[index] in REDIRECTION_OPERATOR:
        index += 1
    while index < len(text) and text[index] in BLANKS:
        index += 1
    return read_word(text, index)[1]


def starts_redirection(text, index):
    return text[index] in REDIRECTIONS or text.startswith("&>", index)


def simple_commands(text):
    if any(mark in text for mark in UNREADABLE_MARKS):
        raise Unreadable()
    commands, tokens, index, end = [], [], 0, 0
    while index < len(text):
        character = text[index]
        if character in BLANKS:
            index += 1
        elif character == COMMENT and not tokens:
            index = line_end(text, index)
        elif starts_redirection(text, index):
            index = end = skip_redirection(text, index)
        elif character in COMMAND_SEPARATORS:
            commands.append((tokens, end))
            tokens, index = [], index + 1
        else:
            start = index
            value, index = read_word(text, index)
            if not (value.isdigit() and index < len(text) and text[index] in REDIRECTIONS):
                tokens.append((value, start, index))
                end = index
    commands.append((tokens, end))
    return [(tokens, end) for tokens, end in commands if tokens]


def without_leading_words(tokens):
    while tokens and (ASSIGNMENT.match(tokens[0][0]) or tokens[0][0] in LEADING_WORDS):
        tokens = tokens[1:]
    return tokens


def insertion_for(tokens, end):
    program = program_name(tokens[0][0])
    if program == GIT:
        return end, " " + PATHSPEC_EXCLUSION
    return tokens[0][2], " " + EXCLUSION_AFTER_PROGRAM[program]


def rewrite(text):
    insertions = []
    for tokens, end in simple_commands(text):
        tokens = without_leading_words(tokens)
        if tokens and classify([value for value, _, _ in tokens]) == REWRITE:
            insertions.append(insertion_for(tokens, end))
    for position, addition in sorted(insertions, reverse=True):
        text = text[:position] + addition + text[position:]
    return len(insertions), text


mode = sys.argv[1] if len(sys.argv) > 1 else ""
sys.stdout.reconfigure(newline="\n")
if mode == "--classify":
    classify_lines(sys.stdin.read(), os.environ.get(WHOLE_COMMAND, ""))
elif mode == "--rewrite":
    try:
        count, rewritten = rewrite(sys.stdin.read())
    except Unreadable:
        sys.exit(UNREADABLE)
    sys.stdout.write(str(count) + "\n" + rewritten)
else:
    sys.exit("usage: secret-args.sh --classify or --rewrite")
PY
)
"$PYTHON" -c "$SHELL_TEXT_CODE
$SECRET_NAMES_CODE
$CODE" "$@"
