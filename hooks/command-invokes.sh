#!/bin/sh
# Prisma Harness. Documented in README.md, section "command-invokes".

if [ "$1" = "--arguments" ]; then
  MODO=argumentos; shift
else
  MODO=segmentos
fi

PROGRAMA="${1:?program name required}"
SUBCOMANDO="${2:-}"

MODO="$MODO" PROGRAMA="$PROGRAMA" SUBCOMANDO="$SUBCOMANDO" python3 -c '
import io, os, re, shlex, sys

modo = os.environ["MODO"]
programa = os.environ["PROGRAMA"]
subcomando = os.environ["SUBCOMANDO"]
comando = sys.stdin.read()

SEPARADORES_SHLEX = {";", "&", "&&", "|", "||", "(", ")", "{", "}", "\n", "<", ">", ">>"}
SEPARADORES_REGEX = re.compile(r"[;&|\n]+|\)|\(|\{|\}")
ASIGNACION_DE_ENTORNO = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
PALABRAS_DE_CONTROL = {"then", "do", "else", "elif", "fi", "done", "!", "time", "sudo", "command", "exec", "env", "nohup"}


def segmentos_con_shlex(texto):
    lexer = shlex.shlex(io.StringIO(texto), posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    actual, salida = [], []
    for token in lexer:
        if token in SEPARADORES_SHLEX:
            salida.append(actual)
            actual = []
        else:
            actual.append(token)
    salida.append(actual)
    return salida


def segmentos_con_regex(texto):
    sin_citas = re.sub(r"'"'"'[^'"'"']*'"'"'|\"[^\"]*\"", " ", texto)
    return [s.split() for s in SEPARADORES_REGEX.split(sin_citas)]


try:
    segmentos = segmentos_con_shlex(comando)
except ValueError:
    segmentos = segmentos_con_regex(comando)

encontrados = []
for tokens in segmentos:
    tokens = list(tokens)
    while tokens and (ASIGNACION_DE_ENTORNO.match(tokens[0]) or tokens[0] in PALABRAS_DE_CONTROL):
        tokens.pop(0)
    if not tokens:
        continue
    if tokens[0].rsplit("/", 1)[-1] != programa:
        continue
    if not subcomando:
        encontrados.append(tokens)
        continue
    resto = tokens[1:]
    i = 0
    while i < len(resto) and resto[i].startswith("-"):
        toma_valor = resto[i] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path")
        i += 2 if toma_valor else 1
    if i < len(resto) and resto[i] == subcomando:
        encontrados.append(tokens)

for tokens in encontrados:
    if modo == "argumentos":
        for token in tokens[1:]:
            print(token)
    else:
        print(" ".join(tokens))

sys.exit(0 if encontrados else 1)
'
