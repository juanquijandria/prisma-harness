// Prisma Harness. The gate of the diagram: it must declare the same lanes, steps and gates as METHOD.md, in BOTH directions.
//   node verify.mjs             check against ../METHOD.md, exit 0 or 1
//   node verify.mjs --selftest  lie on purpose and check the lie is caught

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { NODES, GATES, CARDS, EDGES, LANES } from './content.mjs'

const HERE = path.dirname(fileURLToPath(import.meta.url))
export const SOURCE = path.join(HERE, '..', 'METHOD.md')
const NUMERALS = { two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10 }

export function modelOfSource(text) {
  const gatesHeading = text.match(/^##\s+The\s+([a-z]+)\s+gates\b.*$/mi)
  const declared = gatesHeading ? (NUMERALS[gatesHeading[1].toLowerCase()] ?? null) : null
  const gates = []
  if (gatesHeading) {
    let started = false
    for (const l of text.slice(text.indexOf(gatesHeading[0]) + gatesHeading[0].length).split('\n')) {
      const m = l.match(/^- \*\*([^*]+)\*\*/)
      if (m) { gates.push(m[1].trim().replace(/,$/, '')); started = true; continue }
      if (l.trim() === '') { if (started) break; else continue }
      if (started) break
    }
  }
  const steps = []
  for (const l of text.split('\n')) {
    const m = l.match(/^\|\s*\*{0,2}([0-9][a-z]?)\*{0,2}\s*\|\s*(.+?)\s*\|/)
    if (m) steps.push({ num: m[1], row: l })
  }
  const lanes = []
  for (const l of text.split('\n')) {
    const m = l.match(/^\|\s*\*\*([^*|]+)\*\*\s*\|/)
    if (m && !/^[0-9]/.test(m[1].trim())) lanes.push(m[1].trim())
  }
  return { gates, declared, steps, lanes }
}

function compare(what, inSource, inDiagram, failures) {
  const dupS = inSource.filter((x, i) => inSource.indexOf(x) !== i)
  const dupD = inDiagram.filter((x, i) => inDiagram.indexOf(x) !== i)
  if (dupS.length) failures.push(`${what}: the source repeats ${[...new Set(dupS)].join(', ')}`)
  if (dupD.length) failures.push(`${what}: the diagram repeats ${[...new Set(dupD)].join(', ')}`)
  for (const x of inSource) if (!inDiagram.includes(x)) failures.push(`${what}: the source declares "${x}" and the diagram does NOT draw it`)
  for (const x of inDiagram) if (!inSource.includes(x)) failures.push(`${what}: the diagram draws "${x}" and the source does NOT declare it`)
}

export function verify(sourceText, nodes = NODES, gates = GATES, lanes = LANES) {
  const failures = []
  const S = modelOfSource(sourceText)
  compare('gates', S.gates, gates.map((g) => g.nombre), failures)
  if (S.declared !== null && S.declared !== S.gates.length) failures.push(`the source contradicts itself: the heading says ${S.declared} gates and there are ${S.gates.length} bullets`)
  compare('steps', S.steps.map((p) => p.num), nodes.filter((n) => n.num).map((n) => n.num), failures)
  for (const n of nodes) {
    if (!n.num) continue
    const row = S.steps.find((p) => p.num === n.num)
    if (!row) continue
    const key = n.titulo.toLowerCase().replace(/^(the|a|an) /, '').split(' ')[0]
    if (!row.row.toLowerCase().includes(key)) failures.push(`step ${n.num}: the diagram titles it "${n.titulo}" and that word is not in its source row`)
  }
  compare('lanes', S.lanes, lanes.map((c) => c.nom), failures)
  const gateIds = new Set(gates.map((g) => g.id))
  for (const n of nodes) {
    if (n.num || gateIds.has(n.id)) continue
    if (!n.clave) { failures.push(`node ${n.id} has neither a number nor a key phrase, so nothing ties it to the source`); continue }
    if (!sourceText.toLowerCase().includes(n.clave.toLowerCase())) failures.push(`node ${n.id} ("${n.titulo}") claims the phrase "${n.clave}" and it is NOT in the source`)
  }
  for (const n of nodes) if (!CARDS[n.id]) failures.push(`node ${n.id} has no card`)
  const ids = new Set(nodes.map((n) => n.id))
  for (const a of EDGES) {
    if (!ids.has(a.de)) failures.push(`edge ${a.de}->${a.a} leaves from a node that does not exist`)
    if (!ids.has(a.a)) failures.push(`edge ${a.de}->${a.a} arrives at a node that does not exist`)
  }
  return failures
}

function selftest() {
  const text = fs.readFileSync(SOURCE, 'utf8')
  let r = 0
  const base = new Set(verify(text))
  const cases = [
    ['INVENTION: a step number the source does not have', /steps:.*"9"/, NODES.map((n) => (n.id === 'p3' ? { ...n, num: '9' } : n)), GATES, LANES],
    ['INVENTION: a gate with a made-up name', /Magic Doorman/, NODES, GATES.map((g) => (g.id === 'g2' ? { ...g, nombre: 'Magic Doorman' } : g)), LANES],
    ['OMISSION: a gate the source declares is missing', /gates:.*does NOT draw/, NODES, GATES.slice(0, -1), LANES],
    ['OMISSION: a step the source declares is missing', /steps:.*"3".*does NOT draw/, NODES.filter((n) => n.id !== 'p3'), GATES, LANES],
    ['OMISSION: a lane the source declares is missing', /lanes:.*does NOT draw/, NODES, GATES, LANES.slice(0, -1)],
    ['DUPLICATE: the same gate twice', /the diagram repeats/, NODES, [...GATES, { ...GATES[0], id: 'gx' }], LANES],
    ['RENAME: a lane the source calls something else', /Small change/, NODES, GATES, LANES.map((c, i) => (i === 1 ? { ...c, nom: 'Small change' } : c))],
    ['INVENTION: an unnumbered node resting on a phrase the source lacks', /NOT in the source/, NODES.map((n) => (n.id === 'pv' ? { ...n, clave: 'before starting to build' } : n)), GATES, LANES],
    ['UNTIED: an unnumbered node without a key phrase', /neither a number nor a key phrase/, NODES.map((n) => (n.id === 'frz' ? { ...n, clave: undefined } : n)), GATES, LANES],
  ]
  for (const [name, signature, nodes, gates, lanes] of cases) {
    const fresh = verify(text, nodes, gates, lanes).filter((f) => !base.has(f))
    if (!fresh.length) { console.log(`  BLIND          ${name}`); r = 1 }
    else if (!fresh.some((f) => signature.test(f))) { console.log(`  WRONG RED      ${name}\n                 expected ${signature}, got: ${fresh[0]}`); r = 1 }
    else console.log(`  caught         ${name}`)
  }
  if (base.size) { console.log('\n  SHOUTS on the real content:'); [...base].forEach((x) => console.log('    ' + x)); r = 1 }
  else console.log('\n  quiet on the real content')
  console.log(r === 0 ? '\nSELFTEST OK: every mutation turns red for its OWN reason, and the truth stays quiet' : '\nSELFTEST FAILED')
  return r
}

export const HAND_MAP = path.join(HERE, 'method-map', 'method-map.dc.html')

export function verifyHandMap(sourceText, htmlText) {
  const S = modelOfSource(sourceText)
  const visible = htmlText.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, '').replace(/<[^>]+>/g, ' ').replace(/&amp;/g, '&').replace(/\s+/g, ' ').toLowerCase()
  const missing = []
  for (const g of S.gates) if (!visible.includes(g.toLowerCase())) missing.push(`gate "${g}"`)
  for (const l of S.lanes) if (!visible.includes(l.toLowerCase())) missing.push(`lane "${l}"`)
  for (const p of S.steps) if (!visible.includes(`${p.num}. `.toLowerCase()) && !visible.includes(`${p.num}.`.toLowerCase())) missing.push(`step ${p.num}`)
  for (const r of TRANSVERSAL_RULES(sourceText)) if (!visible.includes(r.toLowerCase())) missing.push(`transversal rule "${r}"`)
  return missing
}

function TRANSVERSAL_RULES(sourceText) {
  const rules = []
  for (const l of sourceText.split('\n')) {
    const m = l.match(/^## (Every claim is a hypothesis until it is measured|How the method grows|The instrument comes before the hypothesis)/)
    if (m) rules.push(m[1])
  }
  return rules
}

if (process.argv[2] === '--selftest') process.exit(selftest())
if (import.meta.url === `file://${process.argv[1]}`) {
  if (!fs.existsSync(SOURCE)) { console.error(`FAIL: ${SOURCE} does not exist`); process.exit(1) }
  const sourceText = fs.readFileSync(SOURCE, 'utf8')
  const failures = verify(sourceText)
  if (failures.length) { console.error('THE DIAGRAM LIES:'); failures.forEach((f) => console.error('  ' + f)); process.exit(1) }
  console.log('GATE OK: the diagram and METHOD.md declare the same things, in both directions')
  if (fs.existsSync(HAND_MAP)) {
    const missing = verifyHandMap(sourceText, fs.readFileSync(HAND_MAP, 'utf8'))
    if (missing.length) { console.log('HAND MAP, declared by the method and not drawn:'); missing.forEach((m) => console.log('  ' + m)) }
    else console.log('HAND MAP OK: every lane, step and gate the method declares is drawn')
  }
}
