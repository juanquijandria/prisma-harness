// Prisma Harness. Geometry test: no edge runs over a box that is not its origin or destination.
import { cruces, ARISTAS, CAJAS, ANCHO, ALTO } from './layout.mjs'

const malas = cruces()
for (const m of malas) console.log(`  CROSSES: ${m.a.de} -> ${m.a.a} runs over ${m.sobre}`)

const cajas = Object.values(CAJAS)
const victima = cajas.find((c) => c.id === 'p1b')
const mentira = { de: 'p1', a: 'p1c', tipo: 'flujo',
                  pts: [[victima.x - 30, victima.cy], [victima.der + 30, victima.cy]] }
const cazada = cruces([mentira])
if (!cazada.length || cazada[0].sobre !== 'p1b') {
  console.log('  THE DETECTOR MISSES an edge that crosses p1b on purpose')
  process.exit(1)
}
console.log(`  positive control: the detector catches the planted edge, over ${cazada[0].sobre}`)

const limpia = { de: 'p1', a: 'p1b', tipo: 'flujo',
                 pts: [[CAJAS.p1.der, CAJAS.p1.cy], [CAJAS.p1b.x, CAJAS.p1b.cy]] }
if (cruces([limpia]).length) { console.log('  THE DETECTOR SHOUTS on a clean edge'); process.exit(1) }
console.log('  negative control: quiet on a clean edge')

console.log(malas.length === 0
  ? `LAYOUT OK: ${ARISTAS.length} edges over ${cajas.length} boxes on a ${ANCHO}x${ALTO} canvas, none crosses`
  : `LAYOUT FAILED: ${malas.length} crossings`)
process.exit(malas.length ? 1 : 0)
