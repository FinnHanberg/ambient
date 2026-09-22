/* ═══════════════════════════════════════════════════════════════════════════
   UI — the studio's own chrome, as a small component library.

   shadcn's INTENT, not its skin: dev-grade component specificity — real
   variants, real states, real disclosure — rendered in the house register
   (monochrome, one family, the opacity ladder). Nothing here invents a colour
   and nothing here is a one-off div.

   Every control returns its element and, where it has one, a `set()` so the
   caller never reaches back into the DOM to update a label.
   ═══════════════════════════════════════════════════════════════════════════ */

export const el = (t, c, p) => { const n = document.createElement(t); if(c) n.className = c; if(p) p.appendChild(n); return n; };

/* ── Button ──────────────────────────────────────────────────────────────
   variant: default · secondary · ghost · destructive     size: sm · md */
export function Button(parent, { label, variant = 'secondary', size = 'sm',
                                 onClick, icon, title, disabled } = {}){
  const b = el('button', `btn ${variant} ${size}`, parent);
  if(icon){ const i = el('span', 'ico', b); i.textContent = icon; }
  el('span', 'lbl', b).textContent = label;
  if(title) b.title = title;
  b.disabled = !!disabled;
  b.onclick = e => { e.stopPropagation(); onClick && onClick(e); };
  return b;
}

/* ── Toggle group — one of n, the honest form of a segmented control ─────── */
export function Toggle(parent, { options, value, onChange }){
  const g = el('div', 'toggle', parent);
  g.setAttribute('role', 'radiogroup');
  const paint = v => [...g.children].forEach(c => c.classList.toggle('on', c.dataset.v === v));
  options.forEach(o => {
    const b = el('button', 'toggle-i', g);
    b.dataset.v = o.value ?? o;
    b.textContent = o.label ?? o;
    b.onclick = () => { paint(b.dataset.v); onChange && onChange(b.dataset.v); };
  });
  paint(value);
  return { el:g, set:paint };
}

/* ── Select ──────────────────────────────────────────────────────────────── */
export function Select(parent, { options, value, onChange }){
  const wrap = el('div', 'select', parent);
  const s = el('select', '', wrap);
  options.forEach(o => { const opt = el('option', '', s); opt.value = o.value ?? o; opt.textContent = o.label ?? o; });
  s.value = value;
  s.onchange = () => onChange && onChange(s.value);
  el('span', 'chev', wrap).textContent = '⌄';
  return { el:wrap, set:v => s.value = v };
}

/* ── Slider — with the value always readable, never on hover only ───────── */
export function Slider(parent, { min = 0, max = 1, step = .01, value, onInput, format = v => v.toFixed(2) }){
  const wrap = el('div', 'slider', parent);
  const i = el('input', '', wrap); i.type = 'range';
  Object.assign(i, { min, max, step, value });
  const v = el('span', 'num', wrap); v.textContent = format(+value);
  const paint = () => {
    v.textContent = format(+i.value);
    i.style.setProperty('--pct', ((i.value - min) / (max - min) * 100) + '%');
  };
  i.oninput = () => { paint(); onInput && onInput(+i.value); };
  paint();
  return { el:wrap, set:n => { i.value = n; paint(); } };
}

/* ── Field — the label/control pair the inspector is made of ────────────── */
export function Field(parent, label, hint){
  const f = el('div', 'field', parent);
  const head = el('div', 'field-h', f);
  el('span', 'field-k', head).textContent = label;
  if(hint) el('span', 'field-hint', head).textContent = hint;
  return el('div', 'field-c', f);
}

/* ── Badge ───────────────────────────────────────────────────────────────── */
export function Badge(parent, text, tone = 'muted'){
  const b = el('span', `badge ${tone}`, parent);
  b.textContent = text;
  return b;
}

export const Separator = parent => el('div', 'sep', parent);

/* ── Accordion — the cascading disclosure the inspector needs ────────────
   Sections open one at a time by default; the point of disclosure is that the
   thing you are not doing is not on screen. */
export function Accordion(parent, { single = true } = {}){
  const root = el('div', 'acc', parent);
  const items = [];
  function add(title, { open = false, count } = {}){
    const item = el('div', 'acc-i', root);
    const head = el('button', 'acc-h', item);
    el('span', 'acc-t', head).textContent = title;
    if(count != null) Badge(head, String(count));
    el('span', 'acc-c', head).textContent = '⌄';
    const body = el('div', 'acc-b', item);
    /* the 0fr→1fr grid collapse clips its child, so the body needs exactly one
       child to hold everything; fields appended straight onto it leaked their
       height and every section stayed tall while closed */
    const inner = el('div', 'acc-inner', body);
    const set = o => { item.classList.toggle('open', o); };
    head.onclick = () => {
      const willOpen = !item.classList.contains('open');
      if(single) items.forEach(i => i.set(false));
      set(willOpen);
    };
    const api = { el:item, body:inner, set };
    items.push(api);
    set(open);
    return api;
  }
  return { el:root, add };
}

/* ── Tabs ────────────────────────────────────────────────────────────────── */
export function Tabs(parent, { options, value, onChange }){
  const bar = el('div', 'tabs', parent);
  const paint = v => [...bar.children].forEach(c => c.classList.toggle('on', c.dataset.v === v));
  options.forEach(o => {
    const b = el('button', 'tab', bar);
    b.dataset.v = o.value ?? o; b.textContent = o.label ?? o;
    b.onclick = () => { paint(b.dataset.v); onChange && onChange(b.dataset.v); };
  });
  paint(value);
  return { el:bar, set:paint };
}

/* ── Empty state ─────────────────────────────────────────────────────────── */
export function Empty(parent, { title, body }){
  const e = el('div', 'empty', parent);
  el('p', 'empty-t', e).textContent = title;
  if(body){ const p = el('p', 'empty-b', e); p.innerHTML = body; }
  return e;
}
