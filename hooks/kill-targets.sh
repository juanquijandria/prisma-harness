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
KILLALL_FLAGS_WITH_VALUE = {"-u", "-t", "-c", "-s"}
COMMAND_WIDTH = 80
LSOF = os.environ.get("PRISMA_LSOF") or "lsof"


def invocations(command):
    lexer = shlex.shlex(command.replace("\n", " ; "), posix=True, punctuation_chars=";&|()")
    lexer.whitespace_split = True
    lexer.commenters = "#"
    current, found = None, []
    for token in lexer:
        if token in SEPARATORS or set(token) <= set(";&|()"):
            current = None
        elif current is not None:
            current.append(token)
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


def pgrep_calls(invocation):
    program, arguments = invocation[0], invocation[1:]
    if program == "killall":
        return [["-x", name] for name in killall_names(arguments)]
    if arguments and SIGNAL_ARGUMENT.match(arguments[0]):
        arguments = arguments[1:]
    return [arguments] if arguments else []


def matching_pids(arguments):
    found = subprocess.run(["pgrep"] + arguments, capture_output=True, text=True)
    if found.returncode not in (PGREP_FOUND, PGREP_NOTHING):
        raise OSError("pgrep could not read the pattern")
    return [int(pid) for pid in found.stdout.split()]


def working_folder(pid):
    listed = subprocess.run([LSOF, "-a", "-p", str(pid), "-d", "cwd", "-Fn"], capture_output=True, text=True)
    for line in listed.stdout.splitlines():
        if line.startswith("n"):
            return os.path.realpath(line[1:])
    proc = "/proc/%d/cwd" % pid
    return os.path.realpath(proc) if os.path.exists(proc) else None


def command_line(pid):
    shown = subprocess.run(["ps", "-o", "command=", "-p", str(pid)], capture_output=True, text=True)
    return shown.stdout.strip()[:COMMAND_WIDTH]


def inside(folder, session):
    return folder == session or folder.startswith(session.rstrip(os.sep) + os.sep)


def main():
    session = os.path.realpath(sys.argv[1])
    own, unknown, seen = {os.getpid(), os.getppid()}, False, set()
    for invocation in invocations(sys.stdin.read()):
        for arguments in pgrep_calls(invocation):
            for pid in matching_pids(arguments):
                if pid in own or pid in seen:
                    continue
                seen.add(pid)
                folder = working_folder(pid)
                if folder is None:
                    unknown = True
                elif not inside(folder, session):
                    print("%d\t%s\t%s" % (pid, folder, command_line(pid)))
    return PARTLY_MEASURED if unknown else 0


try:
    sys.exit(main())
except (OSError, IndexError, ValueError):
    sys.exit(CANNOT_MEASURE)
PY
)
"$PYTHON" -c "$CODE" "$@"
