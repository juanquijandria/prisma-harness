#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
MISSING_PYTHON=3
PYTHON="${PRISMA_PYTHON-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "WARN: kill-targets.sh needs python3 or python and found neither." >&2; exit "$MISSING_PYTHON"; }
CODE=$(cat <<'PY'
import os
import re
import shlex
import subprocess
import sys

CANNOT_MEASURE = 3
PARTLY_MEASURED = 5
PGREP_FOUND, PGREP_NOTHING = 0, 1
KILLERS = {"pkill", "killall"}
SEPARATORS = {";", "&&", "||", "|", "&", "\n", "(", ")"}
SIGNAL_ARGUMENT = re.compile(r"^-([0-9]+|[A-Z][A-Z0-9]*)$")
PUNCTUATION = ";&|()<>"
SEPARATOR_CHARACTERS = set(";&|()")
REDIRECTION_CHARACTERS = set("<>")
HIDDEN_REDIRECTION_ORDER = "<>"
PRIVATE_USE_FIRST, PRIVATE_USE_LAST = 0xE000, 0xF8FF
WORD_BREAKS = set(" \t\n;&|()")
KILLALL_FLAGS_WITH_VALUE = {"-u", "-t", "-c", "-s"}
COMMAND_WIDTH = 80
LSOF = os.environ.get("PRISMA_LSOF") or "lsof"
PGREP = os.environ.get("PRISMA_PGREP") or "pgrep"
PROC_ROOT = "/proc"
LINUX_NAME_WIDTH = 15
PROC_FOLDER = "/proc/%d/cwd"
PROC_COMMAND_LINE = "/proc/%d/cmdline"
POSIX = "posix"
EXISTENCE_PROBE = 0


def free_markers(command):
    used = set(command)
    free = [chr(code) for code in range(PRIVATE_USE_FIRST, PRIVATE_USE_LAST + 1) if chr(code) not in used]
    if len(free) < len(HIDDEN_REDIRECTION_ORDER):
        raise ValueError("no free private use character is left to hide a quoted redirection")
    return dict(zip(HIDDEN_REDIRECTION_ORDER, free))


def hide_redirection(characters, index, markers):
    if index < len(characters) and characters[index] in markers:
        characters[index] = markers[characters[index]]


def lexer_ready(command, markers):
    characters, quote, index = list(command), None, 0
    while index < len(command):
        character = command[index]
        if character == "\\" and quote != "'":
            index += 1
            hide_redirection(characters, index, markers)
        elif quote:
            quote = None if character == quote else quote
            hide_redirection(characters, index, markers)
        elif character in QUOTES:
            quote = character
        elif character in REDIRECTION_CHARACTERS:
            start = index
            while start > 0 and command[start - 1].isdigit():
                start -= 1
            if start < index and (start == 0 or command[start - 1] in WORD_BREAKS):
                characters[start:index] = " " * (index - start)
        index += 1
    return "".join(characters)


def is_redirection(token):
    return bool(set(token) & REDIRECTION_CHARACTERS) and set(token) <= set(PUNCTUATION)


def invocations(command):
    command = without_comments(command, drop_bodies=True)
    markers = free_markers(command)
    shown = str.maketrans({hidden: redirection for redirection, hidden in markers.items()})
    text = lexer_ready(command, markers).replace("\n", " ; ")
    lexer = shlex.shlex(text, posix=True, punctuation_chars=PUNCTUATION)
    lexer.whitespace_split = True
    lexer.commenters = ""
    current, found, target_pending = None, [], False
    for token in lexer:
        if target_pending:
            target_pending = False
        elif current is not None and is_redirection(token):
            target_pending = True
        elif token in SEPARATORS or set(token) <= SEPARATOR_CHARACTERS:
            current = None
        elif current is not None:
            current.append(token.translate(shown))
        elif os.path.basename(token) in KILLERS:
            current = [os.path.basename(token)]
            found.append(current)
    return found


def killall_names(arguments):
    names, skip = [], False
    for argument in arguments:
        if skip:
            skip = False
        elif argument in KILLALL_FLAGS_WITH_VALUE:
            skip = True
        elif not argument.startswith("-"):
            names.append(argument)
    return names


def matching_pids(arguments):
    found = subprocess.run([PGREP] + arguments, capture_output=True, text=True)
    if found.returncode not in (PGREP_FOUND, PGREP_NOTHING):
        raise OSError("pgrep could not read the pattern")
    return [int(pid) for pid in found.stdout.split()]


def program_name(pid):
    try:
        with open(PROC_COMMAND_LINE % pid, "rb") as listed:
            first = listed.read().split(b"\0")[0]
    except OSError:
        return None
    return os.path.basename(first.decode(errors="replace")) or None


def killall_pids(name):
    pids = matching_pids(["-x", name])
    if len(name) > LINUX_NAME_WIDTH and os.path.isdir(PROC_ROOT):
        cut = matching_pids(["-x", name[:LINUX_NAME_WIDTH]])
        pids += [pid for pid in cut if program_name(pid) in (name, None)]
    return pids


def invocation_pids(invocation):
    program, arguments = invocation[0], invocation[1:]
    if program == "killall":
        return [pid for name in killall_names(arguments) for pid in killall_pids(name)]
    if arguments and SIGNAL_ARGUMENT.match(arguments[0]):
        arguments = arguments[1:]
    return matching_pids(arguments) if arguments else []


def lsof_folder(pid):
    try:
        listed = subprocess.run([LSOF, "-a", "-p", str(pid), "-d", "cwd", "-Fn"], capture_output=True, text=True)
    except FileNotFoundError:
        return None
    for line in listed.stdout.splitlines():
        if line.startswith("n"):
            folder = os.path.realpath(line[1:])
            return folder if os.path.isdir(folder) else None
    return None


def working_folder(pid):
    proc = PROC_FOLDER % pid
    return lsof_folder(pid) or (os.path.realpath(proc) if os.path.exists(proc) else None)


def is_known_gone(pid):
    if os.name != POSIX:
        return False
    try:
        os.kill(pid, EXISTENCE_PROBE)
    except ProcessLookupError:
        return True
    except PermissionError:
        return False
    return False


def command_line(pid):
    shown = subprocess.run(["ps", "-o", "command=", "-p", str(pid)], capture_output=True, text=True)
    return shown.stdout.strip()[:COMMAND_WIDTH]


def inside(folder, session):
    return folder == session or folder.startswith(session.rstrip(os.sep) + os.sep)


def main():
    session = os.path.realpath(sys.argv[1])
    own, unknown, seen = {os.getpid(), os.getppid()}, False, set()
    for invocation in invocations(sys.stdin.read()):
        for pid in invocation_pids(invocation):
            if pid in own or pid in seen:
                continue
            seen.add(pid)
            folder = working_folder(pid)
            if folder is None:
                unknown = unknown or not is_known_gone(pid)
            elif not inside(folder, session):
                print("%d\t%s\t%s" % (pid, folder, command_line(pid)))
    return PARTLY_MEASURED if unknown else 0


try:
    sys.exit(main())
except (OSError, IndexError, ValueError):
    sys.exit(CANNOT_MEASURE)
PY
)
HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$HOOKS_DIR/shell-text.sh"
"$PYTHON" -c "$SHELL_TEXT_CODE
$CODE" "$@"
