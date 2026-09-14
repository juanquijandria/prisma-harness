#!/bin/sh
# Prisma Harness. Documented in README.md, section "command-invokes".

YO_MISMO=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")

if [ "$1" = "--selftest" ]; then
  ok=1
  caso() {
    if [ "$2" = "$3" ]; then echo "PASS caso $1"; else echo "FAIL caso $1, esperaba [$3] y dio [$2]"; ok=0; fi
  }
  RUTAS="inbox/Reunion HI LUCA 1 DE 5
raw/x"
  simple='mv "inbox/Reunion HI LUCA 1 DE 5" raw/x'
  heredoc="mv \"inbox/Reunion HI LUCA 1 DE 5\" raw/x && cat >> log.md <<'EOF'
el clip de O'Reilly
EOF"
  segundo_mv="cat >> log.md <<'EOF'
el clip de O'Reilly
EOF
mv \"inbox/Reunion HI LUCA 1 DE 5\" raw/x"
  caso "1 comillas balanceadas" "$(printf '%s' "$simple" | "$YO_MISMO" --arguments mv)" "$RUTAS"
  caso "2 APOSTROFO en heredoc, el origen no se pierde" "$(printf '%s' "$heredoc" | "$YO_MISMO" --arguments mv)" "$RUTAS"
  caso "3 APOSTROFO antes del mv, se detecta igual" "$(printf '%s' "$segundo_mv" | "$YO_MISMO" --arguments mv)" "$RUTAS"
  caso "4 el comando entrecomillado no es invocacion" "$(printf '%s' 'echo "mv inbox/a raw/x"' | "$YO_MISMO" --arguments mv; echo "exit=$?")" "exit=1"
  caso "5 separador real parte el comando" "$(printf '%s' 'ls; mv "inbox/Reunion HI LUCA 1 DE 5" raw/x' | "$YO_MISMO" --arguments mv)" "$RUTAS"
  caso "6 asignacion de entorno antes del programa" "$(printf '%s' 'IMAGENES="3 informativas, 0 referenciales" mv "inbox/Reunion HI LUCA 1 DE 5" raw/x' | "$YO_MISMO" --arguments mv)" "$RUTAS"
  caso "7 separador dentro de comillas no parte" "$(printf '%s' 'git commit -m "no toca; mv a b"' | "$YO_MISMO" --arguments mv; echo "exit=$?")" "exit=1"
  caso "8 subcomando con flags que toman valor" "$(printf '%s' 'git -C /tmp push origin main' | "$YO_MISMO" git push)" "git -C /tmp push origin main"
  caso "9 comentario al final" "$(printf '%s' 'mv "inbox/Reunion HI LUCA 1 DE 5" raw/x # nota' | "$YO_MISMO" --arguments mv)" "$RUTAS"
  caso "10 programa ausente" "$(printf '%s' 'ls -la' | "$YO_MISMO" --arguments mv; echo "exit=$?")" "exit=1"
  apostrofos_alrededor="cat >/dev/null <<'A'
x'y
A
mv \"inbox/Reunion HI LUCA 1 DE 5\" raw/x
cat >/dev/null <<B
close'
unmatched'
B"
  caso "11 APOSTROFOS que encierran al mv, se detecta igual" "$(printf '%s' "$apostrofos_alrededor" | "$YO_MISMO" --arguments mv)" "$RUTAS"
  caso "12 REDIRECCION antes del programa, se detecta igual" "$(printf '%s' '>/dev/null mv "inbox/Reunion HI LUCA 1 DE 5" raw/x' | "$YO_MISMO" --arguments mv)" "$RUTAS"
  caso "13 el destino de una redireccion no es un programa" "$(printf '%s' 'echo hola > mv' | "$YO_MISMO" --arguments mv; echo "exit=$?")" "exit=1"
  caso "14 redireccion despues de los argumentos" "$(printf '%s' 'mv "inbox/Reunion HI LUCA 1 DE 5" raw/x >/dev/null' | "$YO_MISMO" --arguments mv)" "$RUTAS"
  [ "$ok" = "1" ] && echo "SELFTEST OK" && exit 0
  echo "SELFTEST FALLIDO"; exit 1
fi

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
REDIRECCIONES = {"<", ">", ">>", "<<", "<<<", ">&", "&>", ">|"}
SEPARADORES_A_MANO = ";&|\n(){}<>"
REDIRECCIONES_A_MANO = "<>"
COMILLAS = "\"'"'"'"
ESPACIOS = " \t\r"
ASIGNACION_DE_ENTORNO = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
PALABRAS_DE_CONTROL = {"then", "do", "else", "elif", "fi", "done", "!", "time", "sudo", "command", "exec", "env", "nohup"}


def segmentos_con_shlex(texto):
    lexer = shlex.shlex(io.StringIO(texto), posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    actual, salida, saltar = [], [], False
    for token in lexer:
        if saltar:
            saltar = False
        elif token in REDIRECCIONES:
            saltar = True
        elif token in SEPARADORES_SHLEX:
            salida.append(actual)
            actual = []
        else:
            actual.append(token)
    salida.append(actual)
    return salida


def segmentos_a_mano(texto, comillas=COMILLAS):
    salida, actual, token = [], [], ""
    comilla, i, saltar = None, 0, False
    while i < len(texto):
        caracter = texto[i]
        if comilla:
            if caracter == comilla:
                comilla = None
            elif caracter == "\\" and comilla == "\"" and i + 1 < len(texto):
                i += 1
                token += texto[i]
            else:
                token += caracter
        elif caracter in comillas:
            comilla = caracter
        elif caracter == "\\" and i + 1 < len(texto):
            i += 1
            token += texto[i]
        elif caracter == "#" and not token:
            while i < len(texto) and texto[i] != "\n":
                i += 1
            continue
        elif caracter in ESPACIOS:
            if token:
                if saltar:
                    saltar = False
                else:
                    actual.append(token)
                token = ""
        elif caracter in SEPARADORES_A_MANO:
            if token:
                if saltar:
                    saltar = False
                else:
                    actual.append(token)
                token = ""
            if caracter in REDIRECCIONES_A_MANO:
                saltar = True
            else:
                salida.append(actual)
                actual = []
        else:
            token += caracter
        i += 1
    if token and not saltar:
        actual.append(token)
    salida.append(actual)
    if comilla:
        salida.extend(segmentos_a_mano(texto, comillas.replace(comilla, "")))
    return salida


try:
    segmentos = segmentos_con_shlex(comando)
except ValueError:
    segmentos = segmentos_a_mano(comando)

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

unicos, vistos = [], set()
for tokens in encontrados:
    clave = tuple(tokens)
    if clave not in vistos:
        vistos.add(clave)
        unicos.append(tokens)

for tokens in unicos:
    if modo == "argumentos":
        for token in tokens[1:]:
            print(token)
    else:
        print(" ".join(tokens))

sys.exit(0 if encontrados else 1)
'
