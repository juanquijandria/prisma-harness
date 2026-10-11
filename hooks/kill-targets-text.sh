# Prisma Harness. Documented in README.md, section "What is inside". Loaded by kill-targets.sh, not run alone.
SHELL_TEXT_CODE=$(cat <<'PY'
import re

SINGLE_QUOTE = "'"
QUOTES = SINGLE_QUOTE + '"'
BACKTICK = "\x60"
SKIPPED_SPANS = QUOTES + BACKTICK
BACKSLASH = "\\"
NEWLINE = "\n"
COMMENT = "#"
HEREDOC_START = "<"
ARITHMETIC_OPEN = "(("
PARENTHESIS_DEPTH = {"(": 1, ")": -1}
WORD_ENDS = set(" \t\n;&|<>()")
HEREDOC_OPERATOR = re.compile(r"<<(?!<)(-?)[ \t]*")


def read_delimiter(text, index):
    word = []
    while index < len(text) and text[index] not in WORD_ENDS:
        character = text[index]
        if character in QUOTES:
            end = text.find(character, index + 1)
            if end < 0:
                return None, index
            word.append(text[index + 1:end])
            index = end + 1
        elif character == BACKSLASH:
            word.append(text[index + 1:index + 2])
            index += 2
        else:
            word.append(character)
            index += 1
    return "".join(word), index


def heredoc_at(text, index):
    if index > 0 and text[index - 1] == HEREDOC_START:
        return None
    operator = HEREDOC_OPERATOR.match(text, index)
    if not operator:
        return None
    delimiter, end = read_delimiter(text, operator.end())
    return None if delimiter is None or end == operator.end() else (delimiter, operator.group(1) == "-", end)


def line_end(text, start):
    end = text.find(NEWLINE, start)
    return len(text) if end < 0 else end


def after_bodies(text, newline, pending):
    position = newline
    for delimiter, strips_tabs in pending:
        while position < len(text):
            end = line_end(text, position + 1)
            line = text[position + 1:end]
            position = end
            if (line.lstrip("\t") if strips_tabs else line) == delimiter:
                break
    return position


def quoted_end(text, index):
    quote, index = text[index], index + 1
    while index < len(text) and text[index] != quote:
        index += 2 if text[index] == BACKSLASH and quote != SINGLE_QUOTE else 1
    return index + 1


def balanced_end(text, index):
    depth = 0
    while index < len(text):
        if text[index] in SKIPPED_SPANS:
            index = quoted_end(text, index)
            continue
        depth += PARENTHESIS_DEPTH.get(text[index], 0)
        index += 1
        if depth == 0:
            break
    return index


def without_bodies_and_comments(command):
    kept, pending, index = [], [], 0
    while index < len(command):
        character, start = command[index], index
        heredoc = heredoc_at(command, index) if character == HEREDOC_START else None
        if character in SKIPPED_SPANS:
            index = quoted_end(command, index)
        elif character == BACKSLASH:
            index += 2
        elif command.startswith(ARITHMETIC_OPEN, index):
            index = balanced_end(command, index)
        elif character == COMMENT and (index == 0 or command[index - 1] in WORD_ENDS):
            index = line_end(command, index)
            continue
        elif character == NEWLINE and pending:
            kept.append(NEWLINE)
            index, pending = after_bodies(command, index, pending), []
            continue
        elif heredoc:
            pending.append(heredoc[:2])
            index = heredoc[2]
        else:
            index += 1
        kept.append(command[start:index])
    return "".join(kept)
PY
)
