# Cómo se escribe, y qué hace cumplir el gate de formato

Todo texto que sale de la máquina sigue estas reglas, y `hooks/format-gate.sh` comprueba las mecánicas. El gate revisa cómo está escrita una página; no lee código ni encuentra bugs. La versión en inglés es `STYLE.md`, en la raíz.

El gate habla de tres formas. Un nombre de archivo roto, un H1 ausente, un encabezado cuyo conteo no cuadra y, cuando está encendido, un pie de fuentes ausente, son fallas en todos los modos. Un em-dash en la prosa y el voseo son avisos por su cuenta y fallas bajo `--strict`, que es como corre el hook de cierre. Los dos puntos en la prosa, el techo de la página, una etiqueta de verificar sin fecha y un wikilink roto son siempre avisos.

## Las reglas que el gate hace cumplir por defecto

| Regla | Clave de config | Qué caza | Por qué |
|---|---|---|---|
| Sin em-dashes en la prosa | `RULE_EM_DASH` | un `—` fuera de encabezados, código y backticks; dentro de una tabla solo se permite la celda vacía `—` | un em-dash esconde la decisión de cómo se relacionan dos ideas. Una coma, un punto o una "y" la dicen |
| Sin dos puntos en la prosa | `RULE_COLON_IN_PROSE` | `palabra: Palabra` en una línea de prosa, ignorando URLs, horas, tablas y código | los dos puntos abren una lista o una etiqueta; en prosa reemplazan a un verbo que debería estar |
| El encabezado cuenta lo que sigue | `RULE_HEADING_COUNTS` | "## Tres detalles" seguido de cuatro items numerados en negrita, en numerales de español o inglés | un conteo escrito es una afirmación que un diff puede desmentir |
| Nombres de archivo en kebab-case | `RULE_KEBAB_CASE` | `Nombre_Malo.md`, `nombreMalo.md` | una sola convención de nombres y los enlaces no se rompen por mayúsculas |
| H1 en la primera línea | `RULE_H1_FIRST_LINE` | una página que no arranca con `# ` | la primera línea nombra el concepto, para personas y para herramientas |
| Sin voseo | `RULE_VOSEO` | los imperativos con tilde como `mirá` o `usá` en cualquier página, y las palabras sueltas `vos` y `sos` solo en una página escrita en español, así un `SOS` en inglés no es hallazgo. El pretérito `escribí` nunca es voseo | el español del método es peruano, sin voseo. Se apaga si el tuyo lo usa, o si no escribes en español |
| Techo de la página | `RULE_LINE_CEILING` | un aviso a nueve décimos del techo y otro al pasarlo, 150 líneas por defecto | pasadas las 150 líneas una página son dos conceptos. Propone partir, no prohíbe. En 0 se apaga, o se declara `<!-- ceiling-imposed: motivo -->` en las primeras diez líneas |

## Las reglas apagadas por defecto

Son de un wiki en Obsidian y se encienden en `.prisma-format.conf` cuando ese es tu caso.

| Regla | Clave de config | Qué caza |
|---|---|---|
| Pie de fuentes | `RULE_SOURCES_FOOTER` | una página sin línea final `Fuentes:` o `Sources:` |
| Los wikilinks resuelven | `RULE_WIKILINKS` | `[[pagina]]` o `![[archivo.svg]]` que no apunta a nada bajo la carpeta de docs |
| Etiqueta de verificar con fecha | `RULE_VERIFY_TAG` | `[verificar]` o `[verify]` sin una fecha al lado |

## Las reglas que el gate no puede hacer cumplir

Son la forma en que el autor del método le escribe a quien lee, y son la razón de que existan las mecánicas. `hooks/session-voice.sh` las inyecta en cada sesión al arrancar, así el agente las sigue sin que nadie se lo pida; `PRISMA_VOICE=0` lo apaga.

- **La respuesta va primero.** Una pregunta cerrada se responde en la primera línea, antes de cualquier título.
- **Una idea por oración, con verbo.** Corto no es telegráfico; una oración le gana a una etiqueta con dos puntos.
- **Los títulos son cortos y terminan en dos puntos**, y lo clave de la sección va en negrita al inicio. Sin líneas separadoras entre secciones.
- **Sin paréntesis y sin flechas.** Lo que va entre paréntesis merece una oración o merece irse.
- **Los números y el código quedan fuera de la prosa.** Una medición va en su propia línea o en una tabla con la fecha en que se midió; un comando va en bloque de código.
- **Todo nombre propio lleva su cargo la primera vez o no aparece.** Todo "hoy" se vuelve fecha absoluta.
- **Toda cifra que sale de la máquina es hipótesis hasta medirla por dos vías.** Di qué verificaste, qué no, y qué intentaste cuando no pudiste.
- **El español es peruano, sin voseo.** El código, los identificadores y los commits van en inglés.
- **Un texto que alguien va a pegar en otro lado va entre dos líneas de `═`**, sin nada tuyo adentro, nunca en bloque de código ni en cita, porque esos dibujan una barra que se copia junto con el texto.

## Configuración

Copia `.prisma-format.conf.example` a `<raíz de docs>/.prisma-format.conf`, o define `PRISMA_<CLAVE>` en el entorno. La raíz de docs es `PRISMA_DOCS_ROOT`, por defecto la carpeta del proyecto, y las páginas se buscan bajo `PRISMA_DOCS_DIR`, por defecto `wiki`. `EXEMPT_NAMES` y `EXEMPT_DIRS` listan lo que el gate salta.

```
hooks/format-gate.sh --strict pagina.md    una página, con em-dash y voseo elevados a falla
hooks/format-gate.sh --changed             toda página bajo la carpeta de docs tocada hoy, estricto, sale 2 para que el hook de Stop frene
hooks/format-gate.sh --debt                inventario de toda la carpeta, contado y no gritado
hooks/format-gate.sh --debt-freeze         congela el inventario de hoy como baseline de regresión
hooks/format-gate.sh --match pagina.md     inyecta cinco defectos en una copia de una página REAL y comprueba que los caza
hooks/format-gate.sh --selftest            el gate sobre 30 casos armados
```

Fuentes: las reglas de escritura del autor al 14/09/2026, y el selftest del gate, que es la versión ejecutable de esta página.
