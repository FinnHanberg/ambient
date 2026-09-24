/* ═══════════════════════════════════════════════════════════════════════════
   KIT — the house interface, drawn at frame scale.

   Every number in here and in `components.js` is lifted from `canvas.css` and
   `studio.css`. That is the whole point: a component frame is a PHOTOGRAPH of
   the real control, not a drawing of one. If the stylesheet moves, these move
   with it, and the picture stays true.

   A component is written in CSS pixels. `stage()` sets one transform and after
   that every number is the number in the stylesheet — 15px is 15px, a 9px
   radius is 9. The frame decides how big that is; the component never knows.
   ═══════════════════════════════════════════════════════════════════════════ */

export const C = {
  ink:'#141414', ink2:'#5c5c5c', ink3:'#8a8a8a', ink4:'#c4c4c4',
  hair:'#e6e6e6', surf:'#f7f7f7', surf2:'#f0f0f0', paper:'#ffffff', signal:'#fcff52',
};
export const SANS = '-apple-system,BlinkMacSystemFont,"Inter","Helvetica Neue",system-ui,sans-serif';

/* how much of the frame's width a component fills at scale 1 */
export const FILL = .62;

export const lerp  = (a, b, t) => a + (b - a) * t;
export const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
export const easeOut = t => 1 - Math.pow(1 - clamp(t), 3);
export const ease    = t => (t = clamp(t)) < .5 ? 4*t*t*t : 1 - Math.pow(-2*t + 2, 3)/2;
/* in → hold → out, for anything that arrives and leaves */
export const inOut = (t, a = .22, b = .78) =>
  t < a ? easeOut(t/a) : t > b ? 1 - easeOut((t-b)/(1-b)) : 1;

/* ── the transform ────────────────────────────────────────────────────────
   Origin at the component's centre, one unit = one CSS pixel. Returns the
   scale so anything that must stay frame-relative (the dot field) can ask. */
export const unit = (W, cssW, scale = 1) => (W * FILL / cssW) * scale;
export function stage(x, W, H, cssW, scale = 1){
  const u = unit(W, cssW, scale);
  x.save(); x.translate(W/2, H/2); x.scale(u, u);
  return u;
}
export const unstage = x => x.restore();

/* ── type ─────────────────────────────────────────────────────────────────
   `track` is letter-spacing in em, the way the stylesheet writes it. Chrome
   has `letterSpacing`; where it does not exist the type is a hair wide and
   nothing breaks. */
export function type(x, s, { px, w = 400, fill = C.ink, align = 'left',
                             base = 'alphabetic', track = 0, alpha = 1 }){
  x.save();
  x.globalAlpha *= alpha;
  x.font = `${w} ${px}px ${SANS}`;
  x.fillStyle = fill; x.textAlign = align; x.textBaseline = base;
  if('letterSpacing' in x) x.letterSpacing = `${track}em`;
  const out = s;
  x.fillText(out, 0, 0);
  const width = x.measureText(out).width;
  x.restore();
  return width;
}
export function widthOf(x, s, px, w = 400, track = 0){
  x.save(); x.font = `${w} ${px}px ${SANS}`;
  if('letterSpacing' in x) x.letterSpacing = `${track}em`;
  const m = x.measureText(s).width; x.restore(); return m;
}

/* ── boxes ────────────────────────────────────────────────────────────────── */
export const rr = (x, x0, y0, w, h, r) => { x.beginPath(); x.roundRect(x0, y0, w, h, Math.min(r, h/2, w/2)); };
export function box(x, x0, y0, w, h, r, { fill, ring, ringW = 1, shadow, blur = 0, dy = 0 } = {}){
  if(shadow){ x.save(); x.shadowColor = shadow; x.shadowBlur = blur; x.shadowOffsetY = dy;
              rr(x, x0, y0, w, h, r); x.fillStyle = fill || C.paper; x.fill(); x.restore(); }
  else if(fill){ rr(x, x0, y0, w, h, r); x.fillStyle = fill; x.fill(); }
  if(ring){ rr(x, x0 + ringW/2, y0 + ringW/2, w - ringW, h - ringW, r); x.strokeStyle = ring; x.lineWidth = ringW; x.stroke(); }
}

/* ── the keycap, from `#guide kbd` ───────────────────────────────────────── */
export function keycap(x, x0, y, label, px){
  const w = widthOf(x, label, px, 500) + px*.92, h = px*1.62;
  box(x, x0, y - h*.78, w, h, px*.38, { fill: C.surf, ring: C.hair, ringW: px*.075 });
  x.save(); x.translate(x0 + w/2, y); type(x, label, { px, w:500, align:'center' }); x.restore();
  return w;
}

/* ── the ground, from `studio.css` #ground ───────────────────────────────────
   radial-gradient(circle at 1px 1px, rgba(20,20,20,.10) 1px, transparent 0)
   at 28px. Drawn in FRAME pixels — the field belongs to the picture, not to
   the component, so zooming the component does not zoom the paper. */
export function dots(x, W, H, step, r, alpha){
  x.save(); x.fillStyle = `rgba(20,20,20,${alpha})`;
  for(let gy = step/2; gy < H + step; gy += step)
    for(let gx = step/2; gx < W + step; gx += step){
      x.beginPath(); x.arc(gx, gy, r, 0, Math.PI*2); x.fill();
    }
  x.restore();
}
