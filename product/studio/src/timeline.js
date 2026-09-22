/* ═══════════════════════════════════════════════════════════════════════════
   TIMELINE — shots in order, and the fusion between them.

   A card is a still at a chosen moment. A timeline is an ORDER of cards, and
   fusion is the part that reads what changes between two of them and picks the
   manner of the move. That is the whole intelligence: the manner is derived
   from the diff, never chosen at random and never one transition applied to
   everything.

       same control, same treatment, different moment   →  SCRUB
       same control, different framing                  →  REFRAME
       different control, same surface                  →  MATCH
       the surface itself changes                       →  FLIP

   A cut is the honest answer when two shots share nothing; dissolving them is
   a smear, not a transition.
   ═══════════════════════════════════════════════════════════════════════════ */
import { plate } from './components.js';
import { words } from './copy.js';

/* ── cadence ────────────────────────────────────────────────────────────
   Long, decelerating, no overshoot — the iOS curve. A shot is held long
   enough to be read before it is allowed to move. */
export const CADENCE = {
  hold:  720,
  scrub: 900,
  reframe: 760,
  match: 560,
  flip:  320,
};
const BEZ = [0.32, 0.72, 0, 1];

/* cubic-bezier(x1,y1,x2,y2) evaluated by bisection — exact enough at 60fps and
   free of the table a spline solver would need */
export function bezier(t, [x1, y1, x2, y2] = BEZ){
  t = Math.min(1, Math.max(0, t));
  const cx = 3*x1, bx = 3*(x2-x1) - cx, ax = 1 - cx - bx;
  const cy = 3*y1, by = 3*(y2-y1) - cy, ay = 1 - cy - by;
  const fx = u => ((ax*u + bx)*u + cx)*u;
  let lo = 0, hi = 1, u = t;
  for(let i = 0; i < 24; i++){ const x = fx(u); if(Math.abs(x - t) < 1e-4) break; x < t ? lo = u : hi = u; u = (lo + hi)/2; }
  return ((ay*u + by)*u + cy)*u;
}
const lerp = (a, b, t) => a + (b - a) * t;

/* ── what changed, and therefore how to move ─────────────────────────────── */
export function manner(a, b){
  const same = k => a[k] === b[k];
  if(!same('theme')) return 'flip';
  if(same('comp')){
    return (same('layout') && same('format')) ? 'scrub' : 'reframe';
  }
  return 'match';
}

export const MANNERS = {
  scrub:   { name:'Scrub',   job:'One control, carried through its own moment' },
  reframe: { name:'Reframe', job:'Same subject, the framing moves' },
  match:   { name:'Match',   job:'Subject changes on a held surface' },
  flip:    { name:'Flip',    job:'The surface itself turns over' },
};

/* ── the plan ────────────────────────────────────────────────────────────── */
export function fuse(shots, { hold = CADENCE.hold } = {}){
  const segments = [];
  if(!shots.length) return { segments, total:0, shots };
  shots.forEach((s, i) => {
    segments.push({ kind:'hold', a:i, b:i, dur:hold, manner:null });
    if(i < shots.length - 1){
      const m = manner(shots[i], shots[i+1]);
      segments.push({ kind:'move', a:i, b:i+1, dur:CADENCE[m], manner:m });
    }
  });
  let t = 0;
  for(const s of segments){ s.t0 = t; t += s.dur; s.t1 = t; }
  return { segments, total:t, shots };
}

/* what is on screen at time t */
export function sample(plan, t){
  if(!plan.total) return null;
  const time = ((t % plan.total) + plan.total) % plan.total;
  const seg = plan.segments.find(s => time >= s.t0 && time < s.t1) || plan.segments[plan.segments.length-1];
  const u = seg.dur ? bezier((time - seg.t0) / seg.dur) : 1;
  return { seg, u, a:plan.shots[seg.a], b:plan.shots[seg.b] };
}

/* ── drawing one fused frame ─────────────────────────────────────────────
   A scrub is ONE draw with interpolated parameters — crossfading a control
   against itself is a double exposure, not a move. Everything else is a
   dissolve over a held ground. */
export function render(x, W, H, plan, t, ims){
  const s = sample(plan, t);
  if(!s) return;
  const { seg, u, a, b } = s;

  if(seg.kind === 'hold' || !seg.manner){
    plate(x, W, H, a, words(a.seed, a.register), ims);
    return;
  }
  if(seg.manner === 'scrub'){
    draw(x, W, H, {
      ...a,
      phase: lerp(a.phase, b.phase, u),
      scale: lerp(a.scale, b.scale, u),
      reveal: lerp(a.reveal ?? 1, b.reveal ?? 1, u),
    });
    return;
  }
  /* reframe holds the subject and lets the framing travel, so the outgoing
     card keeps moving rather than sitting still under the incoming one */
  const drift = seg.manner === 'reframe' ? lerp(0, .04, u) : 0;
  plate(x, W, H, { ...a, scale:a.scale * (1 + drift) }, words(a.seed, a.register), ims);
  x.save();
  x.globalAlpha = seg.manner === 'flip' ? bezier(u, [.6,0,.9,1]) : u;
  plate(x, W, H, { ...b, scale:b.scale * (1 - .04 + drift) }, words(b.seed, b.register), ims);
  x.restore();
}

/* ── export ──────────────────────────────────────────────────────────────── */
export const frameCount = (plan, fps = 30) => Math.round(plan.total / 1000 * fps);
