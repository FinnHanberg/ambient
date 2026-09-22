/* ═══════════════════════════════════════════════════════════════════════════
   COPY — the adaptive words.

   A component is a shape with holes in it. What fills the holes is not
   decoration: a note row saying "lorem ipsum" is not a photograph of the
   product, it is a drawing of one. Every line here is a line the product
   could really produce.

   Registers let the same component speak to a different audience without
   touching the component. `words(seed, register)` is pure — the same seed
   gives the same words, so a variant is reproducible and a board reloads
   identical.
   ═══════════════════════════════════════════════════════════════════════════ */

export const REGISTERS = [
  { id:'review',  name:'Design review',  job:'What you actually say walking a page' },
  { id:'bug',     name:'Defect',         job:'Sharper, closer to a ticket' },
  { id:'product', name:'Product voice',  job:'The page and the store' },
];

const BANK = {
  review: {
    note: [
      "The hero image is too dominant — bring it down so the headline leads.",
      "Increase the opacity of this, it's disappearing on white.",
      "Fix the spacing around this — it's tighter than the rest of the nav.",
      "This heading sits too tight against the image above it.",
      "Move this above that, and keep the rule between them.",
      "The contrast on this label is under what we agreed.",
    ],
    ctx: [
      "asset-supply.com · link · “Asset Supply©”",
      "asset-supply.com · button · “Account”",
      "asset-supply.com · image · “hero-01”",
      "asset-supply.com · heading · “The Art of Branding”",
    ],
    claim: [
      "Point at it. Say what's wrong.",
      "A review pass is one take, not forty tickets.",
      "It knows which “this” you meant.",
      "Stop writing down what you can already see.",
    ],
  },
  bug: {
    note: [
      "Focus ring is missing on this control entirely.",
      "This wraps to three lines at 1280 and pushes the row out.",
      "Tap target here is under 44 points on mobile.",
      "This state never returns — it sits spinning after the request fails.",
      "The count doesn't update until a second pass.",
    ],
    ctx: [
      "app.local · button · “Continue”",
      "app.local · listitem · “Row 4”",
      "app.local · textfield · “Email”",
      "app.local · alert · “Something went wrong”",
    ],
    claim: [
      "Say it once. Ship the fix.",
      "Every defect arrives with its evidence.",
      "The screenshot is already attached.",
    ],
  },
  product: {
    note: [
      "Hold one chord and walk an interface out loud.",
      "Every pause closes a note and it keeps listening.",
      "Each note carries the page, the element and the crop.",
      "Copy it, or paste it into your agent and send it yourself.",
    ],
    ctx: [
      "Runs on device · nothing is uploaded",
      "macOS 26 · Apple silicon",
      "Capture halts at password fields",
    ],
    claim: [
      "Talk through your interface. Get the brief.",
      "The pixels are already attached.",
      "One hold. Twenty notes.",
      "Nothing leaves the machine unless you send it.",
    ],
  },
};

const STEPS = [
  ['01', 'Hold', 'Control and fn together. The microphone runs only while you hold them.'],
  ['02', 'Talk', 'Walk the whole screen in one hold. Every pause closes a note.'],
  ['03', 'Send', 'Let go and the pass appears for review. Copy it, or paste it.'],
];
const FACTS = [
  ['Transcription', 'On device, using the system speech model. No audio is uploaded.'],
  ['Screen', 'Frames held in memory while you hold, discarded when the pass ends.'],
  ['Password fields', 'Capture stops whenever macOS reports secure input.'],
  ['Output', 'Plain text with image paths. Pass never sends on your behalf.'],
];
const PAGES = ['https://asset-supply.com/', 'https://hansonmethod.com/', 'app.local/settings'];

/* a small deterministic hash so a seed always gives the same words */
const pick = (arr, seed, salt = 0) => arr[Math.abs(Math.round(seed * 9301 + salt * 49297)) % arr.length];

export function words(seed = 0, register = 'review'){
  const b = BANK[register] || BANK.review;
  const step = pick(STEPS, seed, 3), fact = pick(FACTS, seed, 5);
  return {
    note:  pick(b.note, seed, 1),
    ctx:   pick(b.ctx,  seed, 2),
    claim: pick(b.claim, seed, 7),
    page:  pick(PAGES, seed, 11),
    count: 1 + (Math.abs(Math.round(seed * 991)) % 12),
    notes: [pick(b.note, seed, 1), pick(b.note, seed, 13), pick(b.note, seed, 29)],
    ctxs:  [pick(b.ctx, seed, 2), pick(b.ctx, seed, 17), pick(b.ctx, seed, 31)],
    stepNo:step[0], stepName:step[1], step:step[2],
    factKey:fact[0], fact:fact[1],
  };
}
