/* ═══════════════════════════════════════════════════════════════════════════
   COMPONENTS — the Pass interface as material.

   THE INTERFACE IS MATERIAL. A control staged well IS the work, photographed.
   Every component is reached as a string `ui:<id>:<phase>:<scale>:<theme>` so
   it crops, scales, joins a frame and exports with no special case anywhere
   downstream.

   `phase` is a MOMENT, not a clock — a scrubbed state variable. Each component
   declares the moment at which it reads as a finished frame (`rest`), so a
   plate dropped on the canvas is never caught mid-transition by accident.
   ═══════════════════════════════════════════════════════════════════════════ */
import { themeOf, LIGHT, type, widthOf, lines, box, rr, hair, pill, label,
         ring, stage, stageIn, unstage, clamp, lerp, easeOut, ease, inOut, dots } from './kit.js';

/* ── images, cached; a plate never waits on a decode ─────────────────────── */
const IMG = new Map();
export function image(src, onload){
  if(IMG.has(src)) return IMG.get(src);
  const im = new Image();
  im.onload = () => { im._ok = true; onload && onload(); };
  im.src = src; IMG.set(src, im);
  return im;
}
function cover(x, im, x0, y0, w, h, r){
  if(!im || !im._ok){ box(x, x0, y0, w, h, r, { fill:'rgba(128,128,128,.18)' }); return; }
  x.save(); rr(x, x0, y0, w, h, r); x.clip();
  const s = Math.max(w/im.width, h/im.height), dw = im.width*s, dh = im.height*s;
  x.drawImage(im, x0 + (w-dw)/2, y0 + (h-dh)/2, dw, dh);
  x.restore();
}

/* ─────────────────────────────────────────────────────────────────────────
   Each component: cssW is its natural width in CSS pixels; draw() is given a
   context already staged so that one unit is one CSS pixel, origin centred.
   ───────────────────────────────────────────────────────────────────────── */

/* a sub-part's own share of the reveal: 0 → absent, 1 → fully disclosed */
const part = (reveal, index, count) => clamp((reveal * count) - index);

const noteRow = (x, T, w, { i = 1, text, ctx, im, t = 1, rev = 1 }) => {
  const h = 80, thumbW = 84, thumbH = 56;
  x.save(); x.globalAlpha *= t;
  x.save(); x.translate(0, (1 - t) * 10);
  type(x, String(i), { px:10, w:500, fill:T.t3, align:'right', base:'top' });
  cover(x, im, 14, -thumbH/2 + 2, thumbW, thumbH, 5);
  box(x, 14, -thumbH/2 + 2, thumbW, thumbH, 5, { ring:T.hair });
  const tx = 14 + thumbW + 12, measure = w - tx - 26;
  x.globalAlpha *= part(rev, 1, 3) * .0 + 1;   /* text is tier 1, always present */
  const ls = lines(x, text, 13, 400, measure, 2);
  ls.forEach((l, k) => { x.save(); x.translate(tx, -thumbH/2 + 12 + k*18); type(x, l, { px:13, fill:T.t1, base:'middle' }); x.restore(); });
  const cRev = part(rev, 2, 3);
  if(cRev > 0){
    x.save(); x.globalAlpha *= cRev;
    x.translate(tx, -thumbH/2 + 14 + ls.length*18);
    const c = lines(x, ctx, 10.5, 400, measure, 1);
    type(x, c[0] || '', { px:10.5, fill:T.t3, base:'middle' });
    x.restore();
  }
  x.save(); x.translate(w - 12, 0); type(x, '×', { px:15, fill:T.t3, align:'center', base:'middle' }); x.restore();
  x.restore(); x.restore();
  return h;
};

const waveform = (x, T, level, n = 5) => {
  const weights = [.45, .78, 1, .72, .4];
  for(let i = 0; i < n; i++){
    const h = Math.max(3, 3 + level * 17 * weights[i % 5]);
    box(x, i * 5.5, -h/2, 2.5, h, 1.5, { fill:T.ink === '#FFFFFF' ? 'rgba(255,255,255,.75)' : 'rgba(10,10,10,.75)' });
  }
  return n * 5.5;
};

export const COMPONENTS = [
  /* ── the load-bearing one ───────────────────────────────────────────── */
  { id:'noterow', gen:'v1', tall:0.4, pres:1.14, name:'Note row', cssW:520, rest:1,
    job:'Index, crop, what was said, where it was said about.',
    draw(x, W, H, p, T){
      const w = 520;
      box(x, -w/2, -52, w, 104, 14, { fill:T.ground, ring:T.hair });
      x.save(); x.translate(-w/2 + 20, 0);
      noteRow(x, T, w - 40, { i:1, text:p.words.note, ctx:p.words.ctx, im:p.im, t:easeOut(clamp(p.phase / .55)), rev:p.reveal });
      x.restore();
    } },

  /* ── the whole pass ─────────────────────────────────────────────────── */
  { id:'panel', gen:'v1', tall:0.72, pres:1.0, name:'Review panel', cssW:540, rest:1,
    job:'A finished pass, ready to copy.',
    draw(x, W, H, p, T){
      const w = 540, rows = 3, h = 64 + rows*81 + 62;
      box(x, -w/2, -h/2, w, h, 16, { fill:T.ground, ring:T.hair,
        shadow:'rgba(0,0,0,.45)', blur:40, dy:14 });
      x.save(); x.translate(-w/2, -h/2);
      /* header */
      x.save(); x.translate(20, 34);
      const n = type(x, `${rows} notes`, { px:15, w:600, fill:T.t1, base:'middle' });
      x.save(); x.translate(n + 10, 0); type(x, p.words.page, { px:11, fill:T.t3, base:'middle' }); x.restore();
      x.restore();
      hair(x, 0, 56, w, T.hair);
      /* rows, arriving one after another */
      for(let i = 0; i < rows; i++){
        const disclosed = part(p.reveal, i, rows);
        if(disclosed <= 0) continue;
        const t = easeOut(clamp((p.phase - i*.12) / .42)) * disclosed;
        x.save(); x.translate(20, 56 + 40 + i*81);
        noteRow(x, T, w - 40, { i:i+1, text:p.words.notes[i], ctx:p.words.ctxs[i], im:p.ims[i], t, rev:p.reveal });
        x.restore();
        if(i < rows-1) hair(x, 20, 56 + 81 + i*81, w - 40, T.hair);
      }
      hair(x, 0, h - 62, w, T.hair);
      /* footer */
      x.save(); x.translate(20, h - 45);
      const a = pill(x, 0, 0, 'Copy', 12, T, { solid:true });
      pill(x, a + 10, 0, 'Paste into Claude', 12, T, { solid:false });
      x.save(); x.translate(w - 40 - 84, 15);
      type(x, 'Discard', { px:12, fill:T.t3, base:'middle' });
      x.save(); x.translate(56, 0); type(x, 'Close', { px:12, fill:T.t2, base:'middle' }); x.restore();
      x.restore();
      x.restore();
      x.restore();
    } },

  /* ── the listening card ─────────────────────────────────────────────── */
  { id:'hud', gen:'v1', tall:0.46, pres:1.12, name:'Listening panel', cssW:440, rest:.55,
    job:'Mid-pass: the live transcript and what the cursor is on.',
    draw(x, W, H, p, T){
      const w = 440, h = 150;
      box(x, -w/2, -h/2, w, h, 20, { fill:T.ground, ring:T.hair,
        shadow:'rgba(0,0,0,.45)', blur:36, dy:12 });
      x.save(); x.translate(-w/2 + 18, -h/2 + 22);
      /* the bars answer to a level, not to a clock */
      const lv = .35 + .55 * Math.abs(Math.sin(p.phase * Math.PI * 3.1));
      const ww = waveform(x, T, lv);
      x.save(); x.translate(ww + 8, 0);
      label(x, 0, 0, `LISTENING · ${p.words.count}`, 9.5, T, .8);
      x.restore();
      /* the transcript types itself in — bound to phase */
      const full = p.words.note;
      const shown = full.slice(0, Math.max(1, Math.round(full.length * clamp(p.phase / .82))));
      x.save(); x.translate(0, 34);
      lines(x, shown, 17, 400, w - 36, 2).forEach((l, k) => {
        x.save(); x.translate(0, k * 23); type(x, l, { px:17, fill:T.t1, base:'middle' }); x.restore();
      });
      x.restore();
      /* the binding chip */
      const chipT = easeOut(clamp((p.phase - .25) / .3)) * part(p.reveal, 2, 3);
      x.save(); x.globalAlpha *= chipT; x.translate(0, 92);
      const cw = widthOf(x, p.words.ctx, 10.5, 400) + 30;
      box(x, 0, -11, cw, 22, 11, { fill:T.fill, ring:T.hair });
      x.beginPath(); x.arc(13, 0, 3.5, 0, Math.PI*2);
      x.strokeStyle = T.t2; x.lineWidth = 1; x.stroke();
      x.save(); x.translate(23, 0); type(x, p.words.ctx, { px:10.5, fill:T.t2, base:'middle' }); x.restore();
      x.restore();
      x.restore();
    } },

  /* ── the mark ───────────────────────────────────────────────────────── */
  { id:'ringshot', gen:'v1', tall:0.68, pres:1.0, bleed:true, name:'Ringed crop', cssW:520, rest:1,
    job:'What the cursor was on at the instant the word was spoken.',
    draw(x, W, H, p, T){
      const w = 520, h = 347;
      x.save(); rr(x, -w/2, -h/2, w, h, 10); x.clip();
      cover(x, p.im, -w/2, -h/2, w, h, 10);
      x.restore();
      box(x, -w/2, -h/2, w, h, 10, { ring:T.hair });
      /* the ring lands, then holds */
      const t = easeOut(clamp(p.phase / .45));
      const r = lerp(46, 26, t);
      ring(x, w*.06, h*.08, r, t);
    } },

  /* ── the atoms ──────────────────────────────────────────────────────── */
  { id:'status', gen:'v1', tall:0.26, pres:1.5, name:'Status', cssW:380, rest:1,
    job:'Alive, idle, or faulted — legible without being read.',
    draw(x, W, H, p, T){
      const w = 380;
      box(x, -w/2, -34, w, 68, 14, { fill:T.ground, ring:T.hair });
      x.save(); x.translate(-w/2 + 22, 0);
      const states = [['Listening', 'on'], ['Idle', 'off'], ['Not listening', 'err']];
      let cx = 0;
      states.forEach(([name, kind], i) => {
        const lit = i === Math.floor(p.phase * 2.99) % 3;
        x.save(); x.globalAlpha *= lit ? 1 : .35;
        if(kind === 'err'){ x.beginPath(); x.arc(cx + 3, 0, 3, 0, Math.PI*2); x.strokeStyle = T.t1; x.lineWidth = 1; x.stroke(); }
        else { x.beginPath(); x.arc(cx + 3, 0, 3, 0, Math.PI*2); x.fillStyle = kind === 'on' ? T.t1 : T.t3; x.fill(); }
        x.save(); x.translate(cx + 13, 0); const lw = label(x, 0, 0, name, 9.5, T, 1); x.restore();
        cx += 13 + lw + 22;
        x.restore();
      });
      x.restore();
    } },

  { id:'pills', gen:'v1', tall:0.22, pres:1.6, name:'Actions', cssW:340, rest:1,
    job:'One shape. Solid is the single primary action.',
    draw(x, W, H, p, T){
      const lift = easeOut(clamp(p.phase / .5));
      x.save(); x.translate(-150, -16);
      const a = pill(x, 0, 0, 'Copy', 12, T, { solid:true });
      x.save(); x.globalAlpha *= .4 + .6*lift;
      pill(x, a + 10, 0, 'Paste into Claude', 12, T, { solid:false });
      x.restore();
      x.restore();
    } },

  { id:'step', gen:'v1', tall:0.54, pres:1.34, name:'Step', cssW:300, rest:1,
    job:'The mechanic, three across, hairlines not cards.',
    draw(x, W, H, p, T){
      const w = 300, h = 150;
      box(x, -w/2, -h/2, w, h, 0, { fill:T.ground });
      hair(x, -w/2, -h/2, w, T.hair); hair(x, -w/2, h/2, w, T.hair);
      x.save(); x.translate(-w/2 + 24, -h/2 + 30);
      label(x, 0, 0, p.words.stepNo, 12, T);
      x.save(); x.translate(0, 32); type(x, p.words.stepName, { px:20, w:500, fill:T.t1, base:'middle' }); x.restore();
      x.save(); x.translate(0, 58); x.globalAlpha *= part(p.reveal, 2, 3);
      lines(x, p.words.step, 14, 400, w - 48, 3).forEach((l, k) => {
        x.save(); x.translate(0, k*19); type(x, l, { px:14, fill:T.t2, base:'middle' }); x.restore();
      });
      x.restore(); x.restore();
    } },

  { id:'fact', gen:'v1', tall:0.26, pres:1.18, name:'Fact row', cssW:520, rest:1,
    job:'Specification, where a table would be too much furniture.',
    draw(x, W, H, p, T){
      const w = 520;
      x.save(); x.translate(-w/2, 0);
      hair(x, 0, -34, w, T.hair);
      label(x, 0, -8, p.words.factKey, 12, T);
      x.save(); x.translate(180, -8); x.globalAlpha *= part(p.reveal, 1, 2);
      lines(x, p.words.fact, 14, 400, w - 190, 2).forEach((l, k) => {
        x.save(); x.translate(0, k*19); type(x, l, { px:14, fill:T.t2, base:'middle' }); x.restore();
      });
      x.restore();
      hair(x, 0, 34, w, T.hair);
      x.restore();
    } },

  { id:'wordmark', gen:'v1', tall:0.3, pres:1.0, name:'Wordmark', cssW:300, rest:1,
    job:'The name, at the size it is actually set.',
    draw(x, W, H, p, T){
      x.save();
      const t = easeOut(clamp(p.phase / .6));
      x.globalAlpha *= t;
      x.translate(0, lerp(8, 0, t));
      type(x, 'Pass', { px:64, w:500, fill:T.t1, align:'center', base:'middle', track:-.03 });
      x.restore();
    } },

  { id:'claim', gen:'v1', tall:0.44, pres:1.0, name:'Claim', cssW:560, rest:1,
    job:'One line of adaptive copy, set as display.',
    draw(x, W, H, p, T){
      const w = 560;
      const ls = lines(x, p.words.claim, 40, 500, w, 3);
      const t = clamp(p.phase / .8);
      ls.forEach((l, k) => {
        const lt = easeOut(clamp((t - k*.14) / .5));
        x.save(); x.globalAlpha *= lt;
        x.translate(0, (k - (ls.length-1)/2) * 46 + lerp(14, 0, lt));
        type(x, l, { px:40, w:500, fill:T.t1, align:'center', base:'middle', track:-.03 });
        x.restore();
      });
    } },

  /* ═══ v2 — the studio's own library, drawn from studio.css ═══════════════
     The chrome that builds the frames is itself material. Every number below
     is lifted from `studio.css`, so a plate of the Button is a photograph of
     the button the inspector actually uses. */

  { id:'buttons', gen:'v2', tall:.30, pres:1.38, name:'Button', cssW:420, rest:1,
    job:'Four variants, one shape. Solid carries the single primary action.',
    draw(x, W, H, p, T){
      const specs = [['Auto-fuse','default'],['Re-fuse','secondary'],['Play','ghost'],['Clear','destructive']];
      let cx = -210, gap = 8;
      const widths = specs.map(([l]) => widthOf(x, l, 12.5, 500) + 22);
      const total = widths.reduce((a,b)=>a+b,0) + gap*(specs.length-1);
      cx = -total/2;
      specs.forEach(([lab, v], i) => {
        const w = widths[i], h = 30, y = -h/2;
        const t = part(p.reveal, i, specs.length);
        x.save(); x.globalAlpha *= t;
        if(v === 'default')        box(x, cx, y, w, h, 6, { fill:T.t1 });
        else if(v === 'secondary') box(x, cx, y, w, h, 6, { fill:T.fill, ring:T.hair });
        else if(i === Math.floor(p.phase * 3.99) % 4) box(x, cx, y, w, h, 6, { fill:T.fill });
        x.save(); x.translate(cx + w/2, 0);
        type(x, lab, { px:12.5, w:500, align:'center', base:'middle',
                       fill: v === 'default' ? T.on : (v === 'ghost' ? T.t2 : T.t1) });
        x.restore(); x.restore();
        cx += w + gap;
      });
    } },

  { id:'toggle', gen:'v2', tall:.26, pres:1.5, name:'Toggle group', cssW:260, rest:1,
    job:'One of n. The selected item lifts onto the surface.',
    draw(x, W, H, p, T){
      const items = ['Dark','Light'], w = 200, h = 32, pad = 2;
      box(x, -w/2, -h/2, w, h, 6, { fill:T.fill, ring:T.hair });
      const iw = (w - pad*2) / items.length;
      const on = Math.floor(p.phase * 1.99) % items.length;
      items.forEach((lab, i) => {
        const ix = -w/2 + pad + i*iw;
        if(i === on) box(x, ix, -h/2 + pad, iw, h - pad*2, 5,
          { fill:T.paper, shadow:'rgba(10,10,10,.10)', blur:4, dy:1 });
        x.save(); x.translate(ix + iw/2, 0);
        type(x, lab, { px:12, align:'center', base:'middle', fill:i === on ? T.t1 : T.t2 });
        x.restore();
      });
    } },

  { id:'select', gen:'v2', tall:.30, pres:1.34, name:'Select', cssW:300, rest:1,
    job:'A field and its label — what the inspector is made of.',
    draw(x, W, H, p, T){
      const w = 260, h = 34;
      label(x, -w/2, -28, 'Format', 10, T);
      box(x, -w/2, -h/2 + 4, w, h, 6, { fill:T.paper, ring:T.hair });
      x.save(); x.translate(-w/2 + 10, 4 + 1);
      type(x, 'Feed · 4:5', { px:12.5, fill:T.t1, base:'middle' });
      x.restore();
      x.save(); x.translate(w/2 - 14, 2);
      type(x, '⌄', { px:12, fill:T.t3, align:'center', base:'middle' });
      x.restore();
    } },

  { id:'slider', gen:'v2', tall:.26, pres:1.38, name:'Slider', cssW:300, rest:.62,
    job:'The value is always readable, never on hover only.',
    draw(x, W, H, p, T){
      const w = 250, track = w - 46;
      label(x, -w/2, -22, 'Moment', 10, T);
      const u = clamp(p.phase);
      box(x, -w/2, -1.5, track, 3, 2, { fill:T.fill2 || T.fill });
      box(x, -w/2, -1.5, track*u, 3, 2, { fill:T.t1 });
      const cx = -w/2 + track*u;
      box(x, cx - 6.5, -6.5, 13, 13, 6.5, { fill:T.paper, ring:T.hair,
        shadow:'rgba(10,10,10,.22)', blur:3, dy:1 });
      x.save(); x.translate(w/2, 0);
      type(x, u.toFixed(2), { px:11, fill:T.t3, align:'right', base:'middle' });
      x.restore();
    } },

  { id:'badges', gen:'v2', tall:.22, pres:1.52, name:'Badge', cssW:280, rest:1,
    job:'The manner of a move, and the kind of a node.',
    draw(x, W, H, p, T){
      const set = [['Scrub', false], ['Reframe', false], ['Match', true], ['Flip', false]];
      const ws = set.map(([l]) => widthOf(x, l, 10, 500) + 16);
      const total = ws.reduce((a,b)=>a+b,0) + 8*(set.length-1);
      let cx = -total/2;
      set.forEach(([lab, solid], i) => {
        const t = part(p.reveal, i, set.length);
        x.save(); x.globalAlpha *= t;
        const w = ws[i], h = 18;
        box(x, cx, -h/2, w, h, 9, solid ? { fill:T.t1 } : { fill:T.fill, ring:T.hair });
        x.save(); x.translate(cx + w/2, 0);
        type(x, lab, { px:10, w:500, align:'center', base:'middle', fill:solid ? T.on : T.t2 });
        x.restore(); x.restore();
        cx += w + 8;
      });
    } },

  { id:'accordion', gen:'v2', tall:.52, pres:1.18, name:'Accordion', cssW:300, rest:1,
    job:'Cascading disclosure — one section open, the rest out of the way.',
    draw(x, W, H, p, T){
      const w = 280, rows = ['Subject','Treatment','Motion','Anatomy'];
      const open = Math.floor(clamp(p.phase, 0, .999) * rows.length);
      let y = -70;
      hair(x, -w/2, y, w, T.hair);
      rows.forEach((r, i) => {
        const isOpen = i === open;
        x.save(); x.translate(-w/2, y + 17);
        type(x, r, { px:12.5, w:500, fill:T.t1, base:'middle' });
        x.save(); x.translate(w - 8, 0);
        x.rotate(isOpen ? Math.PI : 0);
        type(x, '⌄', { px:11, fill:T.t3, align:'center', base:'middle' });
        x.restore(); x.restore();
        y += 34;
        if(isOpen){
          const bodyH = 30 * part(p.reveal, 0, 1);
          x.save(); x.globalAlpha *= .85;
          box(x, -w/2, y - 6, w, Math.max(0, bodyH), 4, { fill:T.fill });
          x.restore();
          y += Math.max(0, bodyH);
        }
        hair(x, -w/2, y - 1, w, T.hair);
      });
    } },

  { id:'tabs', gen:'v2', tall:.24, pres:1.44, name:'Tabs', cssW:280, rest:1,
    job:'Which generation of the set you are looking at.',
    draw(x, W, H, p, T){
      const items = ['v1 · Product','v2 · System'];
      const ws = items.map(l => widthOf(x, l, 12, 500) + 20);
      const total = ws.reduce((a,b)=>a+b,0) + 6;
      let cx = -total/2;
      const on = Math.floor(p.phase * 1.99) % items.length;
      items.forEach((lab, i) => {
        const w = ws[i];
        x.save(); x.translate(cx + w/2, 0);
        type(x, lab, { px:12, w:500, align:'center', base:'middle', fill:i === on ? T.t1 : T.t3 });
        x.restore();
        if(i === on) box(x, cx + 4, 13, w - 8, 1.5, 1, { fill:T.t1 });
        cx += w + 6;
      });
    } },

  { id:'empty', gen:'v2', tall:.30, pres:1.22, name:'Empty state', cssW:320, rest:1,
    job:'What is missing, and the one move that fixes it.',
    draw(x, W, H, p, T){
      const w = 300;
      x.save(); x.translate(-w/2, -16);
      type(x, 'Timeline is empty', { px:12.5, w:500, fill:T.t1, base:'middle' });
      x.save(); x.translate(0, 22); x.globalAlpha *= part(p.reveal, 1, 2);
      lines(x, 'Select a card and press Add to timeline. Order the shots, then fuse them.', 12, 400, w, 2)
        .forEach((l, k) => { x.save(); x.translate(0, k*17); type(x, l, { px:12, fill:T.t3, base:'middle' }); x.restore(); });
      x.restore(); x.restore();
    } },

  { id:'shotchip', gen:'v2', tall:.44, pres:1.12, name:'Shot chip', cssW:300, rest:1,
    job:'A shot in the timeline, and the manner that follows it.',
    draw(x, W, H, p, T){
      const cw = 78, ch = 98;
      x.save(); x.translate(-118, 0);
      box(x, -4, -ch/2 - 4, cw + 8, ch + 26, 6, { fill:T.fill });
      cover(x, p.im, 0, -ch/2, cw, ch, 3);
      x.save(); x.translate(0, ch/2 + 14);
      type(x, 'REVIEW PANEL', { px:9.5, w:500, track:.03, fill:T.t3, base:'middle' });
      x.restore();
      x.restore();
      /* the join, and the manner it carries */
      const t = part(p.reveal, 1, 2);
      x.save(); x.globalAlpha *= t;
      box(x, -16, -.5, 14, 1, .5, { fill:T.t4 || T.t3 });
      const lw = widthOf(x, 'Match', 10, 500) + 16;
      box(x, 4, -9, lw, 18, 9, { fill:T.fill, ring:T.hair });
      x.save(); x.translate(4 + lw/2, 0);
      type(x, 'Match', { px:10, w:500, align:'center', base:'middle', fill:T.t2 });
      x.restore();
      box(x, 8 + lw, -.5, 14, 1, .5, { fill:T.t4 || T.t3 });
      x.restore();
    } },
];

export const GENERATIONS = [
  { id:'v1', name:'Product', job:"The app's own controls" },
  { id:'v2', name:'System',  job:"The studio's chrome, made material" },
];
export const inGen = g => COMPONENTS.filter(c => (c.gen || 'v1') === g);

export const ANATOMY = {
  buttons:['primary','secondary','ghost','destructive'],
  badges:['scrub','reframe','match','flip'],
  accordion:['the headers','the open body'],
  empty:['the title','the way out'],
  shotchip:['the shot','the join + manner'],
  noterow:['index + crop','what was said','where it was said about'],
  panel:  ['header + actions','first note','the rest of the pass'],
  hud:    ['level + count','live transcript','binding chip'],
  step:   ['number','name','body'],
  fact:   ['key','value'],
  ringshot:['the crop','the ring'],
  status: ['the three states'],
  pills:  ['primary','secondary'],
  claim:  ['the line'],
  wordmark:['the name'],
};

export const byId = id => COMPONENTS.find(c => c.id === id) || COMPONENTS[0];

/* ── the material string ────────────────────────────────────────────────── */
export const encode = n => `ui:${n.comp}:${n.phase.toFixed(2)}:${n.scale.toFixed(2)}:${n.theme}`;
export function decode(s){
  const [, comp, phase, scale, theme] = String(s).split(':');
  return { comp, phase:+phase || 0, scale:+scale || 1, theme: theme || 'dark' };
}

/* ═══════════════════════════════════════════════════════════════════════════
   COMPOSE — the layer between a component and a frame.

   ⛔ Drawn material is composed for the rectangle it is asked for. A 380px
   status bar centred in a 1080×1350 frame is a stamp in a field of white; the
   component is not wrong, the composition is missing. A frame reserves space
   for a line and a mark, and hands the component only what is left.

   Layouts are ROLES, in the recipe sense — the layout proposes, the material
   decides (a claim layout on a component with no claim becomes `bare`).
   ═══════════════════════════════════════════════════════════════════════════ */
/* ═══════════════════════════════════════════════════════════════════════════
   LAYOUT — composition as DATA, not as a branch.

   The four built-ins used to be four `if` arms, which meant the only layouts
   that could exist were the ones already written. A layout is now a spec: where
   the subject sits, where a line sits, what the line says, where the mark goes
   — all in fractions of the frame, with type sizes in 1080-space so they scale
   with it.

   That makes a layout something that can be PROPOSED — by the combinatorics, or
   by a model — and executed without anyone writing code. Validation happens at
   the door (`sanitise`), so a bad spec is clamped, never thrown and never
   evaluated.
   ═══════════════════════════════════════════════════════════════════════════ */
export const LAYOUT_SPECS = {
  bare: { id:'bare', name:'Bare', job:'The control alone, edge to edge',
    subject:{ x:0, y:0, w:1, h:1 }, line:null, caption:null, mark:null },

  titled: { id:'titled', name:'Titled', job:'A line above, the control beneath',
    subject:{ x:0, y:.30, w:1, h:.62 },
    line:{ source:'claim', x:.5, y:.10, w:.86, size:54, align:'center', weight:500, max:3 },
    caption:null, mark:'bl' },

  captioned: { id:'captioned', name:'Captioned', job:'The control, then what it does',
    subject:{ x:0, y:0, w:1, h:.84 },
    line:null,
    caption:{ source:'name+job', x:.067, y:.875, w:.86, size:30 }, mark:'br' },

  stated: { id:'stated', name:'Stated', job:'The claim carries it; the control is evidence',
    subject:{ x:0, y:.58, w:1, h:.34 },
    line:{ source:'claim', x:.5, y:.34, w:.86, size:76, align:'center', weight:500, max:4 },
    caption:null, mark:'bl' },
};
export const LAYOUTS = Object.values(LAYOUT_SPECS);
export const layoutFor = (fmt, aspect) => aspect > 1.15 ? 'titled' : aspect < .8 ? 'captioned' : 'bare';

/* a layout may arrive from anywhere; nothing downstream should have to trust it */
const num = (v, lo, hi, dflt) => Number.isFinite(+v) ? Math.min(hi, Math.max(lo, +v)) : dflt;
export function sanitise(spec){
  if(!spec || typeof spec !== 'object') return LAYOUT_SPECS.bare;
  const s = spec.subject || {};
  const out = {
    id: String(spec.id || 'custom').slice(0, 40),
    name: String(spec.name || 'Custom').slice(0, 40),
    job: String(spec.job || '').slice(0, 120),
    subject: { x:num(s.x,0,.9,0), y:num(s.y,0,.9,0), w:num(s.w,.1,1,1), h:num(s.h,.1,1,1) },
    line:null, caption:null,
    mark: ['bl','br','tl','tr'].includes(spec.mark) ? spec.mark : null,
  };
  if(spec.line){
    const l = spec.line;
    out.line = {
      source: ['claim','name','job'].includes(l.source) ? l.source : 'claim',
      x:num(l.x,0,1,.5), y:num(l.y,0,1,.12), w:num(l.w,.2,1,.86),
      size:num(l.size,16,140,48),
      align: ['left','center','right'].includes(l.align) ? l.align : 'center',
      weight: [400,500,600].includes(+l.weight) ? +l.weight : 500,
      max:num(l.max,1,5,3),
    };
  }
  if(spec.caption){
    const c = spec.caption;
    out.caption = { source: ['name+job','job','claim'].includes(c.source) ? c.source : 'name+job',
      x:num(c.x,0,1,.067), y:num(c.y,0,1,.875), w:num(c.w,.2,1,.86), size:num(c.size,12,60,30) };
  }
  return out;
}

function subject(x, node, bx, by, bw, bh, p, T){
  const c = byId(node.comp);
  const want = node.scale * (c.pres || 1);
  const s = c.bleed ? want : Math.min(want, 1.2);
  stageIn(x, bx, by, bw, bh, c.cssW, s);
  c.draw(x, bw, bh, p, T);
  unstage(x);
}

const sourceText = (src, w, c) =>
  src === 'name' ? c.name : src === 'job' ? c.job :
  src === 'name+job' ? null : w.claim;

export function plate(x, W, H, node, w, ims, opt = {}){
  const T = themeOf(node.theme);
  const c = byId(node.comp);
  const p = { phase:node.phase, reveal:node.reveal ?? 1, words:w, im:ims[0], ims };

  if(opt.bare){ x.save(); subject(x, node, 0, 0, W, H, p, T); x.restore(); return; }

  /* the layout proposes, the material decides: a component that IS a line of
     copy cannot also be titled with one */
  const speaks = c.id === 'claim' || c.id === 'wordmark';
  let L = node.layoutSpec ? sanitise(node.layoutSpec)
                          : (LAYOUT_SPECS[node.layout] || LAYOUT_SPECS.bare);
  if(speaks && L.line) L = LAYOUT_SPECS.bare;

  const S = W / 1080;
  x.save();
  x.fillStyle = T.ground; x.fillRect(0, 0, W, H);
  dots(x, W, H, 28*S*2.2, 1*S*2.2, T === LIGHT ? 'rgba(10,10,10,.05)' : 'rgba(255,255,255,.05)');

  subject(x, node, L.subject.x*W, L.subject.y*H, L.subject.w*W, L.subject.h*H, p, T);

  if(L.line){
    const text = sourceText(L.line.source, w, c) || w.claim;
    const ls = lines(x, text, L.line.size*S, L.line.weight, L.line.w*W, L.line.max);
    const lh = L.line.size * 1.15 * S;
    x.save(); x.translate(L.line.x*W, L.line.y*H);
    ls.forEach((l, k) => { x.save(); x.translate(0, k*lh);
      type(x, l, { px:L.line.size*S, w:L.line.weight, fill:T.t1,
                   align:L.line.align, base:'middle', track:-.03 }); x.restore(); });
    x.restore();
  }

  if(L.caption){
    x.save(); x.translate(L.caption.x*W, L.caption.y*H);
    if(L.caption.source === 'name+job'){
      label(x, 0, 0, c.name, 22*S, T);
      x.save(); x.translate(0, 44*S);
      lines(x, c.job, L.caption.size*S, 400, L.caption.w*W, 2).forEach((l, k) => {
        x.save(); x.translate(0, k*40*S); type(x, l, { px:L.caption.size*S, fill:T.t2, base:'middle' }); x.restore(); });
      x.restore();
    } else {
      const text = L.caption.source === 'job' ? c.job : w.claim;
      lines(x, text, L.caption.size*S, 400, L.caption.w*W, 3).forEach((l, k) => {
        x.save(); x.translate(0, k*(L.caption.size*1.3*S));
        type(x, l, { px:L.caption.size*S, fill:T.t2, base:'middle' }); x.restore(); });
    }
    x.restore();
  }

  if(L.mark) mark(x, W, H, S, T, L.mark);
  x.restore();
}

function mark(x, W, H, S, T, corner = 'bl'){
  const right = corner === 'br' || corner === 'tr';
  const top = corner === 'tl' || corner === 'tr';
  x.save();
  x.translate(right ? W - 72*S : 72*S, top ? 56*S : H - 56*S);
  type(x, 'Pass', { px:26*S, w:600, fill:T.t3, base:'middle', track:-.01,
                    align: right ? 'right' : 'left' });
  x.restore();
}
