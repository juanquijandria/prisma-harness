// Prisma Harness. Draws the method diagram. index.html and assets/prisma-flow.svg are OUTPUT, never edited by hand.

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { CARDS as FICHAS, GATES as PUERTAS, TRANSVERSAL as TRANSVERSALES, LANES as CARRILES, ROUTING_QUESTION as PREGUNTA_RUTEO, ROUTING_SUB as SUB_RUTEO } from './content.mjs'
import { verify as verificar, SOURCE as FUENTE } from './verify.mjs'
import * as G from './layout.mjs'
const HERE = path.dirname(fileURLToPath(import.meta.url))

const { T, MONO, SANS, M, ANCHO: W, ALTO, CAJAS, NODOS, ARISTAS, ACTORES, COLUMNAS } = G

if (!process.env.PRISMA_SKIP_VERIFY) {
  if (!fs.existsSync(FUENTE)) { console.error('FAIL: the source does not exist, ' + FUENTE); process.exit(1) }
  const f = verificar(fs.readFileSync(FUENTE, 'utf8'))
  if (f.length) { console.error('NOT PUBLISHED, the diagram lies:'); f.forEach((x) => console.error('  ' + x)); process.exit(1) }
  const c = G.cruces()
  if (c.length) { console.error('NOT PUBLISHED, edges cross boxes:'); c.forEach((x) => console.error(`  ${x.a.de} -> ${x.a.a} over ${x.sobre}`)); process.exit(1) }
}

const svg = []
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
const texto = (x, y, s, o = {}) =>
  `<text x="${x}" y="${y}" ${o.an ? `text-anchor="${o.an}" ` : ''}font-family="${o.mono ? MONO : SANS}" ` +
  `font-size="${o.t || 11}"${o.peso ? ` font-weight="${o.peso}"` : ''}${o.esp ? ` letter-spacing="${o.esp}"` : ''} ` +
  `fill="${o.c || T.tinta}">${esc(s)}</text>`

const CHW = (W - 2 * M - 4 * 16) / 5
const chipX = (i) => M + i * (CHW + 16)
const Y_BARRA = G.Y_RUTEO + 74, Y_CHIP = G.Y_RUTEO + 84, H_CHIP = 62
const iCod = CARRILES.findIndex((c) => c.pasos)
const xCod = chipX(iCod) + CHW / 2

svg.push(texto(M, G.Y_RUTEO + 14, 'ROUTE FIRST · WHEN IN DOUBT, THE MORE EXPENSIVE LANE · A LANE GOES UP, NEVER SILENTLY DOWN',
  { mono: true, t: 9, esp: 1.1, c: T.medio }))
svg.push(texto(W / 2, G.Y_RUTEO + 42, PREGUNTA_RUTEO, { an: 'middle', t: 14.5, peso: 600 }))
svg.push(texto(W / 2, G.Y_RUTEO + 58, SUB_RUTEO, { an: 'middle', mono: true, t: 9.5, c: T.medio }))
svg.push(`<path d="M ${chipX(0) + CHW / 2} ${Y_BARRA} H ${chipX(4) + CHW / 2}" fill="none" stroke="${T.linea}" stroke-width="1"/>`)
svg.push(`<path d="M ${W / 2} ${G.Y_RUTEO + 64} V ${Y_BARRA}" fill="none" stroke="${T.linea}" stroke-width="1"/>`)
CARRILES.forEach((c, i) => {
  const x = chipX(i), cx = x + CHW / 2
  svg.push(`<path d="M ${cx} ${Y_BARRA} V ${Y_CHIP}" fill="none" stroke="${c.pasos ? T.tinta : T.linea}" stroke-width="${c.pasos ? 1.4 : 1}"/>`)
  svg.push(`<rect x="${x}" y="${Y_CHIP}" width="${CHW}" height="${H_CHIP}" rx="6" fill="${c.pasos ? T.carta : 'rgba(26,26,24,.02)'}" stroke="${c.pasos ? T.tinta : T.linea}" stroke-width="${c.pasos ? 1.8 : 1}"/>`)
  svg.push(texto(cx, Y_CHIP + 26, c.nom, { an: 'middle', t: 13, peso: c.pasos ? 700 : 500 }))
  svg.push(texto(cx, Y_CHIP + 46, c.que, { an: 'middle', mono: true, t: 9.5, c: T.medio }))
  if (!c.pasos) {
    svg.push(`<path d="M ${cx} ${Y_CHIP + H_CHIP} V ${Y_CHIP + H_CHIP + 11}" stroke="${T.suave}" stroke-width="1"/>`)
    svg.push(`<path d="M ${cx - 20} ${Y_CHIP + H_CHIP + 12} H ${cx + 20}" stroke="${T.medio}" stroke-width="2.4" stroke-linecap="round"/>`)
  }
})
svg.push(texto(W - M, Y_CHIP + H_CHIP + 37, 'The other four end at their bar. Only the middle one goes down to the five steps.',
  { an: 'end', mono: true, t: 9, c: T.suave }))
const p1 = CAJAS.p1
const yBaja = Y_CHIP + H_CHIP + 34   // por DEBAJO de las barras de cierre, que van a +12
const canalIzq = G.CANAL_IZQ
const bajada = `M ${xCod} ${Y_CHIP + H_CHIP} V ${yBaja} H ${canalIzq} V ${p1.cy} H ${p1.x}`
svg.push(`<path class="e" data-de="l-code" data-a="p1" d="${bajada}" fill="none" stroke="${T.tinta}" stroke-width="1.4" marker-end="url(#fi)"/>`)
svg.push(`<path class="flujo" data-de="l-code" data-a="p1" d="${bajada}" pointer-events="none"/>`)

COLUMNAS.forEach((c, i) => {
  const x = G.colX(i), w = G.ANCHOS[i]
  svg.push(texto(x + G.PAD, G.Y_EJE + 20, c.nom, { mono: true, t: 10.5, esp: .8, peso: 600, c: T.medio }))
  if (i) svg.push(`<path d="M ${x - G.COLGAP / 2} ${G.Y_EJE + 28} V ${G.Y_FIN_CARRILES}" stroke="${T.linea}" stroke-width="1" stroke-dasharray="2 4"/>`)
})
ACTORES.forEach((a, i) => {
  const y = G.carrilY(i)
  if (i % 2) svg.push(`<rect x="${M}" y="${y}" width="${W - 2 * M}" height="${G.ALTO_CARRIL}" fill="rgba(26,26,24,.022)"/>`)
  svg.push(`<path d="M ${M} ${y} H ${W - M}" stroke="${T.linea}" stroke-width="1"/>`)
  svg.push(texto(M, y + 38, a.nom, { mono: true, t: 11.5, peso: 700, esp: .4 }))
  svg.push(texto(M, y + 54, a.sub, { mono: true, t: 9, c: T.suave }))
})
svg.push(`<path d="M ${M} ${G.Y_FIN_CARRILES} H ${W - M}" stroke="${T.linea}" stroke-width="1"/>`)

const ESTILO = {
  flujo:    { c: T.medio, w: 1.15, guion: '',        puntos: true,  marker: 'f'  },
  puerta:   { c: T.tinta, w: 1.6,  guion: '',        puntos: true,  marker: 'fi' },
  desvio:   { c: T.suave, w: 1.1,  guion: '4 3',     puntos: false, marker: 'f'  },
  retorno:  { c: T.medio, w: 1.3,  guion: '5 4',     puntos: false, marker: 'f'  },
  paralelo: { c: T.medio, w: 1.3,  guion: '9 5',     puntos: true,  marker: 'f'  },
}
const ANCHO_CHAR = 8.5 * 0.60 + 0.4
function libre(x, y, ancho, deId, aId) {
  const x0 = x - ancho / 2, x1 = x + ancho / 2
  return !Object.values(CAJAS).some((c) =>
    x0 < c.der + 4 && x1 > c.x - 4 && y > c.y - 5 && y < c.bot + 9)
}
function etiquetaLibre(pts, txt, deId, aId) {
  const ancho = txt.length * ANCHO_CHAR
  const tramos = []
  for (let i = 0; i < pts.length - 1; i++) {
    const [x1, y1] = pts[i], [x2, y2] = pts[i + 1]
    tramos.push({ x1, y1, x2, y2, len: Math.abs(x2 - x1) + Math.abs(y2 - y1), horiz: Math.abs(y2 - y1) < 2 })
  }
  tramos.sort((a, b) => b.len - a.len)
  for (const t of tramos) {
    for (const f of [0.5, 0.32, 0.68]) {
      const mx = t.x1 + (t.x2 - t.x1) * f, my = t.y1 + (t.y2 - t.y1) * f
      for (const dy of t.horiz ? [-9, 15, -(G.NH / 2 + 14), G.NH / 2 + 16] : [0]) {
        const x = t.horiz ? mx : mx + 8 + ancho / 2
        const y = my + (t.horiz ? dy : -6)
        if (libre(x, y, ancho, deId, aId)) return { x: t.horiz ? mx : mx + 8, y, an: t.horiz ? 'middle' : 'start' }
      }
    }
  }
  return null
}

for (const a of ARISTAS) {
  const pts = G.puntos(a), dd = G.d(pts), e = ESTILO[a.tipo] || ESTILO.flujo
  svg.push(`<path class="e" data-de="${a.de}" data-a="${a.a}" d="${dd}" fill="none" stroke="${e.c}" stroke-width="${e.w}"${e.guion ? ` stroke-dasharray="${e.guion}"` : ''} marker-end="url(#${e.marker})"/>`)
  if (e.puntos) svg.push(`<path class="flujo" data-de="${a.de}" data-a="${a.a}" d="${dd}" pointer-events="none"/>`)
  if (a.etiqueta) {
    const l = etiquetaLibre(pts, a.etiqueta, a.de, a.a)
    if (l) svg.push(texto(l.x, l.y, a.etiqueta, { an: l.an, mono: true, t: 8.5, esp: .4, c: T.suave }))
    else console.warn(`  no room for the label "${a.etiqueta}" of ${a.de}->${a.a}`)
  }
}

for (const n of NODOS) {
  const b = CAJAS[n.id]
  const esPuerta = PUERTAS.some((g) => g.id === n.id)
  const fill = n.fuerte ? T.fill2 : n.desvio ? 'rgba(26,26,24,.02)' : T.carta
  const trazo = n.fuerte ? T.tinta : esPuerta ? 'rgba(26,26,24,.45)' : T.linea
  svg.push(`<g class="n" data-nodo="${n.id}" tabindex="0">`)
  svg.push(`<rect x="${b.x}" y="${b.y}" width="${b.w}" height="${b.h}" rx="6" fill="${fill}" stroke="${trazo}" stroke-width="${n.fuerte ? 1.6 : 1}"${n.desvio ? ' stroke-dasharray="4 3"' : ''}/>`)
  const et = (n.num ? n.num + '. ' : '') + n.titulo
  svg.push(texto(b.cx, b.y + 19, et, { an: 'middle', t: 11.5, peso: n.fuerte ? 700 : 550 }))
  const maxC = Math.floor((b.w - 14) / ANCHO_CHAR)
  const lineas = []; let cur = ''
  for (const pal of n.sub.split(' ')) {
    if ((cur + ' ' + pal).trim().length > maxC) { lineas.push(cur); cur = pal } else cur = (cur + ' ' + pal).trim()
    if (lineas.length === 2) break
  }
  if (lineas.length < 2 && cur) lineas.push(cur)
  if (lineas.length === 2 && lineas.join(' ').length < n.sub.length) lineas[1] = lineas[1].slice(0, maxC - 1) + '…'
  lineas.forEach((ln, i) => svg.push(texto(b.cx, b.y + 34 + i * 12, ln, { an: 'middle', mono: true, t: 8.5, c: T.medio })))
  svg.push(`</g>`)
}

const LEY = [
  ['puerta',   'Gate. Crosses lanes and blocks'],
  ['retorno',  'If a gate fails, back to the step'],
  ['flujo',    'The real path'],
  ['desvio',   'Conditional detour'],
  ['paralelo', 'Runs in parallel and blind'],
]
const xLey = G.colX(3)
LEY.forEach(([k, txt], i) => {
  const y = G.Y_RETORNO + 16 + i * 15, e = ESTILO[k]
  svg.push(`<path d="M ${xLey} ${y} H ${xLey + 26}" stroke="${e.c}" stroke-width="${e.w}"${e.guion ? ` stroke-dasharray="${e.guion}"` : ''}/>`)
  svg.push(texto(xLey + 34, y + 3.5, txt, { mono: true, t: 9, c: T.medio }))
})

svg.push(`<path d="M ${M} ${G.Y_TRANS} H ${W - M}" stroke="${T.tinta}" stroke-width="1.4"/>`)
svg.push(texto(M, G.Y_TRANS + 18, 'THE THREE TRANSVERSAL RULES · THEY HOLD OVER EVERY LANE, THEY ARE NOT ANOTHER STEP',
  { mono: true, t: 9, esp: 1.1, c: T.medio }))
TRANSVERSALES.forEach((t, i) => {
  const x = M + i * ((W - 2 * M) / 3)
  svg.push(texto(x, G.Y_TRANS + 44, String(i + 1), { mono: true, t: 15, peso: 700, c: T.suave }))
  const pal = t.split(' '); const mitad = []
  let l = ''; for (const p of pal) { if ((l + ' ' + p).length > 42) { mitad.push(l); l = p } else l = l ? l + ' ' + p : p } mitad.push(l)
  mitad.forEach((ln, j) => svg.push(texto(x + 18, G.Y_TRANS + 40 + j * 15, ln, { t: 11.5 })))
})

const RELAC = {}
for (const n of NODOS) {
  const s = new Set([n.id])
  for (const a of ARISTAS) { if (a.de === n.id) s.add(a.a); if (a.a === n.id) s.add(a.de) }
  RELAC[n.id] = [...s]
}

const html = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>PRISMA, the method</title>
<style>
*{box-sizing:border-box}
body{margin:0;background:${T.papel};color:${T.tinta};font-family:${SANS};overflow:hidden}
#lienzo{width:100vw;height:100vh;cursor:grab}#lienzo.arrastrando{cursor:grabbing}
svg{display:block;touch-action:none}
.n{cursor:pointer;outline:none}
.n,.e,.flujo{transition:opacity .13s}
.e,.flujo{pointer-events:none}
.dim{opacity:.13}
.flujo{fill:none;stroke:${T.tinta};stroke-width:3;stroke-linecap:round;
  stroke-dasharray:0.01 21.99;stroke-dashoffset:22;animation:viaje .34s linear infinite}
@keyframes viaje{to{stroke-dashoffset:0}}
body.quieto .flujo{animation-play-state:paused}
@media (prefers-reduced-motion:reduce){.flujo{display:none}}
aside{position:fixed;right:16px;top:16px;bottom:16px;width:392px;background:${T.carta};
  border:1px solid ${T.linea};border-radius:10px;padding:24px 22px;overflow:auto;
  transform:translateX(112%);transition:transform .34s cubic-bezier(.22,1,.36,1)}
body.con-ficha aside{transform:none}
aside h2{margin:0 0 12px;font-family:${MONO};font-size:11px;letter-spacing:1.1px;text-transform:uppercase;color:${T.tinta}}
aside p{margin:0 0 11px;font-size:13.5px;line-height:1.55;color:${T.tinta}}
aside .skill{margin-top:16px;padding-top:12px;border-top:1px solid ${T.linea};
  font-family:${MONO};font-size:10px;color:${T.medio};word-break:break-word;line-height:1.5}
.btn{position:fixed;bottom:18px;border:1px solid ${T.linea};background:${T.carta};
  color:${T.medio};border-radius:999px;padding:8px 15px;font-family:${MONO};font-size:10px;
  cursor:pointer;transition:right .34s cubic-bezier(.22,1,.36,1)}
#rest{right:74px}#pausa{right:18px;padding:8px 12px}
.firma{position:fixed;left:18px;bottom:18px;font-family:${MONO};font-size:9px;letter-spacing:1.2px;color:${T.suave}}
#bus{position:fixed;left:50%;top:24%;transform:translateX(-50%) scale(.97);width:min(480px,88vw);
  background:${T.carta};border:1px solid ${T.linea};border-radius:10px;padding:7px;
  opacity:0;pointer-events:none;transition:opacity .16s,transform .16s;z-index:60}
body.buscando #bus{opacity:1;pointer-events:auto;transform:translateX(-50%) scale(1)}
#bus input{width:100%;border:0;background:transparent;color:${T.tinta};font-size:15px;padding:9px;outline:none;font-family:${MONO}}
#bus li{list-style:none;padding:8px 10px;border-radius:6px;font-family:${MONO};font-size:11px;letter-spacing:.6px;cursor:pointer}
#bus li.sel{background:${T.fill2}}
#bus ul{margin:5px 0 0;padding:0;max-height:42vh;overflow:auto}
</style></head><body>
<div id="lienzo"><svg id="s" viewBox="0 0 ${W} ${ALTO}" width="${W}" height="${ALTO}">
<defs>
  <marker id="f" markerWidth="7" markerHeight="7" refX="5.5" refY="3.5" orient="auto"><path d="M0,0 L6,3.5 L0,7 z" fill="${T.medio}"/></marker>
  <marker id="fi" markerWidth="7" markerHeight="7" refX="5.5" refY="3.5" orient="auto"><path d="M0,0 L6,3.5 L0,7 z" fill="${T.tinta}"/></marker>
</defs>
${svg.join('\n')}
</svg></div>
<aside id="ficha"><h2 id="ft"></h2><div id="fc"></div><div class="skill" id="fs"></div></aside>
<div class="firma">PRISMA</div>
<button class="btn" id="rest">Reset</button>
<button class="btn" id="pausa" title="Pause the motion">&#9208;</button>
<div id="bus"><input id="bi" placeholder="Find a step..." autocomplete="off"><ul id="bl"></ul></div>
<script>
const FICHAS=${JSON.stringify(FICHAS)},RELAC=${JSON.stringify(RELAC)};
const NOM=${JSON.stringify(NODOS.map((n) => ({ id: n.id, t: (n.num ? n.num + '. ' : '') + n.titulo })))};
const S=document.getElementById('s'),B=document.body,VB0={x:0,y:0,w:${W},h:${ALTO}};
let vb={...VB0},tocado=null,arr=false,px=0,py=0,movido=false;
const setVB=()=>S.setAttribute('viewBox',vb.x+' '+vb.y+' '+vb.w+' '+vb.h);
function abrir(id){
  const f=FICHAS[id]; if(!f) return;
  document.getElementById('ft').textContent=f.t;
  document.getElementById('fc').innerHTML=f.c.map(function(p){return '<p>'+p+'</p>'}).join('');
  document.getElementById('fs').textContent=f.skill||'';
  B.classList.add('con-ficha');
  const rel=RELAC[id]||[id];
  document.querySelectorAll('.n').forEach(function(n){n.classList.toggle('dim',rel.indexOf(n.dataset.nodo)<0)});
  document.querySelectorAll('.e,.flujo').forEach(function(e){
    e.classList.toggle('dim',!(rel.indexOf(e.dataset.de)>=0&&rel.indexOf(e.dataset.a)>=0))});
}
function cerrar(){B.classList.remove('con-ficha');
  document.querySelectorAll('.dim').forEach(function(x){x.classList.remove('dim')})}
S.addEventListener('pointerdown',function(ev){
  const g=ev.target.closest('.n'); tocado=g?g.dataset.nodo:null;
  arr=true;px=ev.clientX;py=ev.clientY;S.setPointerCapture(ev.pointerId);
  document.getElementById('lienzo').classList.add('arrastrando')});
S.addEventListener('pointermove',function(ev){
  if(!arr)return; const dx=ev.clientX-px,dy=ev.clientY-py;
  if(Math.abs(dx)+Math.abs(dy)>4)movido=true;
  const k=vb.w/S.clientWidth; vb.x-=dx*k; vb.y-=dy*k; px=ev.clientX; py=ev.clientY; setVB()});
S.addEventListener('pointerup',function(){
  arr=false; document.getElementById('lienzo').classList.remove('arrastrando');
  if(!movido){ if(tocado)abrir(tocado); else cerrar() } movido=false; tocado=null});
S.addEventListener('wheel',function(ev){
  ev.preventDefault(); const f=ev.deltaY>0?1.09:0.917;
  const pt=S.createSVGPoint(); pt.x=ev.clientX; pt.y=ev.clientY;
  const p=pt.matrixTransform(S.getScreenCTM().inverse());
  vb.x=p.x-(p.x-vb.x)*f; vb.y=p.y-(p.y-vb.y)*f; vb.w*=f; vb.h*=f; setVB()},{passive:false});
document.getElementById('rest').addEventListener('click',function(){vb={...VB0};setVB();cerrar()});
document.getElementById('pausa').addEventListener('click',function(){B.classList.toggle('quieto')});
const bi=document.getElementById('bi'),bl=document.getElementById('bl');
let sel=0,res=[];
function pintar(){
  res=NOM.filter(function(n){return n.t.toLowerCase().indexOf(bi.value.toLowerCase())>=0});
  bl.innerHTML=res.map(function(n,i){return '<li class="'+(i===sel?'sel':'')+'" data-id="'+n.id+'">'+n.t+'</li>'}).join('')}
bl.addEventListener('click',function(ev){const li=ev.target.closest('li');
  if(li){abrir(li.dataset.id);B.classList.remove('buscando')}});
bi.addEventListener('input',function(){sel=0;pintar()});
document.addEventListener('keydown',function(ev){
  if(ev.key==='Escape'){B.classList.remove('buscando');cerrar();return}
  if((ev.key==='/'&&!B.classList.contains('buscando'))||(ev.key==='k'&&(ev.metaKey||ev.ctrlKey))){
    ev.preventDefault();B.classList.add('buscando');bi.value='';sel=0;pintar();bi.focus();return}
  if(!B.classList.contains('buscando'))return;
  if(ev.key==='ArrowDown'){sel=Math.min(sel+1,res.length-1);pintar();ev.preventDefault()}
  if(ev.key==='ArrowUp'){sel=Math.max(sel-1,0);pintar();ev.preventDefault()}
  if(ev.key==='Enter'&&res[sel]){abrir(res[sel].id);B.classList.remove('buscando')}});
pintar();
</script></body></html>`

fs.writeFileSync(path.join(HERE, 'index.html'), html)
const staticSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${ALTO}" width="${W}" height="${ALTO}" font-family="${SANS}">
<rect width="${W}" height="${ALTO}" fill="${T.papel}"/>
<defs>
  <marker id="f" markerWidth="7" markerHeight="7" refX="5.5" refY="3.5" orient="auto"><path d="M0,0 L6,3.5 L0,7 z" fill="${T.medio}"/></marker>
  <marker id="fi" markerWidth="7" markerHeight="7" refX="5.5" refY="3.5" orient="auto"><path d="M0,0 L6,3.5 L0,7 z" fill="${T.tinta}"/></marker>
</defs>
${svg.filter((s) => !s.includes('class="flujo"')).join('\n')}
</svg>`
fs.writeFileSync(path.join(HERE, '..', 'assets', 'prisma-flow.svg'), staticSvg.replaceAll('"Helvetica Neue"', "'Helvetica Neue'"))
console.log(`index.html ${(html.length / 1024).toFixed(1)} KB and assets/prisma-flow.svg ${(staticSvg.length / 1024).toFixed(1)} KB · ${W}x${ALTO} · ${NODOS.length} boxes in ${ACTORES.length} lanes · ${ARISTAS.length} edges`)
