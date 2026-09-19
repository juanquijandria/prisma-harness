# Writing style, and what the format gate enforces

Every text that leaves the machine follows these rules, and `hooks/format-gate.sh` checks the mechanical ones. The gate reads how a page is written; it reads no code and finds no bugs. The Spanish version of this page is `docs/es/STYLE.md`.

The gate speaks in three ways. A broken file name, a missing H1, a heading whose count does not match and, when it is on, a missing sources footer, are failures in every mode. An em-dash in prose and voseo are warnings on their own and failures under `--strict`, which is how the Stop hook runs. A colon in prose, the page ceiling, an undated verify tag and a broken wikilink are always warnings.

## The rules the gate enforces by default

| Rule | Config key | What it catches | Why |
|---|---|---|---|
| No em-dashes in prose | `RULE_EM_DASH` | a `—` outside headings, code and backticks; inside a table only an empty `—` cell is allowed | an em-dash hides a decision about how two ideas relate. A comma, a period or "and" states it |
| No colons in prose | `RULE_COLON_IN_PROSE` | `word: Word` in a prose line, ignoring URLs, clock times, tables and code | a colon introduces a list or a label; in prose it stands in for a verb that should be there |
| Headings count what follows | `RULE_HEADING_COUNTS` | "## Three details" followed by four bold numbered items, in English or Spanish numerals | a stated count is a claim a diff can disprove |
| File names in kebab-case | `RULE_KEBAB_CASE` | `Bad_Name.md`, `badName.md` | one name convention means links never break on case |
| H1 on the first line | `RULE_H1_FIRST_LINE` | a page that does not start with `# ` | the first line names the concept, for people and for tools |
| No River Plate voseo | `RULE_VOSEO` | accented imperatives like `mirá` or `usá` in any page, and the bare words `vos` and `sos` only in a page that is written in Spanish, so an English `SOS` is not a finding. The first-person preterite `escribí` is never voseo | the method's Spanish is Peruvian, with no voseo. Turn it off if your Spanish uses it, or if you do not write Spanish at all |
| Page ceiling | `RULE_LINE_CEILING` | a warning at nine tenths of the ceiling and another past it, 150 lines by default | past 150 lines a page is two concepts. It proposes a split, it does not forbid. Set to 0 to disable, or add `<!-- ceiling-imposed: reason -->` in the first ten lines |

## The rules off by default

They belong to a wiki kept in Obsidian and are switched on in `.prisma-format.conf` when that is your setup.

| Rule | Config key | What it catches |
|---|---|---|
| Sources footer | `RULE_SOURCES_FOOTER` | a page without a final `Sources:` or `Fuentes:` line |
| Wikilinks resolve | `RULE_WIKILINKS` | `[[page]]` or `![[file.svg]]` that points to nothing under the docs dir |
| Verify tag with date | `RULE_VERIFY_TAG` | `[verify]` or `[verificar]` without a date next to it |
| Rates carry a second reading | `RULE_RATE_SECOND_READING` | a page with six or more rate cells in its tables and not one of them published under a second definition. `RATE_CELLS_FLOOR` moves the six, `RATE_EXEMPT_DIRS` says where it does not apply, and unlike every other rule it still runs on the folders `EXEMPT_DIRS` lists, because a delivery is drafted there |

## The rules the gate cannot enforce

These are how the method's author writes to a reader, and they are the reason the mechanical rules exist. `hooks/session-voice.sh` injects them into every session at start, so the agent follows them without being asked; `PRISMA_VOICE=0` switches that off.

- **The answer goes first.** A closed question gets its answer in the first line, before any heading.
- **One idea per sentence, with a verb.** Short is not clipped; a sentence beats a label with a colon.
- **Headings are short and end in a colon**, and the key point of the section is bold at its start. No horizontal rules between sections.
- **No parentheticals and no arrows.** What goes in parentheses is either worth a sentence or worth cutting.
- **Numbers and code stay out of prose.** A measurement goes on its own line or in a table with the date it was measured; a command goes in a code block.
- **Every proper name gets its role the first time or does not appear.** Every "today" becomes an absolute date.
- **Every figure that leaves the machine is a hypothesis until measured by two routes.** Say what you verified, what you did not, and what you tried when you could not.
- **Spanish is Peruvian, with no voseo.** Code, identifiers and commits are in English.
- **A text someone will paste elsewhere goes between two lines of `═`**, with nothing of yours inside, never in a code block or a quote, because those render a bar that gets copied along.

## Configuration

Copy `.prisma-format.conf.example` to `<docs root>/.prisma-format.conf`, or set `PRISMA_<KEY>` in the environment. The docs root is `PRISMA_DOCS_ROOT`, defaulting to the project directory, and pages are looked up under `PRISMA_DOCS_DIR`, defaulting to `wiki`. `EXEMPT_NAMES` and `EXEMPT_DIRS` list what the gate skips.

```
hooks/format-gate.sh --strict page.md      one page, with em-dash and voseo raised to failures
hooks/format-gate.sh --changed             every page under the docs dir touched today, strict, exits 2 so the Stop hook blocks
hooks/format-gate.sh --debt                inventory of the whole docs dir, counted and not shouted
hooks/format-gate.sh --debt-freeze         freeze today's inventory as the regression baseline
hooks/format-gate.sh --match page.md       inject five defects into a copy of a REAL page and check they get caught
hooks/format-gate.sh --selftest            the gate over 30 built cases
```

Sources: the author's writing rules as of 2026-09-14, and the format gate's selftest, which is the executable version of this page.
