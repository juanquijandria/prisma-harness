#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
MISSING_PYTHON=3
PYTHON="${PRISMA_PYTHON-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "WARN: quote-zsh-words.sh needs python3 or python and found neither." >&2; exit "$MISSING_PYTHON"; }
CODE=$(cat <<'PY'
import re
import sys

UNSAFE_INCLUDE = 4
UNSAFE_EQUALS = 6
FLAG = "--include"
EQUALS = "=="
GLOB_CHARACTERS = set("*?[")
QUOTING_CHARACTERS = set("'\"\\$")
EQUALS_UNSAFE_CHARACTERS = QUOTING_CHARACTERS | GLOB_CHARACTERS | set("{")
WORD_ENDS = set(" \t\n;&|<>()")
BACKTICK = "\x60"
READ_WORD_ENDS = WORD_ENDS | {BACKTICK}
COMMAND_SEPARATORS = set(";&|\n(")
COMMAND_POSITION_WORDS = {"if", "then", "else", "elif", "do", "while", "until", "!", "{", "time"}
BLANKS = " \t"
LINE_BLANKS = " \t\n"
QUOTES = "'\""
SKIPPED_SPANS = QUOTES + BACKTICK
TEST_OPEN = "[["
TEST_CLOSE = "]]"
ARITHMETIC_OPEN = "(("
ARITHMETIC_EXPANSION = "\x24(("
CASE_WORD = "case"
IN_WORD = "in"
ESAC_WORD = "esac"
CASE_SUBJECT = "subject"
CASE_PATTERN = "pattern"
CASE_BODY = "body"
CASE_SEPARATORS = (";;&", ";;", ";&", ";|")
HEREDOC_OPERATOR = re.compile(r"<<(?!<)(-?)[ \t]*")

class Unsafe(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


def unquoted_glob(value):
    return any(character in GLOB_CHARACTERS for _, character in unquoted_characters(value, 0))


def expand_braces(value):
    opening, closing = value.find("{"), value.find("}")
    if opening < 0 and closing < 0:
        return [value]
    if value.count("{") != 1 or value.count("}") != 1 or closing < opening:
        raise Unsafe(UNSAFE_INCLUDE)
    items = value[opening + 1:closing].split(",")
    if len(items) < 2:
        raise Unsafe(UNSAFE_INCLUDE)
    return [value[:opening] + item + value[closing + 1:] for item in items]


def read_word(text, start):
    end = start
    while end < len(text) and text[end] not in READ_WORD_ENDS:
        end += 1
    return text[start:end], end


def quoted_flags(value, separator):
    if not unquoted_glob(value):
        return None
    if any(character in QUOTING_CHARACTERS for character in value):
        raise Unsafe(UNSAFE_INCLUDE)
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


def quoted_equals(value):
    if any(character in EQUALS_UNSAFE_CHARACTERS for character in value):
        raise Unsafe(UNSAFE_EQUALS)
    return "'" + value + "'"


def skip_quoted(text, index):
    quote, index = text[index], index + 1
    while index < len(text) and text[index] != quote:
        index += 2 if text[index] == "\\" and quote != "'" else 1
    return min(index + 1, len(text))


def skip_line(text, index):
    end = text.find("\n", index)
    return len(text) if end < 0 else end


def unquoted_characters(text, index):
    while index < len(text):
        character = text[index]
        if character in QUOTES:
            index = skip_quoted(text, index)
        elif character == "\\":
            index += 2
        else:
            yield index, character
            index += 1


def skip_balanced(text, index):
    depth = 0
    for position, character in unquoted_characters(text, index):
        depth += {"(": 1, ")": -1}.get(character, 0)
        if depth == 0:
            return position + 1
    return len(text)


def skip_test(text, index):
    for position, _ in unquoted_characters(text, index + len(TEST_OPEN)):
        if text.startswith(TEST_CLOSE, position) and text[position - 1] in BLANKS:
            return position + len(TEST_CLOSE)
    return len(text)


def skip_pattern(text, index):
    for position, character in unquoted_characters(text, index):
        if character == ")":
            return position + 1
    return len(text)


def case_separator_at(text, index):
    return next((separator for separator in CASE_SEPARATORS if text.startswith(separator, index)), None)


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
        elif character == "\\":
            word.append(text[index + 1:index + 2])
            index += 2
        else:
            word.append(character)
            index += 1
    return "".join(word), index


def heredoc_at(text, index):
    if index > 0 and text[index - 1] == "<":
        return None
    operator = HEREDOC_OPERATOR.match(text, index)
    if not operator:
        return None
    delimiter, end = read_delimiter(text, operator.end())
    return None if delimiter is None or end == operator.end() else (delimiter, operator.group(1) == "-", end)


def closes_heredoc(line, delimiter, strips_tabs):
    return (line.lstrip("\t") if strips_tabs else line) == delimiter


def skip_heredoc_bodies(text, newline, delimiters):
    position = newline
    for delimiter, strips_tabs in delimiters:
        while position < len(text):
            line_end = skip_line(text, position + 1)
            line = text[position + 1:line_end]
            position = line_end
            if closes_heredoc(line, delimiter, strips_tabs):
                break
    return position


class Quoter:
    def __init__(self, text):
        self.text, self.index, self.out, self.changed = text, 0, [], False
        self.pending, self.cases = [], []
        self.at_word_start, self.at_command = True, True

    def run(self):
        while self.index < len(self.text):
            start = self.index
            replacement = self.step()
            if replacement is None:
                self.out.append(self.text[start:self.index])
            else:
                self.out.append(replacement)
                self.changed = True
            last = self.text[self.index - 1]
            self.at_word_start = last in WORD_ENDS
            self.at_command = self.at_command or last in COMMAND_SEPARATORS
        return "".join(self.out) if self.changed else ""

    def in_case(self, state):
        return bool(self.cases) and self.cases[-1] == state

    def step(self):
        text, index = self.text, self.index
        character = text[index]
        heredoc = heredoc_at(text, index) if character == "<" else None
        if character in SKIPPED_SPANS:
            self.index, self.at_command = skip_quoted(text, index), False
        elif character == "\\":
            self.index, self.at_command = index + 2, False
        elif character == "#" and self.at_word_start:
            self.index = skip_line(text, index)
        elif character == "\n" and self.pending:
            self.index, self.pending = skip_heredoc_bodies(text, index, self.pending), []
        elif heredoc:
            self.pending.append(heredoc[:2])
            self.index = heredoc[2]
        elif text.startswith(ARITHMETIC_EXPANSION, index):
            self.index = skip_balanced(text, index + 1)
        elif character == ";" and self.in_case(CASE_BODY) and case_separator_at(text, index):
            self.index = index + len(case_separator_at(text, index))
            self.cases[-1] = CASE_PATTERN
        elif self.at_word_start:
            return self.step_word()
        else:
            self.index = index + 1
        return None

    def step_word(self):
        text, index = self.text, self.index
        if self.in_case(CASE_PATTERN):
            return self.step_pattern()
        word, at_command = read_word(text, index)[0], self.at_command
        if word:
            self.at_command = word in COMMAND_POSITION_WORDS
        if at_command and word == TEST_OPEN:
            self.index = skip_test(text, index)
        elif at_command and text.startswith(ARITHMETIC_OPEN, index):
            self.index = skip_balanced(text, index)
        elif text.startswith(FLAG, index):
            replacement, end = rewrite_flag(text, index)
            self.index = max(end, index + 1)
            return replacement
        elif word.startswith(EQUALS):
            self.index = index + len(word)
            return quoted_equals(word)
        else:
            self.track_case(word, at_command)
            self.index = index + 1
        return None

    def step_pattern(self):
        text, index = self.text, self.index
        if text[index] in LINE_BLANKS:
            self.index = index + 1
        elif read_word(text, index)[0] == ESAC_WORD:
            self.cases.pop()
            self.index, self.at_command = index + len(ESAC_WORD), False
        else:
            self.index = skip_pattern(text, index)
            self.cases[-1], self.at_command = CASE_BODY, True
        return None

    def track_case(self, word, at_command):
        if at_command and word == CASE_WORD:
            self.cases.append(CASE_SUBJECT)
        elif word == IN_WORD and self.in_case(CASE_SUBJECT):
            self.cases[-1] = CASE_PATTERN
        elif at_command and word == ESAC_WORD and self.cases:
            self.cases.pop()


try:
    result = Quoter(sys.stdin.read()).run()
except Unsafe as unsafe:
    sys.exit(unsafe.code)
sys.stdout.reconfigure(newline="\n")
sys.stdout.write(result)
PY
)
"$PYTHON" -c "$CODE"
