<h1 align="center">Prisma Harness</h1>

<p align="center"><em>Tu agente dice que terminó. PRISMA lo obliga a probarlo, vía por vía, antes de que nada salga de la máquina.</em></p>

<p align="center">
  <img src="https://img.shields.io/badge/funciona%20con-Claude%20Code-111111?style=flat-square" alt="Funciona con Claude Code">
  <img src="https://img.shields.io/badge/modelo-uno%20solo-111111?style=flat-square" alt="Un solo modelo, sin segundo motor">
  <img src="https://img.shields.io/badge/selftests-en%20verde-111111?style=flat-square" alt="Todo hook que decide tiene selftest">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licencia-MIT-111111?style=flat-square" alt="MIT"></a>
</p>

<p align="center"><sub><a href="README.md">English</a> · Español</sub></p>

<p align="center">
  <a href="#instalar"><b>Instalar</b></a> ·
  <a href="docs/es/METHOD.md"><b>El método</b></a> ·
  <a href="docs/es/STYLE.md"><b>Las reglas de escritura</b></a> ·
  <a href="#qué-hay-adentro"><b>Qué hay adentro</b></a> ·
  <a href="#configurar"><b>Configurar</b></a>
</p>

## El problema

Un agente que escribe código escribe también la afirmación de que el código funciona, y un test no puede refutar la premisa que comparte con lo que verifica. Las fallas que llegan a producción son las que nadie miró desde afuera del modelo. PRISMA es un método para mirar desde afuera, y este plugin es la parte que una máquina puede hacer cumplir.

Así se ve dentro de una sesión. El agente intentó escribir una página del wiki sin abrir el índice, y después intentó empujar un diff con un comentario suelto y 1.202 líneas cambiadas.

```
INDEX GATE: you are about to write a page under wiki/ without having opened
index.md in this session. Read <docs root>/index.md first so you do not create
a duplicate page or leave the index stale, then retry.

SIZE GATE: 1202 lines changed, the push is blocked.
Over 1000 lines, defect detection in review drops below half.
```

PRISMA es un método de verificación para el trabajo que produce un agente, y este repositorio es el método empaquetado como plugin de Claude Code. Cinco carriles deciden cuánta verificación necesita un pedido, cinco pasos corren para el código con lógica, y cinco puertas con nombres distintos deciden si el trabajo sale de la máquina. Los hooks frenan lo que el método dice que no debe pasar; la skill corre los pasos; el método escrito dice por qué.

Corre con un solo modelo. No hay segundo motor, ni servicio externo, ni cuenta. El único lugar donde el método nació con dos motores, la réplica ciega, se declara de un solo modelo y dice con claridad lo que eso cuesta.

## Instalar

Dentro de Claude Code, dos comandos. Las actualizaciones llegan con `claude plugin update prisma-harness`, o solas si activas el auto-update de este marketplace en `/plugin`. Una actualización solo se ve cuando cambia la `version` de `plugin.json`, así que cada cambio publicado la sube.

```
/plugin marketplace add juanquijandria/prisma-harness
/plugin install prisma-harness@prisma-harness
```

Los pasos 1 y 2 del método invocan skills del plugin `mattpocock-skills` de Matt Pocock. No están copiadas acá. Instala ese plugin junto a este, o corre la misma secuencia a mano como describe `METHOD.md`.

Requisitos, medidos en macOS el 14/09/2026: `sh`, `bash`, `jq`, `awk`, `cmp`, `git`, y `python3` para el parser de comandos. Linux no está probado todavía.

## Qué hay adentro

| Pieza | Qué hace | Cuándo corre |
|---|---|---|
| `METHOD.md` | el método en inglés, carriles, pasos, puertas, modo de un solo modelo | lo lees |
| `docs/es/METHOD.md` | el bloque canónico en español, la referencia que trae este plugin | `check-canonical-sync.sh` compara tus copias contra él al arrancar la sesión |
| `STYLE.md`, `docs/es/STYLE.md` | las reglas de escritura y cuáles hace cumplir el gate de formato | lo lees |
| `skills/prisma/SKILL.md` | el orden operativo del método, se invoca como `prisma` | cuando dices "PRISMA" |
| `hooks/gate-read-index.sh` | frena una escritura bajo la carpeta de docs si la sesión nunca leyó el índice | `PreToolUse` en Write y Edit |
| `hooks/pre-push-comments.sh` | frena un push o PR cuyo diff agrega comentarios, cifras en comentarios o referencias `archivo:línea` | `PreToolUse` en Bash |
| `hooks/pre-push-size.sh` | avisa sobre 400 líneas cambiadas, frena sobre 1000, y distingue rama vieja de cambio grande | `PreToolUse` en Bash |
| `hooks/pre-push-lint.sh` | corre el linter del propio repo, `php-cs-fixer` o `eslint`, sobre el diff antes del push | `PreToolUse` en Bash |
| `hooks/format-gate.sh` | el gate de formato sobre las páginas tocadas hoy, reglas en `.prisma-format.conf` | `Stop` |
| `hooks/check-canonical-sync.sh` | compara el bloque canónico en toda copia registrada, nunca edita | `SessionStart` |
| `hooks/session-voice.sh` | inyecta las ocho reglas de escritura de `STYLE.md` en cada sesión, así el agente escribe así sin que nadie se lo pida. `PRISMA_VOICE=0` lo apaga | `SessionStart` |
| `hooks/blind-replica.sh` | arma el brief ciego, solo afirmación y fuentes, para la quinta puerta | lo llamas tú |
| `hooks/measure-comments.sh`, `measure-diff-size.sh`, `compare-base.sh`, `command-invokes.sh`, `strip-quotes.sh` | los ayudantes que comparten las puertas | los llaman las puertas |

Los cinco hooks que actúan solos, el gate de índice, el de formato, la sincronía, la réplica ciega y la voz de sesión, tienen `--selftest`, y también el parser de comandos, con 16 casos. Las tres puertas de push se prueban con control positivo y negativo contra un repo de prueba en `tests/push-gates-controls.sh`. `tests/run-selftests.sh` corre todo. Una puerta cuyas pruebas nunca fallan es decoración.

## Configurar

Variables de entorno, todas opcionales. La tabla del `README.md` en inglés las lista con su default; las claves son las mismas. Las tres puertas de push tienen un escape declarado, `PRISMA_COMMENTS_OK=1`, `PRISMA_SIZE_OK=1`, `PRISMA_LINT_OK=1`, puesto delante del comando, y el porqué va en la descripción del cambio. Un escape que se usa por defecto no es una puerta. El gate de índice no tiene escape, leer el índice es el arreglo. El de formato tampoco; una regla que no quieres se apaga en su config.

## Lo que no se toca sin escribir la razón

- **El bloque canónico en `docs/es/METHOD.md`.** Toda copia registrada se compara contra él; editarlo acá hace derivar todas las copias a propósito.
- **Los códigos de salida de una puerta.** Como hook, `0` pasa y `2` frena; una puerta que no puede medir imprime un `WARN` y sale `0`. En la línea de comandos el gate de formato sale `1` con fallas. Una puerta que falla callada fabrica un veredicto.
- **Los selftests.** Cambias una puerta, reintroduces el defecto exacto por el que existe, la ves frenar, lo quitas, la ves pasar. El silencio no prueba nada.

## Cosas que te van a morder

- **Un hook registrado en esta sesión no corre en esta sesión.** La configuración se lee al arrancar. Prueba un hook nuevo en una sesión nueva.
- **`hooks/hooks.json` y `skills/` se cargan por convención.** Nombrarlos otra vez en `plugin.json` hace que Claude Code rechace el plugin como duplicado. Medido el 14/09/2026 instalando desde GitHub, donde la carga local con `--plugin-dir` no se había quejado.
- **La puerta de comentarios salta los archivos cuya extensión no conoce**, y cuenta solo las líneas que tu diff agrega.
- **`--changed` en el gate de formato encuentra páginas modificadas hoy** por fecha de archivo, no por git.
- **El parser de comandos, `command-invokes.sh`, no es un parser de shell.** Respeta comillas, escapes, comentarios y redirecciones, y nunca borra contenido. No resuelve expansiones, alias, `eval` ni globbing. Cuando un comando deja una comilla sin cerrar la lectura es ambigua, y devuelve la UNIÓN de las lecturas plausibles en vez de una sola, así que una puerta puede frenar un comando que no tenía que frenar; el arreglo es partir el comando en dos. Medido el 14/09/2026 sobre 744 comandos reales, 13 traían un número impar de comillas.
- **La puerta de tamaño mide HEAD**, no el ref que empujas. Si empujas otra rama desde `main`, imprime un `WARN` y no mide.

## Dónde se ubica

Quita el modelo del diagrama de un sistema de agentes y lo que queda es el harness, las herramientas, los permisos, el estado y los evaluadores que lo rodean. Prisma Harness vive en esa capa. No es un loop, no reintenta el trabajo hasta que algo pase, y no es un grafo, no decide qué paso corre después. Le da al loop su evidencia y al grafo sus puertas, y solo habla cuando una puerta falla. Los pasos 1 y 2 del método usan las skills de Matt Pocock, la entrevista, la construcción con tests primero y la revisión; los pasos 3, 4 y 5 son la parte donde su flujo termina antes, y la parte por la que existe este harness.

## Lo que Prisma Harness se niega a ser

- **No es un framework de evals.** Sin datasets, sin puntajes, sin dashboards. Cinco puertas con nombre, cada una con el caso que la paga.
- **No es un segundo modelo vigilando al primero.** Corre con un solo modelo y dice en voz alta lo que eso cuesta.
- **No es un revisor de gusto.** El gate de formato lee cómo está escrita una página; nada acá califica la calidad del código.
- **No es silencioso.** Una puerta que no puede medir imprime un aviso. El silencio nunca significa limpio.

## Dónde está el resto

Detrás de cada regla del método hay una falla fechada. Este repositorio trae las reglas; la historia se queda con su autor. Las contribuciones entran con la misma regla que el método se aplica a sí mismo. Un control nuevo entra solo si da rojo sobre un caso real.

Licencia MIT.
