# Prisma Harness. Documented in README.md, section "What is inside". Loaded by secret-args.sh after shell-text.sh, not run alone.
SECRET_NAMES_CODE=$(cat <<'PY'
import collections
import fnmatch
import re

BLOCK = "block"
REWRITE = "rewrite"
PASS = "pass"
READERS = {"cat", "head", "tail", "less", "more", "bat", "sed", "awk", "xxd", "diff", "strings", "nl"}
SECRET_NAME = re.compile(r"\.env([.*?\[].*)?|.+\.env")
FREE_SUFFIXES = (".example", ".sample", ".template")
GIT = "git"
GIT_SEARCH = "grep"
DASHES = "--"
GIT_GLOBAL_VALUE_FLAGS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
PATTERN_FLAGS = {"-e", "-f", "--regexp", "--file"}
LIST_LONG = {"--files-with-matches", "--files-without-match", "--count", "--quiet", "--silent", "--files", "--count-matches", "--name-only"}
GREP_LIST = {"-l", "-L", "-c", "-q"} | LIST_LONG
RG_LIST = {"-l", "-c", "-q"} | LIST_LONG
GREP_RECURSIVE = {"-r", "-R", "--recursive", "--dereference-recursive"}
ALWAYS_RECURSIVE = None
GREP_EXCLUSION = "--exclude='.env*' --exclude='*.env'"
RG_EXCLUSION = "-g '!.env*' -g '!*.env'"
PATHSPEC_EXCLUSION = "':(exclude,glob)**/.env*' ':(exclude,glob)**/*.env'"

Grammar = collections.namedtuple("Grammar", "lists value_short value_long recursive")
GREP = Grammar(GREP_LIST, set("efmABCdD"), {
    "--regexp", "--file", "--max-count", "--after-context", "--before-context", "--context", "--include",
    "--exclude", "--exclude-dir", "--exclude-from", "--binary-files", "--label", "--devices", "--directories",
}, GREP_RECURSIVE)
RIPGREP = Grammar(RG_LIST, set("efgmABCMjtTEdr"), {
    "--regexp", "--file", "--glob", "--iglob", "--type", "--type-not", "--type-add", "--max-count",
    "--after-context", "--before-context", "--context", "--replace", "--encoding", "--max-columns", "--threads",
    "--sort", "--sortr", "--pre", "--pre-glob", "--max-depth", "--max-filesize", "--ignore-file", "--engine",
}, ALWAYS_RECURSIVE)
INCLUDE_FLAGS = {"--include", "-g", "--glob", "--iglob"}
NEGATED_GLOB = "!"
GLOB_CHARACTERS = set("*?[")
ENV_PART = "env"
SECRET_SAMPLES = (".env", ".env.local", "prod.env")
GIT_GREP = Grammar(GREP_LIST, set("efABCm"), {"--max-depth", "--threads"}, ALWAYS_RECURSIVE)
GIT_PATCHES = {"diff", "show", "log"}
GIT_LOG = "log"
PATCH_FLAGS = {"-p", "-u", "--patch"}
NAME_ONLY_FLAGS = {"--name-only", "--name-status", "--stat", "--numstat", "--shortstat", "--quiet"}
GIT_PATCH_VALUES = {"--author", "--committer", "--grep", "--since", "--until", "--after", "--before", "--skip", "--max-count"}
GIT_PATCH = Grammar(set(), set("nSGOL"), GIT_PATCH_VALUES, ALWAYS_RECURSIVE)
SEARCHERS = {"grep": GREP, "egrep": GREP, "fgrep": GREP, "rg": RIPGREP}
EXCLUSION_AFTER_PROGRAM = {**dict.fromkeys(("grep", "egrep", "fgrep"), GREP_EXCLUSION), "rg": RG_EXCLUSION}
XARGS = "xargs"
FIND = "find"
FIND_ACTIONS = {"-exec", "-execdir", "-ok", "-okdir"}
FIND_ACTION_ENDS = {";", "+"}
XARGS_OPTIONS = Grammar(set(), set("IndPLsEaJR"), {"--max-args", "--max-procs", "--delimiter", "--arg-file"}, ALWAYS_RECURSIVE)
COMMAND_SEPARATORS = ";|&\n()"
REDIRECTIONS = "<>"
BLANKS = " \t\r"
ARGUMENT_ENDS = BLANKS + COMMAND_SEPARATORS + REDIRECTIONS
DOUBLE_QUOTE = "\""

def is_secret(path):
    name = path.rstrip("/").rsplit("/", 1)[-1]
    return bool(SECRET_NAME.fullmatch(name)) and not name.endswith(FREE_SUFFIXES)


def names_secrets(word):
    name = word.rstrip("/").rsplit("/", 1)[-1]
    if GLOB_CHARACTERS & set(name) and ENV_PART in name:
        return reaches_secrets(name)
    return is_secret(word)


def short_cluster(arg, value_short):
    flags = []
    for index, letter in enumerate(arg[1:]):
        flags.append("-" + letter)
        if letter in value_short:
            return flags, arg[index + 2:] or None
    return flags, ""


def option_value(args, index, attached):
    if attached is None:
        return args[index + 1] if index + 1 < len(args) else "", 1
    return attached, 0


def long_option(arg, value_long):
    name, equals, attached = arg.partition("=")
    if equals:
        return name, attached
    return name, None if name in value_long else ""


def parse_options(args, grammar):
    flags, operands, values, index, after_dashes = [], [], [], 0, False
    while index < len(args):
        arg = args[index]
        if after_dashes or arg == "-" or not arg.startswith("-"):
            operands.append(arg)
        elif arg == DASHES:
            after_dashes = True
        else:
            if arg.startswith(DASHES):
                name, attached = long_option(arg, grammar.value_long)
                flags.append(name)
            else:
                cluster, attached = short_cluster(arg, grammar.value_short)
                flags.extend(cluster)
                name = cluster[-1]
            value, consumed = option_value(args, index, attached)
            values.append((name, value))
            index += consumed
        index += 1
    return set(flags), operands, values


def reaches_secrets(glob):
    pattern = glob.rsplit("/", 1)[-1]
    return not glob.startswith(NEGATED_GLOB) and any(fnmatch.fnmatchcase(name, pattern) for name in SECRET_SAMPLES)


def includes_secrets(values):
    return any(flag in INCLUDE_FLAGS and reaches_secrets(value) for flag, value in values)


def revision_path(operand):
    return operand.split(":", 1)[-1]


def classify_search(args, grammar):
    flags, operands, values = parse_options(args, grammar)
    paths = operands if flags & PATTERN_FLAGS else operands[1:]
    if flags & grammar.lists:
        return PASS
    if any(names_secrets(revision_path(path)) for path in paths) or includes_secrets(values):
        return BLOCK
    if grammar.recursive is ALWAYS_RECURSIVE or flags & grammar.recursive:
        return REWRITE
    return PASS


def git_subcommand(args):
    index = 0
    while index < len(args) and args[index].startswith("-"):
        index += 2 if args[index] in GIT_GLOBAL_VALUE_FLAGS else 1
    return (args[index], args[index + 1:]) if index < len(args) else ("", [])


def classify_patch(subcommand, args):
    flags, operands, _ = parse_options(args, GIT_PATCH)
    prints_patch = bool(flags & PATCH_FLAGS) or subcommand != GIT_LOG
    names_only = bool(flags & NAME_ONLY_FLAGS) and not flags & PATCH_FLAGS
    if not prints_patch or names_only:
        return PASS
    if any(names_secrets(revision_path(operand)) for operand in operands):
        return BLOCK
    return REWRITE


def classify_git(args):
    subcommand, rest = git_subcommand(args)
    if subcommand == GIT_SEARCH:
        return classify_search(rest, GIT_GREP)
    if subcommand in GIT_PATCHES:
        return classify_patch(subcommand, rest)
    return PASS


def program_name(word):
    return word.rsplit("/", 1)[-1]


def xargs_command(args):
    index = 0
    while index < len(args) and args[index].startswith("-"):
        if args[index].startswith(DASHES):
            attached = long_option(args[index], XARGS_OPTIONS.value_long)[1]
        else:
            attached = short_cluster(args[index], XARGS_OPTIONS.value_short)[1]
        index += 1 + option_value(args, index, attached)[1]
    return args[index:]


def find_commands(args):
    commands, current = [], None
    for arg in args:
        if arg in FIND_ACTIONS:
            current = []
            commands.append(current)
        elif arg in FIND_ACTION_ENDS:
            current = None
        elif current is not None:
            current.append(arg)
    return commands


def prints_lines(tokens):
    program, args = program_name(tokens[0]), tokens[1:]
    if program in SEARCHERS:
        return not parse_options(args, SEARCHERS[program])[0] & SEARCHERS[program].lists
    return program in READERS


def classify_runner(nested, mentions):
    if nested and (classify(nested) == BLOCK or (mentions and prints_lines(nested))):
        return BLOCK
    return PASS


def classify(tokens, mentions=False):
    program, args = program_name(tokens[0]), tokens[1:]
    if program in READERS and any(names_secrets(arg) for arg in args if not arg.startswith("-")):
        return BLOCK
    if program in SEARCHERS:
        return classify_search(args, SEARCHERS[program])
    if program == GIT:
        return classify_git(args)
    if program == XARGS:
        return classify_runner(xargs_command(args), mentions)
    if program == FIND:
        verdicts = [classify_runner(nested, mentions) for nested in find_commands(args)]
        return BLOCK if BLOCK in verdicts else PASS
    return PASS


class Unreadable(Exception):
    pass


def read_quoted(text, index):
    quote, index, value = text[index], index + 1, []
    while index < len(text) and text[index] != quote:
        if text[index] == BACKSLASH and quote == DOUBLE_QUOTE and index + 1 < len(text):
            index += 1
        value.append(text[index])
        index += 1
    if index >= len(text):
        raise Unreadable()
    return "".join(value), index + 1


def read_word(text, index):
    value = []
    while index < len(text) and text[index] not in ARGUMENT_ENDS:
        if text[index] in QUOTES:
            part, index = read_quoted(text, index)
            value.append(part)
        elif text[index] == BACKSLASH:
            value.append(text[index + 1:index + 2])
            index += 2
        else:
            value.append(text[index])
            index += 1
    return "".join(value), index
PY
)
