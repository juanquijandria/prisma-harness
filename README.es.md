<p align="center"><img src="assets/prisma.svg" width="180" alt="A pentagonal prism"></p>

<h1 align="center">Prisma Harness</h1>

<p align="center"><em>Un prisma parte una luz en vías separadas. PRISMA toma una afirmación y la fuerza por rutas independientes hasta que sobrevive o se cae.</em></p>

<p align="center">
  <img src="https://img.shields.io/badge/funciona%20con-Claude%20Code-111111?style=flat-square" alt="Funciona con Claude Code">
  <img src="https://img.shields.io/badge/modelo-uno%20solo-111111?style=flat-square" alt="Un solo modelo, sin segundo motor">
  <a href="https://github.com/juanquijandria/prisma-harness/actions/workflows/selftests.yml"><img src="https://github.com/juanquijandria/prisma-harness/actions/workflows/selftests.yml/badge.svg" alt="selftests en Ubuntu, macOS y Windows"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/licencia-MIT-111111?style=flat-square" alt="MIT"></a>
</p>

<p align="center"><sub><a href="README.md">English</a> · Español</sub></p>

<p align="center">
  <a href="#instalar"><b>Instalar</b></a> ·
  <a href="docs/es/METHOD.md"><b>El método</b></a> ·
  <a href="docs/es/STYLE.md"><b>Las reglas de escritura</b></a> ·
  <a href="#cómo-lo-usa-una-persona"><b>Cómo se usa</b></a> ·
  <a href="#configurar"><b>Configurar</b></a>
</p>

## Por qué existe

Un agente escribe el código y escribe también la afirmación de que el código funciona. Elige los tests, lee su salida y decide que pasaron. De ese círculo no se sale desde adentro, porque un test no puede refutar la premisa que comparte con lo que verifica. Las fallas que llegan a producción son justo aquellas en las que todos los chequeos estuvieron de acuerdo, y el verde casi siempre significa que ninguno cubría lo que se rompió.

PRISMA agrega los chequeos que un agente no puede darse a sí mismo. Puertas que frenan de forma mecánica antes de un push, un paso que obliga a mirar la superficie real, un refutador cuyo trabajo es tumbar el hallazgo, y una réplica ciega que recibe la afirmación y las fuentes pero nunca el razonamiento. Cada regla del método la pagó una falla real, y una nueva entra solo si da rojo sobre el caso que la paga.

Así se ve dentro de una sesión. El agente intentó escribir una página de documentación sin abrir el índice, y después intentó empujar un cambio de 1.202 líneas.

```
INDEX GATE: you are about to write a page under wiki/ without having opened
index.md in this session. Read <docs root>/index.md first so you do not create
a duplicate page or leave the index stale, then retry.

SIZE GATE: 1202 lines changed, the push is blocked.
This repository blocks a push over 400 changed lines and warns
over 200. Reviewers stop finding things long before they finish reading.
```

PRISMA es un método de verificación para el trabajo que produce un agente, y este repositorio es el método empaquetado como plugin de Claude Code. Cinco carriles deciden cuánta verificación necesita un pedido, cinco pasos corren para el código con lógica, y cinco puertas con nombres distintos deciden si el trabajo sale de la máquina. Los hooks frenan lo que el método dice que no debe pasar; las skills corren los pasos; el método escrito dice por qué.

Corre con un solo modelo. No hay segundo motor, ni servicio externo, ni cuenta. El único lugar donde el método nació con dos motores, la réplica ciega, se declara de un solo modelo y dice con claridad lo que eso cuesta.

## El método en un dibujo

![PRISMA: primero se rutea a uno de cinco carriles; el código con lógica corre cinco pasos por cuatro carriles de actor, la persona, el agente, las puertas y la réplica ciega; cinco puertas cruzan carriles y frenan](assets/method-map.png)

Tres reglas valen sobre todos los carriles y no son un paso más.

1. Toda afirmación es hipótesis hasta que se mida por una vía independiente.
2. El instrumento se calibra en el corpus real, y quien calibra dice qué no probó.
3. Una línea entra al método solo si da rojo sobre su caso histórico.

El orden que sigue el agente está escrito, no dibujado. Vive en `docs/es/METHOD.md` y en `skills/prisma/SKILL.md`, que es lo que corre cuando dices PRISMA, con las cuatro skills de los pasos al lado. El dibujo está en inglés.

## Cómo lo usa una persona

1. **Instala una vez**, los dos comandos de abajo. No hay un segundo plugin que instalar.
2. **Abre una sesión nueva y trabaja como siempre.** No llamas a nada. Las puertas corren solas y hablan solo cuando algo está mal. Una escritura en tus docs sin abrir el índice se frena y el agente recibe qué leer. Un push con comentarios sueltos, con más de cuatrocientas líneas cambiadas o con el linter en rojo se frena y el agente recibe qué hacer. Una página con em-dash o voseo no deja que el agente cierre el turno hasta arreglarla. Las reglas de escritura llegan al arrancar la sesión, así que el agente escribe así sin que se lo pidas.
3. **Di "PRISMA"** cuando quieras el método entero sobre un trabajo. Es lo único que se llama. La skill rutea el pedido por los cinco carriles y corre lo que piden, hasta los cinco pasos y las cinco puertas.
4. **Lee `docs/es/METHOD.md`** cuando quieras saber por qué una puerta hizo lo que hizo.
5. **Actualiza** con los comandos de la sección siguiente, o enciende una vez el auto-update de este marketplace en `/plugin` y olvídate.

## Instalar

Primero las dos herramientas que las puertas necesitan, en tu terminal. Sáltate esto si ya las tienes.

```
brew install jq python
```

```
sudo apt install jq python3
```

Después, dentro de Claude Code, dos comandos.

```
/plugin marketplace add juanquijandria/prisma-harness
/plugin install prisma-harness@prisma-harness
```

Para actualizar, corre esto en tu terminal y abre una sesión nueva.

```
claude plugin marketplace update
claude plugin update prisma-harness@prisma-harness
```

Para no pensar más en eso, abre `/plugin` dentro de Claude Code, entra a Marketplaces, elige `prisma-harness` y enciende auto-update.

Requisitos: `jq`, `python3` o `python`, `git`, `awk`, `cmp`, `bash`, `mktemp`, `find`, `sed`. Si falta alguno, PRISMA te lo dice al arrancar la sesión con el comando para instalarlo, y pregunta antes de instalar nada.

Todos los selftests y los controles de las puertas de push corren en GitHub Actions en Ubuntu, macOS y Windows con Git Bash, en cada push. La insignia de arriba es esa corrida. En Windows, Claude Code necesita Git for Windows para que los hooks corran bajo Git Bash, y la primera corrida en Windows cazó dos cosas ya arregladas, Python escribiendo CRLF en la salida del parser y `python` como único nombre disponible. Instala las herramientas con `winget install jqlang.jq Python.Python.3.12`. WSL 2 se comporta como Linux.

## Qué hay adentro

| Pieza | Qué hace | Cuándo corre |
|---|---|---|
| `METHOD.md` | el método en inglés, carriles, pasos, puertas, modo de un solo modelo | lo lees |
| `docs/es/METHOD.md` | el bloque canónico en español, la referencia que trae este plugin | `check-canonical-sync.sh` compara tus copias contra él al arrancar la sesión |
| `STYLE.md`, `docs/es/STYLE.md` | las reglas de escritura y cuáles hace cumplir el gate de formato | lo lees |
| `skills/prisma/SKILL.md` | el orden operativo del método, se invoca como `prisma` | cuando dices "PRISMA" |
| `skills/prisma-plan/SKILL.md` | el paso 1, la entrevista en rondas que deja registro y cierra con el carril y la estimación de sesión | cuando `prisma` llega al paso 1 |
| `skills/prisma-build/SKILL.md` | el paso 2, tests primero en los seams acordados, cada control visto en rojo antes del código, después la revisión, después el commit | cuando `prisma` llega al paso 2 |
| `skills/prisma-fidelity-review/SKILL.md` | el revisor de fidelidad, dos ejes separados, corre en un subagente limpio contra el registro del plan | cuando `prisma-build` llega a su revisión, o cuando pides una revisión |
| `skills/prisma-diagnose/SKILL.md` | el paso 2b, el loop antes de la hipótesis, y al final el paso del que se escapó el defecto | cuando algo está roto |
| `hooks/gate-read-index.sh` | frena una escritura bajo la carpeta de docs si la sesión nunca leyó el índice | `PreToolUse` en Write y Edit |
| `hooks/pre-push-comments.sh` | frena un push o PR cuyo diff agrega comentarios, cifras en comentarios o referencias `archivo:línea` | `PreToolUse` en Bash |
| `hooks/pre-push-size.sh` | avisa sobre 200 líneas cambiadas, frena sobre 400, y distingue rama vieja de cambio grande | `PreToolUse` en Bash |
| `hooks/pre-push-lint.sh` | corre el linter del propio repo, `php-cs-fixer` o `eslint`, sobre el diff antes del push | `PreToolUse` en Bash |
| `hooks/format-gate.sh` | el gate de formato sobre las páginas tocadas hoy, reglas en `.prisma-format.conf` | `Stop` |
| `hooks/check-canonical-sync.sh` | compara el bloque canónico en toda copia registrada, nunca edita | `SessionStart` |
| `hooks/session-voice.sh` | inyecta las reglas de escritura de `STYLE.md` en cada sesión, así el agente escribe así sin que nadie se lo pida. Lo avisa una vez por proyecto y `PRISMA_VOICE=0` lo apaga | `SessionStart` |
| `hooks/session-deps.sh` | al arrancar la sesión, le dice al agente qué herramientas o qué plugin faltan, con el comando para instalarlos, y que pregunte antes de instalar. Calla cuando no falta nada. `PRISMA_DEPS_CHECK=0` lo apaga | `SessionStart` |
| `hooks/notes-machinery.sh` | reporta un repositorio de git, un manifiesto de paquete, una carpeta de módulos o un entorno virtual metidos dentro de un árbol que guarda información y no código. Necesita `PRISMA_NOTES_ROOT`, y sin eso el chequeo no aplica | `SessionStart` y `Stop` |
| `hooks/blind-replica.sh` | arma el brief ciego, solo afirmación y fuentes, para la quinta puerta, y con un auditor configurado su código de salida es el veredicto | lo llamas tú |
| `hooks/receipt.sh` | una línea local por freno, escape, aviso o puerta que no pudo medir, y un resumen que pegas a quien lo pida | lo escriben las puertas, lo lees tú |
| `hooks/measure-comments.sh`, `measure-diff-size.sh`, `compare-base.sh`, `command-invokes.sh`, `strip-quotes.sh`, `escape-declared.sh` | los ayudantes que comparten las puertas | los llaman las puertas |

Diez piezas tienen `--selftest`, el gate de índice, el de formato, la sincronía, la réplica ciega, la voz de sesión, el chequeo de dependencia, el recibo, el detector de maquinaria, el parser de comandos y el parser del escape. Las tres puertas de push están cubiertas por 52 controles contra un repositorio de prueba en `tests/push-gates-controls.sh`, que frenan un defecto real y después dejan pasar el diff corregido. `tests/push-gates-never-fabricate.sh`, `tests/page-gates-never-fabricate.sh` y `tests/page-gates-receipts.sh` suman 62 más sobre lo que reporta una puerta cuando no midió, que nunca reporta un veredicto y que deja su línea en el recibo, y cada uno estuvo rojo antes del cambio que lo puso verde, salvo dos contraejemplos de la suite de recibos que tienen que quedarse callados y ya lo estaban. `tests/skills-controls.sh` suma 17 sobre el texto de las cuatro skills de paso, siete de ellos sobre copias mutadas que tienen que ponerse rojas. `tests/runner-controls.sh` suma 20 sobre la suite misma, corridos desde afuera porque un corredor no puede correrse a sí mismo. `tests/run-selftests.sh` corre todo eso, comprueba que las páginas que este repositorio publica cumplen las reglas que este repositorio propone, y compara cuántos casos declara cada selftest contra cuántos imprimió de verdad, porque una suite en verde no prueba que cada caso corrió, y una suite que no imprime conteo falla. La suite propia del gate de formato en `hooks/format-gate.sh`, la más grande con 42 casos, quedó fuera de esa comparación hasta 0.6.0 porque su línea de cierre no llevaba número. Una puerta cuyas pruebas nunca fallan es decoración.

## Las reglas de escritura, y cómo apagarlas

Este plugin pone reglas de escritura al inicio de cada sesión, y lo avisa en la primera sesión de cada proyecto. Si quieres la verificación y no el estilo de prosa, pon esto en tu configuración de Claude Code.

```json
{ "env": { "PRISMA_VOICE": "0" } }
```

O díselo a tu agente con tus palabras, que es más corto.

```
Apaga las reglas de escritura de PRISMA en este proyecto.
```

## Dos cosas que se leen más pesadas de lo que son

**Algo roto no pasa por la entrevista.** `skills/prisma-diagnose/SKILL.md` tiene su propio disparador y no pide registro de plan. El paso 1 es para trabajo que se está decidiendo, no para un defecto que se está reproduciendo.

**La puerta de comentarios no frena hasta que se lo pidas.** Recién instalada mide el diff y dice qué encontró. `PRISMA_COMMENTS_BLOCK=1` convierte esa medición en un freno.

## Qué se hace cumplir, y quién

"Pasó PRISMA" significa tres cosas distintas según la promesa, y esta tabla dice cuál. Un hook frena solo. Al agente se le pide, y el transcript y el recibo son la evidencia. Una persona, o evidencia de fuera de la máquina, decide el resto. Nada del tercer tipo lo hace cumplir este repositorio, y decirlo es el punto. Las puertas de push miden el HEAD activo contra su base, así que una rama empujada desde otro lado no se mide y la puerta lo dice, y un repositorio listado en `PRISMA_SKIP_REPOS` nunca se mide.

| Promesa | La sostiene | Cómo lo sabes |
|---|---|---|
| ninguna página bajo el directorio de docs se escribe **con Write o Edit** sin leer el índice | hook | el gate de índice frena, y no tiene escape. Una página escrita por un comando de shell queda fuera |
| ningún push de un repositorio vigilado lleva líneas de comentario, cifras en comentarios ni referencias de archivo y línea | hook | la puerta de comentarios frena el HEAD, y un escape queda en el recibo |
| ningún push de un repositorio vigilado pasa el techo de tamaño | hook | la puerta de tamaño frena el HEAD, y un escape queda en el recibo |
| un push de un repositorio vigilado pasa su propio linter | hook | la puerta de lint frena el HEAD, y un escape queda en el recibo |
| una página tocada hoy cumple las reglas de escritura | hook | el gate de formato frena el cierre, y una regla se apaga en la config |
| el bloque canónico coincide con toda copia registrada | agente | la sincronía reporta la deriva al arrancar y nunca frena |
| los cinco pasos corren para código con lógica | agente | la skill los ordena, y el transcript muestra si corrieron |
| un hallazgo se reproduce antes de repetirse como hecho | agente | el transcript |
| una cifra se mide por una segunda vía | agente | `blind-replica.sh` arma el brief y lee el veredicto, y no juzga su verdad |
| el resultado se miró en la superficie que ve una persona | persona | el paso 3, y nadie más puede hacerlo |
| la condición de salida se cumple donde cayó el trabajo | evidencia externa | el paso 5, sobre la fuente real |
| las puertas reducen los defectos escapados | evidencia externa | el recibo cuenta frenos, no si cada freno tenía razón |

## Configurar

Variables de entorno, todas opcionales. La tabla del `README.md` en inglés las lista con su default; las claves son las mismas. Las tres puertas de push tienen un escape declarado, `PRISMA_COMMENTS_OK=1`, `PRISMA_SIZE_OK=1`, `PRISMA_LINT_OK=1`, puesto delante del comando, y el porqué va en la descripción del cambio. Un escape que se usa por defecto no es una puerta. El gate de índice no tiene escape, leer el índice es el arreglo. El de formato tampoco; una regla que no quieres se apaga en su config.

**De dónde salen 200 y 400.** Son la política de este repositorio, y toman su forma de una sola fuente, [un caso de diez meses sobre 2.500 revisiones](https://static1.smartbear.co/support/media/resources/cc/book/code-review-cisco-case-study.pdf) en un solo grupo de producto de Cisco, hecho y escrito en 2006 por el proveedor de la herramienta de revisión que midió. Su conclusión es que las líneas bajo revisión deben quedar bajo 200 y no pasar de 400.

Léelo antes de confiar en los defaults, porque el número solo esconde lo que el estudio dice de sí mismo. Sus conteos de defectos salen de una muestra de 300 de esas revisiones codificada a mano, no de las 2.500. Aparta una quinta parte de las revisiones por poco interesantes. Su propia nota al pie declara la premisa sobre la que se apoya todo, que la densidad real de defectos es constante entre cambios grandes y chicos. Su consejo resumido es más estrecho que el punto que estos defaults siguen, entre 100 y 300 líneas por vez. Y nunca dice si sus líneas bajo revisión son las líneas que cuenta un diff, que es lo que esta puerta mide.

Esa es la única afirmación que este repositorio hace sobre la literatura. No dice haberla leído toda, y dos versiones anteriores de este párrafo fueron refutadas por una réplica ciega que recibió las fuentes y nada del razonamiento. La primera citaba un techo de 1000 que no se rastreaba a ninguna fuente. La segunda decía que los datos de Cisco son C y C++, que el estudio nunca dice. Los números de acá son tuyos para cambiarlos, y la puerta imprime la política y nunca el estudio.

## El recibo

Cada vez que una puerta frena algo, alguien la pasa con el escape, mide algo que no le pidieron frenar, o no puede medir, cae una línea en `~/.prisma-harness/receipts.log` con la fecha y hora, la puerta, el repositorio, y cuál de las cuatro fue. El resumen las cuenta en columnas separadas, porque una puerta que no pudo medir no aprobó nada. Nada más, y nunca sale de tu máquina salvo que lo pegues. Los hooks que corren dentro de Claude Code y el comando que corres en la terminal leen y escriben ese mismo archivo, a propósito.

```
sh hooks/receipt.sh --summary
```

Eso imprime una fila por puerta con frenos, escapes y el primer y último día, lista para pegar en un chat. Así sabes qué puertas cazan cosas en tu trabajo y cuáles nunca disparan, y es lo que le mandas a quien lleve PRISMA para un equipo. Cuenta frenos, no si cada freno tenía razón, y no ve lo que ninguna puerta cazó. `PRISMA_RECEIPT=0` lo apaga, `--path` dice dónde está el archivo, `--reset` lo vacía después de preguntar.

## Lo que no se toca sin escribir la razón

- **El bloque canónico en `docs/es/METHOD.md`.** Toda copia registrada se compara contra él; editarlo acá hace derivar todas las copias a propósito.
- **Los códigos de salida de una puerta.** Como hook, `0` pasa y `2` frena; una puerta que no puede medir imprime un `WARN` y sale `0`. En la línea de comandos el gate de formato sale `1` con fallas. Una puerta que falla callada fabrica un veredicto. `hooks/blind-replica.sh` es un comando y no un hook, y sus códigos son propios, `0` el auditor confirmó, `5` refutó, `4` sin veredicto, `6` no hay auditor configurado y solo se imprimió el brief, `2` no se pudo leer el brief.
- **Los selftests.** Cambias una puerta, reintroduces el defecto exacto por el que existe, la ves frenar, lo quitas, la ves pasar. El silencio no prueba nada.

## Trampas conocidas

- **Un hook registrado en esta sesión no corre en esta sesión.** La configuración se lee al arrancar. Prueba un hook nuevo en una sesión nueva.
- **`hooks/hooks.json` y `skills/` se cargan por convención.** Nombrarlos otra vez en `plugin.json` hace que Claude Code rechace el plugin como duplicado. Medido el 14/09/2026 instalando desde GitHub, donde la carga local con `--plugin-dir` no se había quejado.
- **La puerta de comentarios salta los archivos cuya extensión no conoce**, y cuenta solo las líneas que tu diff agrega.
- **El gate de índice vigila Write y Edit, no el shell.** Una página creada con `cat > pagina.md` o con una redirección nunca le llega. La puerta existe para que un agente no escriba una página duplicada, y un agente que escribe por el shell le pasa por al lado.
- **El parser de comandos lee el cuerpo de un heredoc como comandos.** Un `git push` adentro de un heredoc se reporta como push, así que una puerta puede frenar un comando que nunca empuja. Es el mismo exceso que con una comilla sin cerrar, y el arreglo es el mismo, partir el comando en dos.
- **En Windows, una ruta que se le pasa a un programa nativo se reescribe antes de que el programa la vea.** Git Bash convierte un argumento con forma de ruta Unix en una de Windows, así que `jq --arg alguna_ruta /tmp/x` le llega a jq como `C:/.../tmp/x` mientras el JSON que lee sigue diciendo `/tmp/x`, y la comparación falla en silencio. Los tres sistemas del CI lo cazaron el mismo día que se introdujo. Un hook de acá compara rutas en el shell y nunca le pasa una a jq como dato.
- **`--changed` en el gate de formato encuentra páginas modificadas hoy** por fecha de archivo, no por git.
- **El parser de comandos, `command-invokes.sh`, no es un parser de shell.** Respeta comillas, escapes, comentarios y redirecciones, y nunca borra contenido. No resuelve expansiones, alias, `eval` ni globbing. Cuando un comando deja una comilla sin cerrar la lectura es ambigua, y devuelve la UNIÓN de las lecturas plausibles en vez de una sola, así que una puerta puede frenar un comando que no tenía que frenar; el arreglo es partir el comando en dos. Es raro, y determinista cuando pasa.
- **La puerta de tamaño mide HEAD**, no el ref que empujas. Si empujas otra rama desde `main`, imprime un `WARN` y no mide.

## Dónde se ubica

Quita el modelo del diagrama de un sistema de agentes y lo que queda es el harness, las herramientas, los permisos, el estado y los evaluadores que lo rodean. Prisma Harness vive en esa capa. No es un loop, no reintenta el trabajo hasta que algo pase, y no es un grafo, no decide qué paso corre después. Le da al loop su evidencia y al grafo sus puertas, y solo habla cuando una puerta falla. Los pasos 1 y 2 traen sus propias skills, la entrevista, la construcción con tests primero, la revisión de fidelidad y el loop de diagnóstico; descienden de [las skills de ingeniería de Matt Pocock](https://github.com/mattpocock/skills), cuyo flujo termina en el commit, y los pasos 3, 4 y 5 son la parte por la que existe este harness.

## Lo que Prisma Harness se niega a ser

- **No es un framework de evals.** Sin datasets, sin puntajes, sin dashboards. Cinco puertas con nombre, cada una con el caso que la paga.
- **No es un segundo modelo vigilando al primero.** Corre con un solo modelo y dice en voz alta lo que eso cuesta.
- **No es un revisor de gusto.** El gate de formato lee cómo está escrita una página; nada acá califica la calidad del código.
- **No es silencioso.** Una puerta que no puede medir imprime un aviso. El silencio nunca significa limpio.

## Dónde está el resto

Detrás de cada regla del método hay una falla fechada. Este repositorio trae las reglas; la historia se queda con su autor. Las contribuciones entran con la misma regla que el método se aplica a sí mismo. Un control nuevo entra solo si da rojo sobre un caso real.

Licencia MIT.
