/* ═══════════════════════════════════════════════════════════════════════════
   KIT — the Pass interface, drawn at frame scale.

   Every number here is lifted from the app and the component sandbox. A
   component plate is a PHOTOGRAPH of the real control, not a drawing of one:
   if the product's numbers move, these move with it and the picture stays true.

   Written in CSS pixels. `stage()` sets one transform; after that 13px is 13px
   and a 5px radius is 5. The frame decides how big that is — the component
   never knows what size it is being asked for.
   ═══════════════════════════════════════════════════════════════════════════ */

/* the two surfaces, and the one opacity ladder used identically on both */
export const LIGHT = {
  ink:'#0A0A0A', ground:'#F4F4F4', paper:'#FFFFFF',
  t1:'rgba(10,10,10,1)', t2:'rgba(10,10,10,.52)', t3:'rgba(10,10,10,.34)',
  hair:'rgba(10,10,10,.14)', fill:'rgba(10,10,10,.06)', on:'#F4F4F4',
};
export const DARK = {
  ink:'#FFFFFF', ground:'#0F0F0F', paper:'#141414',
  t1:'rgba(255,255,255,.95)', t2:'rgba(255,255,255,.52)', t3:'rgba(255,255,255,.34)',
  hair:'rgba(255,255,255,.12)', fill:'rgba(255,255,255,.06)', on:'#0F0F0F',
};
export const themeOf = t => (t === 'light' ? LIGHT : DARK);

export const SANS = 'Geist,-apple-system,BlinkMacSystemFont,"Helvetica Neue",system-ui,sans-serif';

/* how much of the frame's width a component fills at scale 1 */
export const FILL = .78;

export const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
export const lerp  = (a, b, t) => a + (b - a) * t;
export const easeOut = t => 1 - Math.pow(1 - clamp(t), 3);
export const ease = t => (t = clamp(t)) < .5 ? 4*t*t*t : 1 - Math.pow(-2*t + 2, 3)/2;
/* arrives, holds, leaves — for anything with a lifetime inside one moment */
export const inOut = (t, a = .22, b = .78) =>
  t < a ? easeOut(t/a) : t > b ? 1 - easeOut((t-b)/(1-b)) : 1;

/* ── the transform ───────────────────────────────────────────────────────
   `stage` centres on the whole frame; `stageIn` centres on a given box, so a
   composed frame can hand the component a rectangle smaller than the picture
   and the component still never knows what size it is being asked for. */
export const unit = (W, cssW, scale = 1) => (W * FILL / cssW) * scale;
export function stage(x, W, H, cssW, scale = 1){
  return stageIn(x, 0, 0, W, H, cssW, scale);
}
export function stageIn(x, bx, by, bw, bh, cssW, scale = 1){
  const u = unit(bw, cssW, scale);
  x.save(); x.translate(bx + bw/2, by + bh/2); x.scale(u, u);
  return u;
}
export const unstage = x => x.restore();

/* ── type ─────────────────────────────────────────────────────────────────
   `track` is letter-spacing in em, the way the stylesheet writes it. */
export function type(x, s, { px, w = 400, fill = '#000', align = 'left',
                             base = 'alphabetic', track = 0, alpha = 1 }){
  x.save();
  x.globalAlpha *= alpha;
  x.font = `${w} ${px}px ${SANS}`;
  x.fillStyle = fill; x.textAlign = align; x.textBaseline = base;
  if('letterSpacing' in x) x.letterSpacing = `${track}em`;
  x.fillText(s, 0, 0);
  const width = x.measureText(s).width;
  x.restore();
  return width;
}
export function widthOf(x, s, px, w = 400, track = 0){
  x.save(); x.font = `${w} ${px}px ${SANS}`;
  if('letterSpacing' in x) x.letterSpacing = `${track}em`;
  const m = x.measureText(s).width; x.restore(); return m;
}
/* wrap to a measure, returning the lines — the label voice never wraps */
export function lines(x, s, px, w, maxW, max = 3){
  const words = String(s).split(/\s+/); const out = []; let line = '';
  for(const word of words){
    const next = line ? line + ' ' + word : word;
    if(widthOf(x, next, px, w) > maxW && line){ out.push(line); line = word; if(out.length === max) break; }
    else line = next;
  }
  if(line && out.length < max) out.push(line);
  if(out.length === max){
    let last = out[max-1];
    while(widthOf(x, last + '…', px, w) > maxW && last.length > 1) last = last.slice(0, -1);
    if(words.join(' ') !== out.join(' ')) out[max-1] = last + '…';
  }
  return out;
}

/* ── boxes ───────────────────────────────────────────────────────────────── */
export const rr = (x, x0, y0, w, h, r) => {
  x.beginPath(); x.roundRect(x0, y0, w, h, Math.max(0, Math.min(r, h/2, w/2)));
};
export function box(x, x0, y0, w, h, r, { fill, ring, ringW = 1, shadow, blur = 0, dy = 0 } = {}){
  if(shadow){ x.save(); x.shadowColor = shadow; x.shadowBlur = blur; x.shadowOffsetY = dy;
              rr(x, x0, y0, w, h, r); x.fillStyle = fill || '#fff'; x.fill(); x.restore(); }
  else if(fill){ rr(x, x0, y0, w, h, r); x.fillStyle = fill; x.fill(); }
  if(ring){ rr(x, x0 + ringW/2, y0 + ringW/2, w - ringW, h - ringW, r);
            x.strokeStyle = ring; x.lineWidth = ringW; x.stroke(); }
}
export function hair(x, x0, y0, w, colour, t = 1){
  x.fillStyle = colour; x.fillRect(x0, y0, w, t);
}

/* ── the pill, from the site's .pill ─────────────────────────────────────── */
export function pill(x, x0, y0, label, px, T, { solid = true } = {}){
  const padX = px * 1.4, h = px * 2.55;
  const w = widthOf(x, label, px, 500) + padX * 2;
  box(x, x0, y0, w, h, h/2, solid
    ? { fill:T === LIGHT ? T.ink : 'rgba(255,255,255,.16)' }
    : { fill:T.fill, ring:T.hair, ringW:1 });
  x.save(); x.translate(x0 + w/2, y0 + h/2);
  type(x, label, { px, w:500, align:'center', base:'middle',
                   fill: solid ? (T === LIGHT ? T.on : '#fff') : T.t2 });
  x.restore();
  return w;
}

/* ── the label voice — 12 uppercase, +.04em, weight 500 ──────────────────── */
export function label(x, x0, y0, s, px, T, alpha = 1){
  x.save(); x.translate(x0, y0);
  const w = type(x, String(s).toUpperCase(), { px, w:500, track:.04, fill:T.t3, alpha, base:'middle' });
  x.restore(); return w;
}

/* ── the cursor ring — the product's one mark ────────────────────────────── */
export function ring(x, cx, cy, r, t = 1){
  x.save();
  x.globalAlpha *= t;
  x.strokeStyle = 'rgba(0,0,0,.85)'; x.lineWidth = r * .30;
  x.beginPath(); x.arc(cx, cy, r, 0, Math.PI*2); x.stroke();
  x.strokeStyle = '#fff'; x.lineWidth = r * .15;
  x.beginPath(); x.arc(cx, cy, r, 0, Math.PI*2); x.stroke();
  x.restore();
}

/* ── the dot field, drawn in FRAME pixels ────────────────────────────────
   The paper belongs to the picture, not to the component, so zooming the
   component must not zoom the field. */
export function dots(x, W, H, step, r, colour){
  x.save(); x.fillStyle = colour;
  for(let gy = step/2; gy < H + step; gy += step)
    for(let gx = step/2; gx < W + step; gx += step){
      x.beginPath(); x.arc(gx, gy, r, 0, Math.PI*2); x.fill();
    }
  x.restore();
}
