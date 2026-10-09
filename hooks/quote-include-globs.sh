#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
MISSING_PYTHON=3
PYTHON="${PRISMA_PYTHON-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "WARN: quote-include-globs.sh needs python3 or python and found neither." >&2; exit "$MISSING_PYTHON"; }
CODE=$(cat <<'PY'
import re
import sys

UNSAFE = 4
FLAG = "--include"
GLOB_CHARACTERS = set("*?[")
QUOTING_CHARACTERS = set("'\"\\$")
WORD_ENDS = set(" \t\n;&|<>()")
BLANKS = " \t"
HEREDOC_START = re.compile(r"<<(?!<)-?[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


class Unsafe(Exception):
    pass


def unquoted_glob(value):
    quote, index = None, 0
    while index < len(value):
        character = value[index]
        if quote:
            quote = None if character == quote else quote
        elif character == "\\":
            index += 1
        elif character in "'\"":
            quote = character
        elif character in GLOB_CHARACTERS:
            return True
        index += 1
    return False


def expand_braces(value):
    opening, closing = value.find("{"), value.find("}")
    if opening < 0 and closing < 0:
        return [value]
    if value.count("{") != 1 or value.count("}") != 1 or closing < opening:
        raise Unsafe(value)
    items = value[opening + 1:closing].split(",")
    if len(items) < 2:
        raise Unsafe(value)
    return [value[:opening] + item + value[closing + 1:] for item in items]


def read_word(text, start):
    end = start
    while end < len(text) and text[end] not in WORD_ENDS:
        end += 1
    return text[start:end], end


def quoted_flags(value, separator):
    if not unquoted_glob(value):
        return None
    if any(character in QUOTING_CHARACTERS for character in value):
        raise Unsafe(value)
    return " ".join(FLAG + separator + "'" + item + "'" for item in expand_braces(value))


def rewrite_flag(text, index):
    after = index + len(FLAG)
    if after >= len(text):
        return None, index
    if text[after] == "=":
        value, end = read_word(text, after + 1)
        return quoted_flags(value, "="), end
    if text[after] not in BLANKS:
        return None, index
    start = after
    while start < len(text) and text[start] in BLANKS:
        start += 1
    value, end = read_word(text, start)
    return quoted_flags(value, " "), end


def skip_quoted(text, index):
    quote, index = text[index], index + 1
    while index < len(text) and text[index] != quote:
        index += 2 if text[index] == "\\" and quote == '"' else 1
    return min(index + 1, len(text))


def skip_line(text, index):
    end = text.find("\n", index)
    return len(text) if end < 0 else end


def skip_heredoc_bodies(text, newline, delimiters):
    position = newline
    for delimiter in delimiters:
        while position < len(text):
            line_end = skip_line(text, position + 1)
            line = text[position + 1:line_end]
            position = line_end
            if line.strip() == delimiter:
                break
    return position


def heredoc_at(text, index):
    if index > 0 and text[index - 1] == "<":
        return None
    return HEREDOC_START.match(text, index)


def rewrite(text):
    out, index, changed, pending, at_word_start = [], 0, False, [], True
    while index < len(text):
        character, start = text[index], index
        heredoc = heredoc_at(text, index) if character == "<" else None
        if character in "'\"":
            index = skip_quoted(text, index)
        elif character == "\\":
            index += 2
        elif character == "#" and at_word_start:
            index = skip_line(text, index)
        elif character == "\n" and pending:
            index, pending = skip_heredoc_bodies(text, index, pending), []
        elif heredoc:
            pending.append(heredoc.group(2))
            index = heredoc.end()
        elif at_word_start and text.startswith(FLAG, index):
            replacement, index = rewrite_flag(text, index)
            if replacement:
                out.append(replacement)
                changed, at_word_start = True, False
                continue
            index = max(index, start + 1)
        else:
            index += 1
        out.append(text[start:index])
        at_word_start = text[index - 1] in WORD_ENDS
    return "".join(out) if changed else ""


try:
    result = rewrite(sys.stdin.read())
except Unsafe:
    sys.exit(UNSAFE)
sys.stdout.reconfigure(newline="\n")
sys.stdout.write(result)
PY
)
"$PYTHON" -c "$CODE"
