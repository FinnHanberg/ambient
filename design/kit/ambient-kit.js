/* ═══════════════════════════════════════════════════════════════════════════
   AMBIENT KIT — the voice-capture interface as material.

   Same contract as `canvas/src/components.js`: each entry is the real control
   drawn in CSS pixels with ONE phase parameter — the moment in its behaviour.
   A still is a moment you chose; a loop is that moment sweeping. Reached as

       ui:<id>:<phase 0-100>:<scale 0-300>[:<label>]

   so it crops, takes the bar, goes under the optic and exports with no special
   case anywhere downstream. To move this into Compose, drop the file into
   `canvas/src/` and spread AMBIENT into COMPONENTS — the import line below is
   already the path it will need.

   Every number is lifted from `Panel.swift` / `Chrome`: 12pt radius, 18pt
   gutter, hairline white 12%, rule white 7%, ground white 5.5%. If the app
   moves, these move with it and the picture stays true.
   Each entry also carries three traits — `family`, `mass` (0-1 visual weight) and
   `motion` — which are what `reel.html` reads to ORDER a sequence and to choose the
   transition between two cuts. The transition is never picked; it is derived.
   `cue` is the phase at which the component makes its ONE sound, and which voice.
   ⛔ A component that moves continuously (the waveform) gets NO cue — a sound per frame
   is noise, and the silence is what makes the others land.
   ⛔ A component MULTIPLIES `globalAlpha`, never assigns it — assigning punches the
   component through whatever fade the reel has it under, and the old cut keeps showing.
   ⛔ Nothing here invents copy. A component says what the interface says.
   ═══════════════════════════════════════════════════════════════════════════ */
import { lerp, clamp, easeOut, inOut,
         stage, unstage, type, widthOf, box } from './kit.js';

/* the app's own tokens — Chrome, in CSS pixels */
export const A = {
  ground: '#0e0e0f',
  hair:   'rgba(255,255,255,.12)',
  rule:   'rgba(255,255,255,.07)',
  on:     'rgba(255,255,255,.96)',
  on2:    'rgba(255,255,255,.55)',
  on3:    'rgba(255,255,255,.30)',
  live:   '#c8553d',
  radius: 12,
  gutter: 18,
};

/* the panel every surface sits in */
function panel(x, w, h, { r = A.radius } = {}){
  box(x, -w/2, -h/2, w, h, r, { fill: A.ground, shadow: 'rgba(0,0,0,.34)', blur: 18, dy: 5 });
  box(x, -w/2, -h/2, w, h, r, { ring: A.hair, ringW: 1 });
}

export const AMBIENT = [

/* ── the chord ────────────────────────────────────────────────────────────
   Two caps that depress together and stay lit while a pass runs. The only
   place the interface shows a held state. */
{ id:'am-chord', family:'keys', mass:0.8, motion:'press', cue:[[.20,'thock'], [.80,'click']], rest:0, name:'Chord', w:200, note:'⌃ fn · hold to speak',
  draw(x, W, H, p, scale){
    stage(x, W, H, 200, scale);
    const press = inOut(p, .18, .72);            // down, hold, up
    const caps = [['⌃', -46], ['fn', 46]];
    for(const [label, cx] of caps){
      const w = 76, h = 52, dy = press * 2.4;
      x.save(); x.translate(cx, dy);
      box(x, -w/2, -h/2, w, h, 11, {
        fill: `rgba(255,255,255,${lerp(.06, .26, press)})`,
        ring: `rgba(255,255,255,${lerp(.12, .34, press)})`, ringW: 1.2 });
      x.translate(0, 7.5);
      type(x, label, { px:21, w:500, align:'center', fill: A.on });
      x.restore();
    }
    unstage(x);
  } },

/* ── the waveform ─────────────────────────────────────────────────────────
   Bound to level, never to a clock. It rests flat, which is what makes a dead
   microphone visible instead of invisible. */
{ id:'am-wave', family:'level', mass:0.45, motion:'pulse', cue:[], rest:0, name:'Waveform', w:200, note:'input level, five bars',
  draw(x, W, H, p, scale){
    stage(x, W, H, 200, scale);
    const weights = [.5, .85, 1, .72, .42];
    /* one speech gesture: rise, two syllables, fall */
    const lvl = Math.sin(clamp(p) * Math.PI) * (0.62 + 0.38 * Math.sin(clamp(p) * Math.PI * 6));
    for(let i = 0; i < 5; i++){
      const h = Math.max(4, 4 + Math.abs(lvl) * 46 * weights[i]);
      box(x, -22 + i * 10, -h/2, 4, h, 2, { fill: A.on });
    }
    unstage(x);
  } },

/* ── the binding chip ─────────────────────────────────────────────────────
   Names what the next “this” resolves to, live, before the sentence is
   finished. Dips while the cursor travels; the ring pulses once on lock. */
{ id:'am-chip', family:'pill', mass:0.4, motion:'settle', cue:[[.70,'pip']], rest:1, name:'Binding chip', w:280, note:'link “Asset Supply©”',
  draw(x, W, H, p, scale){
    stage(x, W, H, 280, scale);
    const seek = inOut(p, .10, .58);             // away, then back
    const lock = clamp((p - .60) / .22);
    x.save();
    x.globalAlpha *= lerp(1, .5, seek);
    x.translate(0, seek * 3);
    const label = 'link “Asset Supply©”';
    const tw = widthOf(x, label, 13);
    const w = tw + 52, h = 32;
    box(x, -w/2, -h/2, w, h, h/2, { fill:'rgba(255,255,255,.05)',
      ring:`rgba(255,255,255,${lerp(.20, .12, seek)})`, ringW:1 });
    const rr2 = 4.5 * (1 + .5 * Math.sin(lock * Math.PI));
    x.beginPath(); x.arc(-w/2 + 19, 0, rr2, 0, Math.PI*2);
    x.strokeStyle = lock > .5 ? A.on : A.on2; x.lineWidth = 1.6; x.stroke();
    x.save(); x.translate(-w/2 + 32, 4.5);
    type(x, label, { px:13, fill:'rgba(255,255,255,.80)' }); x.restore();
    x.restore();
    unstage(x);
  } },

/* ── the count ────────────────────────────────────────────────────────────
   One scale bump per note, no number roll. The value changes at the peak of
   the bump so the eye lands on the new figure. */
{ id:'am-count', family:'pill', mass:0.28, motion:'bump', cue:[[.02,'tick'], [.35,'tick'], [.68,'tick']], rest:0, name:'Count', w:120, note:'notes held in this pass',
  draw(x, W, H, p, scale){
    stage(x, W, H, 120, scale);
    const step = clamp(p) * 3;                   // three increments across the sweep
    const n = 4 + Math.floor(step);
    const f = step - Math.floor(step);
    const bump = 1 + .2 * Math.sin(clamp(f / .28) * Math.PI) * (f < .28 ? 1 : 0);
    x.save(); x.scale(bump, bump);
    const label = String(n);
    const w = widthOf(x, label, 15, 500) + 26, h = 26;
    box(x, -w/2, -h/2, w, h, h/2, { ring:A.hair, ringW:1.2 });
    x.translate(0, 5.5);
    type(x, label, { px:15, w:500, align:'center', fill:A.on2 });
    x.restore();
    unstage(x);
  } },

/* ── the allowance ────────────────────────────────────────────────────────
   Drains in steps, never continuously — one step is one export. It takes
   colour only at the very end, and that is the single accent in the product. */
{ id:'am-meter', family:'bar', mass:0.34, motion:'drain', cue:[[.02,'tick'], [.36,'tick'], [.70,'blip']], rest:0, name:'Allowance', w:240, note:'100 notes free',
  draw(x, W, H, p, scale){
    stage(x, W, H, 240, scale);
    const steps = [1, .62, .30, .08];
    const t = clamp(p) * (steps.length - 1);
    const i = Math.min(steps.length - 2, Math.floor(t));
    const v = lerp(steps[i], steps[i+1], easeOut(t - i));
    const w = 190, h = 3.5;
    box(x, -w/2, -h/2, w, h, h/2, { fill:'rgba(255,255,255,.10)' });
    box(x, -w/2, -h/2, w * v, h, h/2, { fill: v < .14 ? A.live : 'rgba(255,255,255,.72)' });
    x.save(); x.translate(-w/2, -14);
    type(x, v < .14 ? 'last one' : `${Math.round(v * 100)} left`, { px:11, fill:A.on3 });
    x.restore();
    unstage(x);
  } },

/* ── the switch ───────────────────────────────────────────────────────────
   The knob stretches as it travels and settles back — the only liberty taken
   anywhere in the app, and it is two pixels wide. */
{ id:'am-switch', family:'control', mass:0.26, motion:'travel', cue:[[.30,'click']], rest:0, name:'Switch', w:120, note:'a drawn switch, never Toggle',
  draw(x, W, H, p, scale){
    stage(x, W, H, 120, scale);
    const t = easeOut(clamp((p - .12) / .5));
    const stretch = Math.sin(clamp((p - .12) / .5) * Math.PI);
    const w = 34, h = 20, pad = 2.5, kd = h - pad*2;
    box(x, -w/2, -h/2, w, h, h/2, {
      fill:`rgba(255,255,255,${lerp(.12, .82, t)})` });
    const kw = kd + stretch * 5;
    const kx = lerp(-w/2 + pad, w/2 - pad - kw, t);
    box(x, kx, -kd/2, kw, kd, kd/2, { fill: t > .5 ? '#141414' : '#9e9e9e' });
    unstage(x);
  } },

/* ── the ring landing ─────────────────────────────────────────────────────
   The mark arrives by contracting onto the target, so the motion itself
   points. The one animation carrying information rather than polish. */
{ id:'am-ring', family:'plate', mass:0.92, motion:'contract', cue:[[.40,'blip']], rest:1, name:'Ring lands', w:260, note:'what the cursor was on',
  draw(x, W, H, p, scale){
    stage(x, W, H, 260, scale);
    const w = 200, h = 126;
    /* the crop is a HAIRLINE, not a picture — a grey-blue gradient is an invented
       colour standing in for content nobody asked to see */
    box(x, -w/2, -h/2, w, h, 8, { fill:'rgba(255,255,255,.035)', ring: A.hair, ringW: 1 });
    const t = easeOut(clamp((p - .12) / .45));
    const r = lerp(26, 9, t);
    x.save();
    x.globalAlpha *= clamp(t * 2.2);
    x.translate(w * .10, -h * .04);
    x.beginPath(); x.arc(0, 0, r, 0, Math.PI*2);
    x.strokeStyle = '#fff'; x.lineWidth = 2.2; x.stroke();
    x.restore();
    unstage(x);
  } },

/* ── the panel ────────────────────────────────────────────────────────────
   One object at three sizes rather than three panels. Contents fade in after
   the box has finished moving, never during. */
{ id:'am-panel', family:'panel', mass:0.66, motion:'open', cue:[[.08,'swell'], [.58,'tick']], rest:0, name:'Panel', w:300, note:'closed · listening · transcript',
  draw(x, W, H, p, scale){
    stage(x, W, H, 300, scale);
    const t = easeOut(clamp(p / .55));
    const w = lerp(44, 240, t), h = lerp(26, 52, t);
    panel(x, w, h);
    const fade = clamp((p - .5) / .3);
    if(fade > 0){
      x.save(); x.globalAlpha *= fade;
      for(let i = 0; i < 3; i++){
        const bh = [8, 14, 10][i];
        box(x, -w/2 + 16 + i*7, -bh/2, 3.5, bh, 2, { fill: A.on });
      }
      x.save(); x.translate(-w/2 + 44, 4.5);
      type(x, 'the spacing is too tight', { px:12.5, fill:A.on2 });
      x.restore();
      x.restore();
    }
    unstage(x);
  } },

/* ── the action ───────────────────────────────────────────────────────────
   Press, then the label swaps for a tick in place. The button never moves
   position — only its contents change, so the eye stays put. */
{ id:'am-action', family:'pill', mass:0.44, motion:'press', cue:[[.36,'click'], [.56,'pip']], rest:0, name:'Action', w:220, note:'Copy brief → Copied',
  draw(x, W, H, p, scale){
    stage(x, W, H, 220, scale);
    const press = 1 - Math.abs(Math.sin(clamp((p - .3) / .22) * Math.PI)) * (p > .3 && p < .52 ? 1 : 0) * .05;
    const done = clamp((p - .52) / .2);
    x.save(); x.scale(press, press);
    const label = done > .5 ? '✓ Copied' : 'Copy brief';
    const tw = widthOf(x, label, 13, 500);
    const w = tw + 34, h = 30;
    box(x, -w/2, -h/2, w, h, h/2, { fill:'rgba(255,255,255,.92)' });
    x.translate(0, 4.5);
    type(x, label, { px:13, w:500, align:'center', fill:'#0e0e0f' });
    x.restore();
    unstage(x);
  } },

/* ── a captured note ──────────────────────────────────────────────────────
   The row the review panel is made of: index, the ringed crop, what you said,
   and where it came from. */
{ id:'am-note', family:'panel', mass:0.88, motion:'rise', cue:[[.18,'tick']], rest:1, name:'Note', w:360, note:'one row of a pass',
  draw(x, W, H, p, scale){
    stage(x, W, H, 360, scale);
    const t = easeOut(clamp(p / .5));
    const w = 322, h = 66;
    x.save();
    x.globalAlpha *= t; x.translate(0, lerp(10, 0, t));
    panel(x, w, h);
    x.save(); x.translate(-w/2 + A.gutter, 0);
    type(x, '1', { px:10, fill:A.on3, base:'middle' });
    /* the crop */
    const tw = 50, th = 33;
    box(x, 14, -th/2, tw, th, 4, { fill:'rgba(255,255,255,.035)', ring: A.hair, ringW: 1 });
    x.beginPath(); x.arc(14 + tw*.6, -th*.06, 4.5, 0, Math.PI*2);
    x.strokeStyle = '#fff'; x.lineWidth = 1.6; x.stroke();
    /* what was said, and where */
    x.save(); x.translate(76, -3);
    type(x, 'The spacing around “Account” is off', { px:12.5, fill:A.on });
    x.restore();
    x.save(); x.translate(76, 12);
    type(x, 'button · asset-supply.com', { px:10, fill:A.on3 });
    x.restore();
    x.restore();
    x.restore();
    unstage(x);
  } },
];

/* the material string a component is reached by, exactly as Compose writes it */
export const material = (id, phase, scale = 100, label) =>
  `ui:${id}:${Math.round(clamp(phase) * 100)}:${Math.round(scale)}${label ? ':' + label : ''}`;

export default AMBIENT;
