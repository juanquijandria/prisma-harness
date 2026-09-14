// Prisma Harness. Geometry of the diagram, the only place that produces it. Ported from the author's diagram with its internal identifiers unchanged.
import { NODES as NODOS, EDGES as ARISTAS, ACTORS as ACTORES, COLUMNS as COLUMNAS } from './content.mjs'

export const T = { papel:'#f2f0ed', carta:'#faf9f7', tinta:'#1a1a18', medio:'#8a8681',
                   suave:'#b4b0a9', linea:'rgba(26,26,24,.17)', fill2:'#e8e5e0' }
export const MONO = 'ui-monospace,SFMono-Regular,Menlo,monospace'
export const SANS = '"Helvetica Neue",Inter,system-ui,-apple-system,sans-serif'

// --- rejilla. Todo divisible por 2, y las medidas grandes por 4.
export const M = 40            // margen
export const ROTULO = 168      // gutter izquierdo, donde van los nombres de carril
export const NW = 138, NH = 56 // caja
export const GAP = 12          // entre cajas de la misma celda
export const PAD = 14          // aire dentro de la columna
export const COLGAP = 28       // canal entre columnas, por donde suben las aristas
export const ALTO_CARRIL = 110
export const H_RUTEO = 186     // la banda de ruteo, arriba de todo
export const H_EJE = 30        // los rotulos de columna
export const H_RETORNO = 68    // la capa donde viven los retornos
export const H_TRANS = 84      // la banda de las tres reglas
export const SEP = 26

// --- ejes verticales
export const Y_RUTEO = M
export const Y_EJE = Y_RUTEO + H_RUTEO + SEP
export const Y_CARRIL0 = Y_EJE + H_EJE
export const carrilY = (i) => Y_CARRIL0 + i * ALTO_CARRIL
export const Y_FIN_CARRILES = carrilY(ACTORES.length)
export const Y_RETORNO = Y_FIN_CARRILES
export const Y_TRANS = Y_RETORNO + H_RETORNO + SEP
export const ALTO = Y_TRANS + H_TRANS + M

// --- ejes horizontales. El ancho de una columna sale de cuantas cajas tiene
// la celda mas cargada, no de una lista escrita a mano.
const enCelda = (actor, col) => NODOS.filter((n) => n.actor === actor && n.col === col)
const maxEnCol = (col) => Math.max(...ACTORES.map((a) => enCelda(a.id, col).length))
export const ANCHOS = COLUMNAS.map((c) => {
  const n = Math.max(1, maxEnCol(c.id))
  return n * NW + (n - 1) * GAP + 2 * PAD
})
export const X0 = M + ROTULO
export const colX = (i) => X0 + ANCHOS.slice(0, i).reduce((s, w) => s + w + COLGAP, 0)
export const colIdx = (id) => COLUMNAS.findIndex((c) => c.id === id)
// el canal limpio a la izquierda de cada columna, garantizado sin cajas
export const canal = (i) => colX(i) - COLGAP / 2
export const CANAL_IZQ = M + 140   // el canal del gutter, para los retornos largos
export const ANCHO = colX(COLUMNAS.length - 1) + ANCHOS[COLUMNAS.length - 1] + M

// --- las cajas
export const CAJAS = {}
for (const a of ACTORES) {
  const iA = ACTORES.indexOf(a)
  for (const c of COLUMNAS) {
    enCelda(a.id, c.id).forEach((n, pos) => {
      const x = colX(colIdx(c.id)) + PAD + pos * (NW + GAP)
      const y = carrilY(iA) + (ALTO_CARRIL - NH) / 2
      CAJAS[n.id] = { id: n.id, x, y, w: NW, h: NH, cx: x + NW / 2, cy: y + NH / 2,
                      der: x + NW, bot: y + NH, actor: a.id, col: c.id, iActor: iA }
    })
  }
}

const nodo = (id) => NODOS.find((n) => n.id === id)

// --- las rutas. Cada arista devuelve sus puntos, y de ahi salen el path del
// dibujo y la comprobacion de cruces. Una sola definicion para las dos cosas.
//
// El enrutado es POR REINTENTO y no por casos escritos a mano: se proponen tres
// formas en orden de preferencia y se toma la primera que no pise una caja
// ajena. Escribir un caso por situacion fue lo que dejo pasar dos cruces en el
// primer intento de hoy, uno de ellos sobre la propia caja del refutador.

function pisa(pts, deId, aId) {
  const ajenas = Object.values(CAJAS).filter((c) => c.id !== deId && c.id !== aId)
  for (let i = 0; i < pts.length - 1; i++) {
    const [x1, y1] = pts[i], [x2, y2] = pts[i + 1]
    for (let t = 0; t <= 1; t += 0.01) {
      const x = x1 + (x2 - x1) * t, y = y1 + (y2 - y1) * t
      for (const c of ajenas) {
        if (x > c.x + 2 && x < c.der - 2 && y > c.y + 2 && y < c.bot - 2) return c
      }
    }
  }
  return null
}

// 1. la directa, que es la que se lee mejor
function directa(a) {
  const A = CAJAS[a.de], B = CAJAS[a.a]
  if (a.tipo === 'retorno' && A.col !== B.col && A.actor === B.actor) {
    const y = Y_RETORNO + 30
    return [[A.cx, A.bot], [A.cx, y], [CANAL_IZQ, y], [CANAL_IZQ, B.cy], [B.x, B.cy]]
  }
  if (a.tipo === 'retorno' && A.actor === B.actor) {
    const y = A.y - 16
    return [[A.cx, A.y], [A.cx, y], [B.cx, y], [B.cx, B.y]]
  }
  if (A.actor === B.actor) return A.cx < B.cx ? [[A.der, A.cy], [B.x, B.cy]] : [[A.x, A.cy], [B.der, B.cy]]
  if (Math.abs(A.cx - B.cx) < 1) {
    // Un retorno con la misma x cae ENCIMA de la ida y desaparece. Se corre para
    // que el par ida/vuelta se lea como par. Pasaba con g1 -> p2 el 28/08.
    const dx = a.tipo === 'retorno' ? 22 : 0
    return A.iActor < B.iActor
      ? [[A.cx, A.bot], [B.cx, B.y]]
      : [[A.cx + dx, A.y], [A.cx + dx, (A.y + B.bot) / 2], [B.cx + dx, (A.y + B.bot) / 2], [B.cx + dx, B.bot]]
  }
  if (A.iActor < B.iActor && A.cx < B.cx) return [[A.der, A.cy], [B.cx, A.cy], [B.cx, B.y]]
  if (A.iActor > B.iActor && A.cx < B.cx) {
    const y = A.y - 16
    return [[A.cx, A.y], [A.cx, y], [B.cx, y], [B.cx, B.bot]]
  }
  if (A.iActor > B.iActor) return [[A.cx, A.y], [A.cx, B.cy], [B.der, B.cy]]
  const cx = canal(colIdx(B.col))
  return [[A.x, A.cy], [cx, A.cy], [cx, B.cy], [B.x, B.cy]]
}

// 2. por encima de la fila de cajas, sin salir del carril
function porArriba(a) {
  const A = CAJAS[a.de], B = CAJAS[a.a]
  const y = Math.min(A.y, B.y) - 16
  return [[A.cx, A.y], [A.cx, y], [B.cx, y], [B.cx, B.y]]
}

// 3. por el canal entre columnas, que esta garantizado sin cajas
function porCanal(a) {
  const A = CAJAS[a.de], B = CAJAS[a.a]
  const cx = canal(colIdx(B.col))
  const eA = A.x < cx ? A.der : A.x
  const eB = B.x < cx ? B.der : B.x
  return [[eA, A.cy], [cx, A.cy], [cx, B.cy], [eB, B.cy]]
}

export function puntos(a) {
  if (a.pts) return a.pts   // ruta explicita, solo la usa la calibracion
  const A = CAJAS[a.de], B = CAJAS[a.a]
  if (!A || !B) return []
  for (const via of [directa, porArriba, porCanal]) {
    const pts = via(a)
    if (pts.length && !pisa(pts, a.de, a.a)) return pts
  }
  return directa(a)   // ninguna limpia: se devuelve la mejor y la prueba lo grita
}

export const d = (pts) => pts.map((p, i) => (i ? 'L ' : 'M ') + p[0] + ' ' + p[1]).join(' ')

// --- la comprobacion de cruces vive aca porque usa la misma geometria
export function cruces(lista = ARISTAS) {
  const malas = []
  for (const a of lista) {
    const pts = puntos(a)
    const ajenas = Object.values(CAJAS).filter((c) => c.id !== a.de && c.id !== a.a)
    let choque = null
    for (let i = 0; i < pts.length - 1 && !choque; i++) {
      const [x1, y1] = pts[i], [x2, y2] = pts[i + 1]
      for (let t = 0; t <= 1 && !choque; t += 0.01) {
        const x = x1 + (x2 - x1) * t, y = y1 + (y2 - y1) * t
        for (const c of ajenas) {
          if (x > c.x + 2 && x < c.der - 2 && y > c.y + 2 && y < c.bot - 2) { choque = c; break }
        }
      }
    }
    if (choque) malas.push({ a, sobre: choque.id })
  }
  return malas
}

export { NODOS, ARISTAS, ACTORES, COLUMNAS, nodo }
