/* ═══════════════════════════════════════════════════════════════════════════
   COMBINE — generative combinatorics.

   "Ten new versions" is not ten random draws. Random sampling of a product
   space returns near-duplicates and calls them variety. This walks the space
   instead: every variant differs from every other in at least two axes, and
   the axes are swept rather than rolled.

   Axes: component · moment · scale · theme · register · word seed.
   ═══════════════════════════════════════════════════════════════════════════ */
import { COMPONENTS, byId } from './components.js';
import { REGISTERS } from './copy.js';

/* the formats a frame can be asked for */
export const FORMATS = [
  { id:'story',   name:'Story',   w:1080, h:1920, note:'9:16' },
  { id:'feed',    name:'Feed',    w:1080, h:1350, note:'4:5' },
  { id:'square',  name:'Square',  w:1080, h:1080, note:'1:1' },
  { id:'wide',    name:'Wide',    w:1600, h:900,  note:'16:9' },
  { id:'card',    name:'Card',    w:1200, h:630,  note:'OG' },
];
export const formatOf = id => FORMATS.find(f => f.id === id) || FORMATS[1];

const PHASES = [.18, .34, .5, .68, .84, 1];
const SCALES = [.72, .86, 1, 1.18];
const THEMES = ['dark', 'light'];
const LAYOUTS_A = ['bare', 'titled', 'captioned', 'stated'];

/* golden-ratio stride: consecutive draws land far apart on every axis, and the
   sequence never repeats a pair until it has used them all */
const PHI = 0.6180339887;
const stride = (i, n, off = 0) => Math.floor(((i * PHI + off) % 1) * n);

/**
 * Ten (or n) variants that genuinely differ.
 * `lock` pins any axis the user has already decided — a locked component means
 * ten moments of that one control rather than ten different controls.
 */
export function variants(n = 10, lock = {}, base = {}){
  const comps = lock.comp ? [lock.comp] : COMPONENTS.map(c => c.id);
  const regs  = lock.register ? [lock.register] : REGISTERS.map(r => r.id);
  const out = [];
  const seen = new Set();

  for(let i = 0; out.length < n && i < n * 6; i++){
    const comp  = comps[stride(i, comps.length, .11)];
    const phase = lock.phase != null ? lock.phase : PHASES[stride(i, PHASES.length, .37)];
    const scale = lock.scale != null ? lock.scale : SCALES[stride(i, SCALES.length, .59)];
    const theme = lock.theme || THEMES[stride(i, THEMES.length, .23)];
    const register = regs[stride(i, regs.length, .71)];
    const layout = lock.layout || LAYOUTS_A[stride(i, LAYOUTS_A.length, .43)];
    const seed = +(((i * PHI * 7.13) % 1).toFixed(4));

    /* two variants may share a component, but never a component AND a moment */
    const key = `${comp}|${phase}|${theme}|${layout}`;
    if(seen.has(key)) continue;
    seen.add(key);
    out.push({ ...base, comp, phase, scale, theme, register, seed, layout });
  }
  return out;
}

/** One variant, nudged — for "another like this" rather than a fresh sweep. */
export function nudge(node, k = 1){
  const p = PHASES[(PHASES.findIndex(v => v >= node.phase) + k + PHASES.length) % PHASES.length];
  return { ...node, phase:p, seed:+(((node.seed + PHI) % 1).toFixed(4)) };
}
