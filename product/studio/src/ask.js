/* ═══════════════════════════════════════════════════════════════════════════
   ASK — the generative layer.

   Three things can be asked of a selected component: a LAYOUT, a set of
   VARIATIONS, or an ANIMATION. Each returns DATA over a schema this studio
   already executes — a layout spec, parameter sets, an ordered shot list.
   Nothing returns code, and nothing is evaluated: a proposal is validated and
   clamped at the door, so the worst a bad answer can do is look wrong.

   Every ask has a local proposer that runs with no model at all. The model
   makes the proposals better; it is not what makes the feature exist. And when
   a model IS configured but fails, the failure is named — reporting a rejected
   key as "no model" is a lie the user cannot debug.
   ═══════════════════════════════════════════════════════════════════════════ */
import { COMPONENTS, byId, LAYOUT_SPECS, sanitise } from './components.js';
import { REGISTERS } from './copy.js';
import { variants, FORMATS } from './combine.js';

export const KINDS = [
  { id:'layout',     name:'Layout',     job:'Compose the frame around this component' },
  { id:'variations', name:'Variations', job:'Ten treatments worth looking at' },
  { id:'animation',  name:'Animation',  job:'A sequence of moments, fused' },
];

/* ── is there a model behind the endpoint ───────────────────────────────── */
export let MODEL = { ready:false, checked:false, detail:'' };
export async function probe(){
  try{
    const r = await fetch('/api/state');
    const d = await r.json();
    MODEL = { ready:!!d.model, checked:true, detail:d.model ? '' : 'no key on the server' };
  } catch{
    MODEL = { ready:false, checked:true, detail:'server has no /api/state — restart it with server.mjs' };
  }
  return MODEL;
}

const HOUSE = `
House rules, not negotiable:
- Monochrome only. Never propose a colour; hierarchy comes from size and opacity.
- One type family. No second face, no italics for emphasis.
- Copy is conventional, minimal and precise. No wordplay, no slogans, no filler.
- A frame must be composed for its rectangle: a small control centred in a tall
  frame is a stamp in a field of white.
Answer with JSON only. No prose, no code fence.`;

function context(node){
  const c = byId(node.comp);
  return `Component: ${c.name} — ${c.job}
Natural width ${c.cssW}px, reads finished at moment ${c.rest}.
Current: format ${node.format}, layout ${node.layout}, surface ${node.theme}, register ${node.register}, moment ${node.phase.toFixed(2)}, reveal ${(node.reveal ?? 1).toFixed(2)}.
Formats available: ${FORMATS.map(f => `${f.id} (${f.note})`).join(', ')}.
Registers available: ${REGISTERS.map(r => r.id).join(', ')}.
Layouts available: ${Object.keys(LAYOUT_SPECS).join(', ')}.`;
}

/* ── the three asks ──────────────────────────────────────────────────────── */
const SYSTEMS = {
  layout: `You compose social frames around a live UI component.
Return one layout spec:
{"name":"short name","job":"one line","subject":{"x":0..0.9,"y":0..0.9,"w":0.1..1,"h":0.1..1},
 "line":null or {"source":"claim|name|job","x":0..1,"y":0..1,"w":0.2..1,"size":16..140,"align":"left|center|right","weight":400|500|600,"max":1..5},
 "caption":null or {"source":"name+job|job|claim","x":0..1,"y":0..1,"w":0.2..1,"size":12..60},
 "mark":null or "bl|br|tl|tr","why":"one sentence"}
All positions are fractions of the frame. Type sizes are in 1080-wide space.
Leave the subject room to breathe and do not overlap the line with it.${HOUSE}`,

  variations: `You propose treatments of one component.
Return {"variants":[ up to 10 of
 {"layout":"bare|titled|captioned|stated","format":"story|feed|square|wide|card",
  "theme":"dark|light","register":"review|bug|product",
  "phase":0..1,"reveal":0..1,"scale":0.6..1.4,"claim":"optional one-line override"} ],"why":"one sentence"}
Every variant must differ from every other in at least two fields. Sweep the
axes rather than sampling near one point.${HOUSE}`,

  animation: `You choreograph a short sequence of one component.
Return {"shots":[ 3 to 8 of
 {"phase":0..1,"reveal":0..1,"scale":0.6..1.4,"layout":"bare|titled|captioned|stated","theme":"dark|light"} ],
 "hold":300..1400,"why":"one sentence"}
Shots are keyframes; the studio interpolates between them and picks the manner
of each move from what changes. Consecutive shots that change everything at once
produce cuts, which is usually not what you want. Build it so something is
carried through: sweep reveal to disclose the anatomy, or sweep the moment.${HOUSE}`,
};

async function call(kind, node, note){
  const r = await fetch('/api/ask', {
    method:'POST', headers:{ 'content-type':'application/json' },
    body: JSON.stringify({ system: SYSTEMS[kind],
      prompt: `${context(node)}${note ? `\n\nWhat is wanted: ${note}` : ''}` }),
  });
  const d = await r.json();
  if(!r.ok) throw new Error(d.detail || d.error || `HTTP ${r.status}`);
  const t = String(d.text || '');
  const a = t.indexOf('{'), b = t.lastIndexOf('}');
  if(a < 0 || b < a) throw new Error('the model did not answer with JSON');
  return JSON.parse(t.slice(a, b + 1));
}

/* ── validation: everything that lands is clamped to a known range ───────── */
const pick = (v, list, dflt) => list.includes(v) ? v : dflt;
const num = (v, lo, hi, d) => Number.isFinite(+v) ? Math.min(hi, Math.max(lo, +v)) : d;
const LAY = Object.keys(LAYOUT_SPECS), FMT = FORMATS.map(f => f.id), REG = REGISTERS.map(r => r.id);

const cleanVariant = (v, node) => ({
  layout: pick(v.layout, LAY, node.layout),
  format: pick(v.format, FMT, node.format),
  theme:  pick(v.theme, ['dark','light'], node.theme),
  register: pick(v.register, REG, node.register),
  phase: num(v.phase, 0, 1, node.phase),
  reveal: num(v.reveal, 0, 1, 1),
  scale: num(v.scale, .6, 1.4, 1),
  claim: typeof v.claim === 'string' ? v.claim.slice(0, 120) : null,
});
const cleanShot = (s, node) => ({
  phase: num(s.phase, 0, 1, node.phase),
  reveal: num(s.reveal, 0, 1, 1),
  scale: num(s.scale, .6, 1.4, 1),
  layout: pick(s.layout, LAY, node.layout),
  theme: pick(s.theme, ['dark','light'], node.theme),
});

/* ── local proposers — no model, still useful ───────────────────────────── */
const PHI = .6180339887;
function localLayout(node, i = Math.random()){
  const base = LAYOUT_SPECS[node.layout] || LAYOUT_SPECS.titled;
  const u = (i * PHI) % 1;
  const top = u < .5;
  return sanitise({
    name:'Proposed', job:'Local proposal — the subject moved and the line follows',
    subject:{ x:0, y: top ? .34 : .06, w:1, h:.58 },
    line:{ source:'claim', x: u < .33 ? .067 : .5, y: top ? .13 : .78,
           w:.86, size: 40 + Math.round(u * 40), align: u < .33 ? 'left' : 'center',
           weight:500, max:3 },
    caption:null, mark: top ? 'bl' : 'tl',
  });
}
const localVariants = node => variants(10, { comp:node.comp }).map(v => cleanVariant(v, node));
function localAnimation(node){
  /* disclose the anatomy, then carry the moment — a cascade, then a scrub */
  return { shots:[
    cleanShot({ phase:.12, reveal:.34, layout:node.layout, theme:node.theme }, node),
    cleanShot({ phase:.4,  reveal:.67, layout:node.layout, theme:node.theme }, node),
    cleanShot({ phase:.7,  reveal:1,   layout:node.layout, theme:node.theme }, node),
    cleanShot({ phase:1,   reveal:1,   layout:node.layout, theme:node.theme, scale:1.06 }, node),
  ], hold:640, why:'Local proposal — the anatomy discloses, then the moment carries.' };
}

/* ── the one entry point ─────────────────────────────────────────────────── */
export async function ask(kind, node, note){
  const local = () => kind === 'layout' ? { spec:localLayout(node), why:'Local proposal.' }
    : kind === 'variations' ? { variants:localVariants(node), why:'Local sweep of the axes.' }
    : localAnimation(node);

  if(!MODEL.ready) return { ...local(), source:'local', detail:MODEL.detail };

  try{
    const raw = await call(kind, node, note);
    if(kind === 'layout') return { spec:sanitise(raw), why:String(raw.why || ''), source:'model' };
    if(kind === 'variations') return {
      variants:(Array.isArray(raw.variants) ? raw.variants : []).slice(0, 10).map(v => cleanVariant(v, node)),
      why:String(raw.why || ''), source:'model' };
    return {
      shots:(Array.isArray(raw.shots) ? raw.shots : []).slice(0, 8).map(s => cleanShot(s, node)),
      hold:num(raw.hold, 300, 1400, 720), why:String(raw.why || ''), source:'model' };
  } catch(e){
    /* a configured model that failed must say why */
    return { ...local(), source:'fallback', detail:String(e.message || e) };
  }
}
