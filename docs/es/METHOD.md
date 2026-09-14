# PRISMA, el método de trabajo

Este es el bloque en español que define PRISMA, tomado de la fuente de verdad del autor el 14/09/2026 con una sola diferencia, los nombres de personas se reemplazaron por su rol. La versión en inglés vive en `METHOD.md`, en la raíz del repo, y es una traducción declarada de este bloque. Si las dos difieren, manda este. Los marcadores `PRISMA-CANONICAL` delimitan el bloque para que `hooks/check-canonical-sync.sh` compare tus propias copias contra él al arrancar cada sesión.

## Los cinco pasos

<!-- PRISMA-CANONICAL:START -->
**PRIMERO se rutea. Solo el carril de código corre los cinco pasos de abajo.**

| Carril | Qué es | Qué corre, con su disparador |
|---|---|---|
| **Consulta** | responder con datos, sin cambiar nada | la regla de afirmaciones. Si el número sale a un tercero, dos vías y etiqueta `[valor \| ruta \| fecha-hora]`. Sin skill |
| **Cambio mecánico** | **solo si se puede DEMOSTRAR que no cambia comportamiento EJECUTABLE, datos guardados, permisos, integración ni despliegue.** Si no se puede demostrar, es código. Una constante no es automáticamente mecánica y un umbral es una decisión | **solo el paso 3**, correrlo y mirarlo. Sin skill |
| **Código con lógica** | feature, fix de bug, migración, script que otro va a correr | **los cinco pasos**, y las skills se INVOCAN, no se citan |
| **Datos a un tercero** | un Excel para un colega, una lista para el CRM, una cifra para la dirección | **suma controles, no los reemplaza.** La consulta que produce el archivo es código y corre por su carril; la entrega lleva además **paso 3 obligatorio**, abrir el archivo y mirar filas reales, `protocolo-verificacion` y refutador |
| **Texto** | página del vault, cuerpo de PR, mensaje, informe, guion | gate de formato, refutador y la regla de afirmaciones |

**Se mide RIESGO, nunca tamaño, y la carga de la prueba la lleva mecánico.** Una fórmula de una línea puede ser el cambio más peligroso del día, y el bug del piso de RAM del 28/08 lo pagó. La redacción anterior preguntaba "¿toca una decisión, una fórmula, una métrica o una interpretación?", y un fallo de **permisos, integración o despliegue** no toca ninguna de las cuatro. Un lector cuidadoso igual lo manda a código estirando "decisión", **y eso es el problema**, porque la guarda de esta misma tabla dice que el agente tiene interés en elegir barato. Un carril no puede depender de una lectura generosa.

**Dos guardas.** En la duda va el carril MÁS CARO, porque el agente tiene interés en elegir barato. Y un carril **se sube, nunca se baja en silencio**; bajar de carril siempre se declara.

| # | Paso | Qué pasa | Skill o comprobación | Quién lo dispara |
|---|---|---|---|---|
| **1** | **Plan** | entrevista que afila la idea hasta el entendimiento compartido y deja registro | **invoca AHORA** `mattpocock-skills:grilling` (la persona, directo, `/mattpocock-skills:grill-with-docs`) | el terminal la arranca solo; la persona responde decisiones |
| 1b | la bifurcación | decidir si cabe en UNA sesión (~140k de contexto útil) | ningún comando, es criterio | el agente lo estima al cerrar la entrevista y LO DICE |
| 1c | solo si NO cabe | escribir el destino y el camino en tickets del tamaño de una sesión | spec y tickets como misiones del tablero (la persona, directo, `/to-spec` → `/to-tickets`) | el agente |
| **2** | **Construir** | ejecutar la cadena del orquestador | **invoca AHORA**, en orden: construir → `mattpocock-skills:tdd` → `mattpocock-skills:code-review` en subagentes limpios → commit (la persona, directo, `/implement`) | el agente |
| 2b | solo si está roto | diagnosticar antes de parchar | `mattpocock-skills:diagnosing-bugs` | el agente |
| **3** | **E2E** | correr sobre datos reales y **MIRAR** el resultado. Antes de activar algo que una persona va a ver, **se nombra la superficie donde la ve y se mira ESA**, no el artefacto que la produce. Si no se puede nombrar, no se activa. Se nombra ANTES, porque después uno nombra lo que ya miró. Y si lo que ya corre en producción comparte una configuración y lo nuevo no, esa diferencia **se explica antes de activar**, no se anota como opcional. Si la cifra gobierna una decisión, se validan la cifra Y la decisión **a los dos lados del umbral**, porque una cifra equivocada puede caer del lado correcto por accidente | ninguna skill, es ejecutar la cosa real | el agente. Dos fallas de la misma hipótesis funcional obligan a volver al paso 1. Una falla ambiental se diagnostica y no cuenta para ese límite |
| **4** | **QA del QA y gate de formato** | **falsificar el oráculo**, no elegir una mutación cómoda. Tres requisitos: reintroducir el defecto EXACTO, sumar un contraejemplo semántico elegido aparte, y confirmar que la prueba **falla por la razón esperada** y no que aparezca cualquier rojo | inyección controlada + `~/.claude/hooks/judge-vault.sh --strict` sobre el texto | el agente. El gate de formato no lee código ni reemplaza la prueba |
| **5** | **Verificar** | comprobar la condición de salida en la fuente o superficie real | si produce una cifra, medirla de nuevo por otra vía, y si depende del estado del entorno medirla en el estado normal **y en el de borde**; si cambia comportamiento, observarlo en el destino | el agente. No se cita una corrida anterior ni el vault como sustituto de la realidad |
<!-- PRISMA-CANONICAL:END -->

## Cómo se lee

**Primero se rutea, después se ejecuta.** Cada pedido entra por uno de los cinco carriles y el carril decide qué corre. Solo el carril de código con lógica corre los cinco pasos. La guía completa, con un ejemplo por carril y la pregunta de una línea que decide cada uno, está en `METHOD.md`.

**El modo de un solo modelo.** Este repo no exige un segundo motor. Donde el método pide una réplica ciega, se lanza un subagente en contexto limpio con solo la afirmación y las fuentes, y se declara que eso da independencia de derivación y no de motor. Quien tenga otro motor lo conecta con `PRISMA_AUDITOR_CMD`. El detalle está en `METHOD.md`, sección "Single-model mode".

Fuentes: bloque canónico de PRISMA, versión del 05/09/2026, extraído de la fuente de verdad del autor el 14/09/2026 y neutralizado en nombres.
