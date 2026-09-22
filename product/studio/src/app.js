/* ═══════════════════════════════════════════════════════════════════════════
   STUDIO — the interface, pasted onto an infinite canvas.

     PARTS     the app's controls lying loose on the ground, drawn live.
     CARDS     frames carrying a treatment — format, layout, surface, register.
     TIMELINE  cards put in an order, and fused into motion.

   Drag a part onto a card: the card takes the subject and keeps its treatment,
   and the part stays where it is. Drop cards into the timeline and fuse them:
   the manner of each move is read from what changes between the two shots.
   ═══════════════════════════════════════════════════════════════════════════ */
import { createWorld } from './world.js';
import { COMPONENTS, byId, plate, image, encode, LAYOUTS, ANATOMY, GENERATIONS, inGen } from './components.js';
import { words, REGISTERS } from './copy.js';
import { variants, nudge, FORMATS, formatOf } from './combine.js';
import { fuse, render as renderFused, sample, MANNERS, frameCount } from './timeline.js';
import { ask, probe, MODEL, KINDS } from './ask.js';
import { el, Button, Toggle, Select, Slider, Field, Badge, Separator, Accordion, Empty, Tabs } from './ui.js';

const $ = s => document.querySelector(s);
const ground = $('#ground'), plane = $('#plane');
const ims = ['../assets/pointing.png', '../assets/review.png'].map(s => image(s, () => redrawAll()));

const WORLD = 1/3, PART_W = 300;
const state = { parts:[], cards:[], shots:[], sel:null, play:false, seq:1, plan:null, t:0, gen:'all' };

/* ⛔ Back the bitmap at the device ratio. A backing store the size of the CSS
   box is half resolution on a Retina display and reads as the whole tool being
   soft. Zoom raises it to a ceiling and re-renders once the camera settles. */
const DPR = Math.min(3, Math.max(1, window.devicePixelRatio || 1));
const quality = () => Math.min(3, DPR * Math.max(1, Math.min(2, world.cam.z)));

const world = createWorld(ground, plane, {
  onSelect: n => select(n ? n.dataset.id : null),
  onNudge: (n, fx, fy) => {
    const node = find(n.dataset.id); if(!node) return;
    const r = n.getBoundingClientRect();
    node.x += fx * r.width / world.cam.z;
    node.y += fy * r.height / world.cam.z;
    place(node);
  },
  onCamera: () => scheduleSharpen(),
});

const wordsOf = n => { const w = words(n.seed, n.register); return n.claim ? { ...w, claim:n.claim } : w; };
const all = () => state.parts.concat(state.cards);
const find = id => all().find(n => n.id === id);
const maxY = () => state.cards.reduce((m, c) => Math.max(m, c.y), 0);

/* ── geometry + drawing ──────────────────────────────────────────────────── */
function sizeOf(n){
  if(n.kind === 'part'){ const c = byId(n.comp); return { w:PART_W, h:Math.round(PART_W * (c.tall || .62)) }; }
  const f = formatOf(n.format);
  return { w:Math.round(f.w * WORLD), h:Math.round(f.h * WORLD) };
}
function place(n){
  const { w, h } = sizeOf(n);
  n.el.style.transform = `translate3d(${n.x}px,${n.y}px,0)`;
  n.el.style.width = w + 'px'; n.el.style.height = h + 'px';
}
function draw(n){
  const { w, h } = sizeOf(n), q = quality();
  const bw = Math.round(w*q), bh = Math.round(h*q);
  if(n.cv.width !== bw || n.cv.height !== bh){ n.cv.width = bw; n.cv.height = bh; }
  const x = n.cv.getContext('2d');
  x.setTransform(1,0,0,1,0,0); x.clearRect(0,0,bw,bh); x.scale(q,q);
  if(n.kind === 'card' && !n.comp) emptyCard(x, w, h, n);
  else plate(x, w, h, n, wordsOf(n), ims, { bare:n.kind === 'part' });
  if(n.tag) n.tag.textContent = n.kind === 'part'
    ? byId(n.comp).name : `${formatOf(n.format).note} · ${n.comp ? byId(n.comp).name : 'empty'}`;
}
const redrawAll = () => { all().forEach(draw); paintStrip(); };

function emptyCard(x, w, h, n){
  const light = n.theme === 'light';
  x.fillStyle = light ? '#F4F4F4' : '#0F0F0F'; x.fillRect(0,0,w,h);
  x.save();
  x.strokeStyle = light ? 'rgba(10,10,10,.20)' : 'rgba(255,255,255,.20)';
  x.setLineDash([5,5]); x.lineWidth = 1; x.strokeRect(10.5,10.5,w-21,h-21);
  x.fillStyle = light ? 'rgba(10,10,10,.34)' : 'rgba(255,255,255,.34)';
  x.textAlign = 'center';
  x.font = '500 11px Geist, system-ui, sans-serif';
  if('letterSpacing' in x) x.letterSpacing = '.04em';
  x.fillText('DROP A PART', w/2, h/2 - 4);
  x.font = '400 11px Geist, system-ui, sans-serif';
  if('letterSpacing' in x) x.letterSpacing = '0em';
  x.fillText(`${formatOf(n.format).name} · ${(LAYOUTS.find(l=>l.id===n.layout)||{}).name||''}`, w/2, h/2 + 16);
  x.restore();
}
let sharpenT = 0;
const scheduleSharpen = () => { clearTimeout(sharpenT); sharpenT = setTimeout(() => { if(!state.play) redrawAll(); }, 180); };

/* ── nodes ───────────────────────────────────────────────────────────────── */
function node(kind, spec){
  const n = {
    id:'n' + (state.seq++), kind,
    comp: spec.comp ?? null,
    phase: spec.phase ?? (spec.comp ? byId(spec.comp).rest : 1),
    reveal: spec.reveal ?? 1,
    scale: spec.scale ?? 1,
    theme: spec.theme || 'dark',
    register: spec.register || 'product',
    layout: spec.layout || 'titled',
    format: spec.format || 'feed',
    seed: spec.seed ?? +(Math.random().toFixed(4)),
    gen: spec.gen || (spec.comp ? (byId(spec.comp).gen || 'v1') : null),
    layoutSpec: spec.layoutSpec || null,
    claim: spec.claim || null,
    x: spec.x || 0, y: spec.y || 0,
  };
  const wrap = el('div', 'node ' + kind, plane);
  wrap.dataset.id = n.id;
  n.el = wrap; n.cv = el('canvas', '', wrap); n.tag = el('div', 'tag', wrap);
  (kind === 'part' ? state.parts : state.cards).push(n);
  place(n); draw(n);
  return n;
}
/* the two generations sit side by side so progress is a thing you can see,
   not a thing you have to remember */
const GEN_X = { v1:0, v2:760 };
const FRAMES_X = 1520;

function buildParts(){
  const cols = 2, gapX = PART_W + 54, gap = 46, LABEL = 26;
  GENERATIONS.forEach(g => {
    const y = new Array(cols).fill(0);
    inGen(g.id).forEach(c => {
      const col = y.indexOf(Math.min(...y));
      const n = node('part', { comp:c.id, theme:'light', gen:g.id,
        x:GEN_X[g.id] + col*gapX, y:y[col] });
      y[col] += sizeOf(n).h + LABEL + gap;
    });
    cluster(`${g.id} · ${g.name}`, GEN_X[g.id] - 4, -54);
  });
}
function buildCards(list){
  const f = formatOf('feed'), w = f.w*WORLD + 54, h = f.h*WORLD + 74;
  list.forEach((v, i) => node('card', { ...v, x:FRAMES_X + (i%4)*w, y:Math.floor(i/4)*h }));
  cluster('Frames', FRAMES_X - 4, -54);
}

/* the tab hides the generation you are not looking at and frames the one you
   are; the nodes are not destroyed, so a hidden part keeps its place */
function showGen(g){
  state.gen = g;
  state.parts.forEach(n => n.el.classList.toggle('off', g !== 'all' && n.gen !== g));
  document.querySelectorAll('.cluster').forEach(c => {
    const owns = c.dataset.gen;
    c.classList.toggle('off', !!owns && g !== 'all' && owns !== g);
  });
  const vis = state.parts.filter(n => !n.el.classList.contains('off'));
  if(vis.length) world.fitRect(unionOf(vis), .12);
}
function unionOf(list){
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  list.forEach(n => {
    const { w, h } = sizeOf(n);
    x0 = Math.min(x0, n.x); y0 = Math.min(y0, n.y);
    x1 = Math.max(x1, n.x + w); y1 = Math.max(y1, n.y + h);
  });
  return { x:x0, y:y0 - 60, w:Math.max(1, x1-x0), h:Math.max(1, y1-y0+60) };
}
function cluster(text, x, y){
  const d = el('div', 'cluster', plane); d.textContent = text;
  const g = String(text).split(' ')[0];
  if(g === 'v1' || g === 'v2') d.dataset.gen = g;
  d.style.transform = `translate3d(${x}px,${y}px,0)`;
}

/* ── dragging a part onto a card ─────────────────────────────────────────── */
let drag = null;
plane.addEventListener('pointerdown', e => {
  const pe = e.target.closest('.node.part');
  if(!pe || e.button !== 0) return;
  const p = find(pe.dataset.id); if(!p) return;
  e.stopPropagation();
  drag = { part:p, moved:false, x:e.clientX, y:e.clientY };
  plane.setPointerCapture(e.pointerId);
}, true);
plane.addEventListener('pointermove', e => {
  if(!drag) return;
  if(!drag.moved){
    if(Math.hypot(e.clientX-drag.x, e.clientY-drag.y) < 5) return;
    drag.moved = true;
    drag.ghost = el('div', 'drag-chip', document.body);
    drag.ghost.textContent = byId(drag.part.comp).name;
  }
  drag.ghost.style.transform = `translate3d(${e.clientX+12}px,${e.clientY+12}px,0)`;
  const over = document.elementFromPoint(e.clientX, e.clientY)?.closest('.node.card');
  state.cards.forEach(c => c.el.classList.toggle('over', c.el === over));
}, true);
plane.addEventListener('pointerup', e => {
  if(!drag) return;
  const d = drag; drag = null;
  d.ghost && d.ghost.remove();
  state.cards.forEach(c => c.el.classList.remove('over'));
  if(!d.moved) return select(d.part.id);
  const over = document.elementFromPoint(e.clientX, e.clientY)?.closest('.node.card');
  const card = over && find(over.dataset.id);
  if(!card) return;
  card.comp = d.part.comp; card.phase = byId(card.comp).rest;
  draw(card); select(card.id); paintStrip();
}, true);
plane.addEventListener('pointercancel', () => { drag && drag.ghost && drag.ghost.remove(); drag = null; }, true);

/* ── selection ───────────────────────────────────────────────────────────── */
function select(id){
  state.sel = id;
  all().forEach(n => n.el.classList.toggle('sel', n.id === id));
  inspector();
}

/* ── inspector ───────────────────────────────────────────────────────────── */
function inspector(){
  const host = $('#insp'); host.innerHTML = '';
  const n = find(state.sel);
  if(!n){
    Empty(host, { title:'Nothing selected',
      body:'Drag a <b>part</b> onto a <b>card</b>. The card keeps its treatment and takes the subject.<br><br>Ground pans · ⌘-scroll zooms · double-click frames' });
    return;
  }
  const head = el('div', 'insp-h', host);
  Badge(head, n.kind, n.kind === 'part' ? 'muted' : 'solid');
  el('h2', 'insp-t', head).textContent = n.comp ? byId(n.comp).name : 'Empty card';
  if(n.comp) el('p', 'insp-j', host).textContent = byId(n.comp).job;

  const acc = Accordion(host, { single:true });

  /* SUBJECT — what it is */
  if(n.kind === 'card'){
    const sub = acc.add('Subject', { open:!n.comp });
    const f = Field(sub.body, 'Component');
    Select(f, { value:n.comp || '', options:[{value:'',label:'— empty —'},
      ...COMPONENTS.map(c => ({ value:c.id, label:c.name }))],
      onChange:v => { n.comp = v || null; if(v) n.phase = byId(v).rest; draw(n); inspector(); paintStrip(); } });
    const r = Field(sub.body, 'Register', 'the words it speaks');
    Select(r, { value:n.register, options:REGISTERS.map(k => ({ value:k.id, label:k.name })),
      onChange:v => { n.register = v; draw(n); paintStrip(); } });
    Button(sub.body, { label:'Reseed words', variant:'ghost',
      onClick:() => { n.seed = +(Math.random().toFixed(4)); draw(n); paintStrip(); } });
  }

  /* TREATMENT — how it is framed */
  if(n.kind === 'card'){
    const tr = acc.add('Treatment', { open:!!n.comp });
    const f = Field(tr.body, 'Format');
    Select(f, { value:n.format, options:FORMATS.map(k => ({ value:k.id, label:`${k.name} · ${k.note}` })),
      onChange:v => { n.format = v; place(n); draw(n); paintStrip(); } });
    const l = Field(tr.body, 'Layout', (LAYOUTS.find(k=>k.id===n.layout)||{}).job);
    Select(l, { value:n.layout, options:LAYOUTS.map(k => ({ value:k.id, label:k.name })),
      onChange:v => { n.layout = v; draw(n); inspector(); paintStrip(); } });
    const s = Field(tr.body, 'Surface');
    Toggle(s, { value:n.theme, options:[{value:'dark',label:'Dark'},{value:'light',label:'Light'}],
      onChange:v => { n.theme = v; draw(n); paintStrip(); } });
  } else {
    const s = Field(acc.add('Treatment', { open:false }).body, 'Surface');
    Toggle(s, { value:n.theme, options:[{value:'dark',label:'Dark'},{value:'light',label:'Light'}],
      onChange:v => { n.theme = v; draw(n); } });
  }

  /* MOTION — the two axes that move */
  const mo = acc.add('Motion', { open:false });
  const m = Field(mo.body, 'Moment', 'where it is in its own behaviour');
  Slider(m, { value:n.phase, onInput:v => { n.phase = v; draw(n); paintStrip(); } });
  const rv = Field(mo.body, 'Reveal', 'how much of its anatomy is disclosed');
  Slider(rv, { value:n.reveal, onInput:v => { n.reveal = v; draw(n); paintStrip(); } });
  const sc = Field(mo.body, 'Scale');
  Slider(sc, { min:.5, max:1.6, value:n.scale, onInput:v => { n.scale = v; draw(n); paintStrip(); } });

  /* ANATOMY — cascading disclosure, in the order reveal discloses it */
  if(n.comp && ANATOMY[n.comp]){
    const an = acc.add('Anatomy', { open:false, count:ANATOMY[n.comp].length });
    const list = el('ol', 'anat', an.body);
    ANATOMY[n.comp].forEach((t, i) => {
      const li = el('li', '', list);
      el('span', 'anat-n', li).textContent = String(i + 1);
      el('span', 'anat-t', li).textContent = t;
      const at = (i + 1) / ANATOMY[n.comp].length;
      const b = Button(li, { label:'reveal', variant:'ghost',
        onClick:() => { n.reveal = at; draw(n); inspector(); } });
      b.classList.toggle('on', n.reveal >= at - .001);
    });
  }

  /* EXPLORE — ask for a layout, a sweep of treatments, or a sequence */
  if(n.comp){
    const ex = acc.add('Explore', { open:false });
    const noteF = Field(ex.body, 'What do you want', 'optional — left blank it proposes freely');
    const note = el('input', 'ask-note', noteF);
    note.placeholder = 'tighter, more editorial, less chrome…';

    const row = el('div', 'ask-row', ex.body);
    KINDS.forEach(k => Button(row, { label:k.name, title:k.job,
      variant: k.id === 'variations' ? 'default' : 'secondary',
      onClick: e => run(k.id, n, note.value.trim(), e.currentTarget) }));

    const out = el('div', 'ask-out', ex.body);
    out.id = 'ask-out';
    const st = el('p', 'ask-state', out);
    st.textContent = MODEL.ready ? 'Model connected.'
      : `No model — proposing locally. ${MODEL.detail || ''}`;
    st.classList.toggle('dim', !MODEL.ready);
  }

  Separator(host);
  const acts = el('div', 'acts', host);
  if(n.kind === 'part'){
    Button(acts, { label:'New card', variant:'default', onClick:() => {
      const c = node('card', { comp:n.comp, theme:'dark', x:n.x + 900, y:n.y });
      select(c.id); world.fitRect(world.worldRect(c.el), .25);
    }});
    Button(acts, { label:'10 treatments', onClick:() => {
      const f = formatOf('feed'), w = f.w*WORLD+54, h = f.h*WORLD+74;
      const y0 = state.cards.length ? maxY() + h : 0;
      const made = variants(10, { comp:n.comp }).map((v,i) =>
        node('card', { ...v, comp:n.comp, x:820 + (i%4)*w, y:y0 + Math.floor(i/4)*h }));
      made[0] && select(made[0].id); world.fitAll();
    }});
  } else {
    Button(acts, { label:'Add to timeline', variant:'default', onClick:() => addShot(n) });
    Button(acts, { label:'Vary', onClick:() => { Object.assign(n, nudge(n)); draw(n); inspector(); paintStrip(); }});
    if(n.layoutSpec) Button(acts, { label:'Drop layout', variant:'ghost',
      onClick:() => { n.layoutSpec = null; draw(n); inspector(); }});
    Button(acts, { label:'Duplicate', onClick:() => select(node('card', { ...n, x:n.x+40, y:n.y+40 }).id) });
    Button(acts, { label:'Export', onClick:() => exportNode(n) });
    Button(acts, { label:'Delete', variant:'destructive', onClick:() => {
      n.el.remove(); state.cards = state.cards.filter(k => k !== n);
      state.shots = state.shots.filter(s => s.from !== n.id); select(null); refuse();
    }});
  }
  if(n.comp){ const c = el('div', 'code', host); c.textContent = encode(n); }
}

/* ── running an ask ──────────────────────────────────────────────────────
   Whatever comes back is applied to the canvas as ordinary nodes, so a
   proposal is something you can then edit, vary and export like anything else.
   Nothing arrives that the studio could not have made by hand. */
async function run(kind, n, note, btn){
  const out = document.getElementById('ask-out');
  const say = (msg, tone) => { if(out) out.innerHTML = `<p class="ask-state ${tone||''}">${msg}</p>`; };
  btn && (btn.disabled = true);
  say('Thinking…', 'dim');
  try{
    const r = await ask(kind, n, note);
    const badge = r.source === 'model' ? 'model' : r.source === 'fallback' ? 'fell back' : 'local';

    if(kind === 'layout'){
      n.layoutSpec = r.spec; draw(n); paintStrip();
      say(`<b>${badge}</b> · ${r.spec.name} — ${r.why || r.spec.job}` +
          (r.detail ? `<br><span class="dim">${r.detail}</span>` : ''));
    }
    else if(kind === 'variations'){
      const f = formatOf('feed'), w = f.w*WORLD+54, h = f.h*WORLD+74;
      const y0 = state.cards.length ? maxY() + h : 0;
      const made = r.variants.map((v, i) => node('card', {
        ...v, comp:n.comp, layoutSpec:null,
        x:FRAMES_X + (i%4)*w, y:y0 + Math.floor(i/4)*h }));
      made[0] && select(made[0].id);
      world.fitAll();
      say(`<b>${badge}</b> · ${made.length} treatments — ${r.why || ''}` +
          (r.detail ? `<br><span class="dim">${r.detail}</span>` : ''));
      return;
    }
    else {
      state.shots = r.shots.map(sh => ({ from:n.id, comp:n.comp, register:n.register,
        format:n.format, seed:n.seed, claim:n.claim, layoutSpec:n.layoutSpec, ...sh }));
      state.plan = fuse(state.shots, { hold:r.hold });
      paintStrip(); paintMeta(); scrubTo(0);
      document.getElementById('dock').classList.add('open');
      play(true);
      say(`<b>${badge}</b> · ${r.shots.length} shots — ${r.why || ''}` +
          (r.detail ? `<br><span class="dim">${r.detail}</span>` : ''));
    }
  } catch(e){
    say(`Could not propose: ${e.message}`, '');
  } finally { btn && (btn.disabled = false); }
}

/* ── export ──────────────────────────────────────────────────────────────── */
function exportNode(n){
  if(!n.comp) return;
  const f = formatOf(n.format);
  const cv = document.createElement('canvas');
  cv.width = f.w; cv.height = f.h;
  plate(cv.getContext('2d'), f.w, f.h, n, wordsOf(n), ims);
  cv.toBlob(b => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(b);
    a.download = `pass-${n.comp}-${f.id}-${n.layout}.png`;
    a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  }, 'image/png');
}

/* ═══════════════════════════════ TIMELINE ═══════════════════════════════ */
const shotSpec = n => ({ from:n.id, comp:n.comp, phase:n.phase, reveal:n.reveal, scale:n.scale,
  theme:n.theme, register:n.register, layout:n.layout, layoutSpec:n.layoutSpec, claim:n.claim,
  format:n.format, seed:n.seed });

function addShot(n){
  if(!n.comp) return;
  state.shots.push(shotSpec(n));
  refuse(); $('#dock').classList.add('open');
}
function refuse(){
  state.plan = state.shots.length ? fuse(state.shots) : null;
  paintStrip(); paintMeta();
}

function paintMeta(){
  const n = state.shots.length;
  $('#tl-count').textContent = n ? `${n} shot${n>1?'':''}` : 'no shots';
  $('#tl-dur').textContent = state.plan ? `${(state.plan.total/1000).toFixed(1)}s · ${frameCount(state.plan)} frames` : '';
}

function paintStrip(){
  const strip = $('#strip'); if(!strip) return;
  strip.innerHTML = '';
  if(!state.shots.length){
    Empty(strip, { title:'Timeline is empty',
      body:'Select a card and press <b>Add to timeline</b>. Order the shots, then fuse them.' });
    paintMeta(); return;
  }
  state.shots.forEach((s, i) => {
    if(i > 0 && state.plan){
      const seg = state.plan.segments.find(g => g.kind === 'move' && g.b === i);
      const j = el('div', 'join', strip);
      j.innerHTML = `<span class="join-l"></span>`;
      const b = Badge(j, (MANNERS[seg?.manner] || {}).name || '—');
      b.title = (MANNERS[seg?.manner] || {}).job || '';
      el('span', 'join-l', j);
    }
    const chip = el('div', 'shot', strip);
    chip.draggable = true; chip.dataset.i = i;
    const cv = el('canvas', '', chip);
    const W = 78, H = Math.round(W * formatOf(s.format).h / formatOf(s.format).w);
    cv.width = W*2; cv.height = H*2;
    cv.style.width = W+'px'; cv.style.height = H+'px';
    const x = cv.getContext('2d'); x.scale(2,2);
    plate(x, W, H, s, s.claim ? { ...words(s.seed, s.register), claim:s.claim } : words(s.seed, s.register), ims);
    el('span', 'shot-n', chip).textContent = byId(s.comp).name;
    const rm = el('button', 'shot-x', chip); rm.textContent = '×';
    rm.onclick = e => { e.stopPropagation(); state.shots.splice(i,1); refuse(); };
    chip.onclick = () => { const c = find(s.from); if(c) select(c.id); scrubTo(shotStart(i)); };
    chip.ondragstart = e => { e.dataTransfer.setData('text/plain', String(i)); chip.classList.add('dragging'); };
    chip.ondragend = () => chip.classList.remove('dragging');
    chip.ondragover = e => { e.preventDefault(); chip.classList.add('over'); };
    chip.ondragleave = () => chip.classList.remove('over');
    chip.ondrop = e => {
      e.preventDefault(); chip.classList.remove('over');
      const from = +e.dataTransfer.getData('text/plain');
      if(from === i) return;
      const [moved] = state.shots.splice(from, 1);
      state.shots.splice(i, 0, moved);
      refuse();
    };
  });
  paintMeta();
}
const shotStart = i => state.plan ? (state.plan.segments.find(s => s.kind === 'hold' && s.a === i)?.t0 ?? 0) : 0;

/* ── the preview ─────────────────────────────────────────────────────────── */
const pv = $('#preview');
function drawPreview(){
  if(!state.plan) { const x = pv.getContext('2d'); x.clearRect(0,0,pv.width,pv.height); return; }
  const s = sample(state.plan, state.t);
  const f = formatOf((s.a || state.shots[0]).format);
  const H = 150, W = Math.round(H * f.w / f.h);
  if(pv.width !== W*2 || pv.height !== H*2){ pv.width = W*2; pv.height = H*2; pv.style.width = W+'px'; pv.style.height = H+'px'; }
  const x = pv.getContext('2d');
  x.setTransform(2,0,0,2,0,0);
  renderFused(x, W, H, state.plan, state.t, ims);
  $('#tl-now').textContent = `${(state.t/1000).toFixed(2)}s`;
  const sc = $('#scrub'); if(sc && !sc.matches(':active')) sc.value = state.plan.total ? state.t / state.plan.total : 0;
}
const scrubTo = t => { state.t = t; drawPreview(); };

let raf = 0, last = 0;
function loop(now){
  if(!state.play) return;
  if(!last) last = now;
  state.t = (state.t + (now - last)) % (state.plan?.total || 1);
  last = now;
  drawPreview();
  raf = requestAnimationFrame(loop);
}
function play(on){
  state.play = on && !!state.plan;
  $('#tl-play').classList.toggle('on', state.play);
  $('#tl-play').querySelector('.lbl').textContent = state.play ? 'Pause' : 'Play';
  last = 0;
  if(state.play) raf = requestAnimationFrame(loop); else cancelAnimationFrame(raf);
}

/* ── board ───────────────────────────────────────────────────────────────── */
const KEY = 'pass.studio.board.v3';
const keep = ({ id, kind, comp, phase, reveal, scale, theme, register, layout, layoutSpec, claim, format, seed, gen, x, y }) =>
  ({ id, kind, comp, phase, reveal, scale, theme, register, layout, layoutSpec, claim, format, seed, gen, x, y });
const serialise = () => JSON.stringify({ cam:world.cam, nodes:all().map(keep), shots:state.shots });
let lastSave = '';
setInterval(() => {
  const s = serialise(); if(s === lastSave) return; lastSave = s;
  try { localStorage.setItem(KEY, s); } catch {}
  $('#saved').textContent = 'saved';
  clearTimeout(window.__st); window.__st = setTimeout(() => $('#saved').textContent = '', 1400);
}, 1200);
function restore(){
  let doc = null;
  try { doc = JSON.parse(localStorage.getItem(KEY) || 'null'); } catch {}
  if(!doc || !doc.nodes?.length) return false;
  doc.nodes.forEach(n => { state.seq = Math.max(state.seq, (+String(n.id).slice(1)||0)+1); node(n.kind, n); });
  GENERATIONS.forEach(g => cluster(`${g.id} · ${g.name}`, GEN_X[g.id] - 4, -54));
  cluster('Frames', FRAMES_X - 4, -54);
  state.shots = doc.shots || [];
  if(!world.setCam(doc.cam)) world.fitAll(false);
  return true;
}

/* ── bar + dock ──────────────────────────────────────────────────────────── */
$('#add-card').onclick = () => {
  const f = formatOf('feed'), h = f.h*WORLD + 74;
  select(node('card', { x:820, y:state.cards.length ? maxY()+h : 0 }).id);
};
$('#gen').onclick = () => {
  const f = formatOf('feed'), w = f.w*WORLD+54, h = f.h*WORLD+74;
  const y0 = state.cards.length ? maxY()+h : 0;
  const made = variants(10).map((v,i) => node('card', { ...v, x:820+(i%4)*w, y:y0+Math.floor(i/4)*h }));
  made[0] && select(made[0].id); world.fitAll();
};
$('#fit').onclick = () => { state.gen = 'all'; genTabs.set('all'); showGen('all'); world.fitAll(); };

const genTabs = Tabs($('#gen-tabs'), {
  value:'all',
  options:[{ value:'all', label:'All' },
           ...GENERATIONS.map(g => ({ value:g.id, label:`${g.id} · ${g.name}` }))],
  onChange:showGen,
});
$('#dock-t').onclick = () => $('#dock').classList.toggle('open');
$('#tl-play').onclick = () => play(!state.play);
$('#tl-fuse').onclick = () => { refuse(); scrubTo(0); };
$('#tl-auto').onclick = () => {
  /* the auto sweep: every card that holds something, ordered so that adjacent
     shots differ in as little as possible — the fusion then has something to
     carry rather than a pile of cuts */
  const cards = state.cards.filter(c => c.comp);
  if(!cards.length) return;
  const rest = cards.slice(1);
  const order = [cards[0]];
  while(rest.length){
    const last = order[order.length-1];
    let best = 0, bestScore = -1;
    rest.forEach((c, i) => {
      const score = (c.comp===last.comp?3:0)+(c.theme===last.theme?2:0)+(c.layout===last.layout?1:0)+(c.format===last.format?1:0);
      if(score > bestScore){ bestScore = score; best = i; }
    });
    order.push(rest.splice(best,1)[0]);
  }
  state.shots = order.map(shotSpec);
  refuse(); scrubTo(0); $('#dock').classList.add('open'); play(true);
};
$('#tl-clear').onclick = () => { state.shots = []; play(false); refuse(); };
$('#scrub').oninput = e => { if(state.plan) scrubTo(+e.target.value * state.plan.total); };

addEventListener('keydown', e => {
  if(e.target.matches('input,select,textarea')) return;
  const n = find(state.sel);
  if(e.key === ' '){ e.preventDefault(); play(!state.play); }
  if(e.key === 'Backspace' && n?.kind === 'card'){
    e.preventDefault(); n.el.remove(); state.cards = state.cards.filter(k=>k!==n); select(null);
  }
  if(e.key === 'f') world.fitAll();
  if(e.key === 'Escape') select(null);
});

window.__studio = { state, find, all, refuse };

/* ── first run ───────────────────────────────────────────────────────────── */
if(!restore()){ buildParts(); buildCards(variants(8)); world.fitAll(false); }
refuse(); inspector(); drawPreview();
probe().then(m => {
  const b = document.getElementById('model-state');
  if(b){ b.textContent = m.ready ? 'model' : 'local'; b.className = 'badge' + (m.ready ? ' solid' : ''); b.title = m.ready ? 'Proposals come from the model' : (m.detail || 'No model configured — proposals are local'); }
  inspector();
});
