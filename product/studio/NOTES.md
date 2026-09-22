# Pass studio — the model

An infinite canvas whose material is the product's own interface.

    PART  →  CARD  →  TIMELINE  →  Board
    (the control)   (the treatment)   (the order, fused)   (saved)

Two clusters, and the whole tool is the relationship between them. **Parts** are
the app's controls lying loose on the ground — drawn live, no frame, no
furniture, the interface pasted in. **Cards** are frames carrying a treatment:
format, layout, surface, register. A card is a treatment waiting for a subject.

Drag a part onto a card and the card takes it. **The part stays where it is** —
it is the component, not a copy, and a palette you consume is not a palette. The
same part lands in five cards at five treatments; changing a card never touches
the part.

Grown from the CONTENT studio (`~/Claude 1/displace/canvas`), which formalised
`Source → Recipe → Set → Nodes → Frame + Board`. `src/world.js` is inherited
verbatim so the camera laws come with it rather than being rediscovered.

---

## The six files

| | |
|---|---|
| `src/world.js` | The ground. Camera, pan, zoom, select, fit. Inherited. |
| `src/kit.js` | Drawing primitives at frame scale. Every number lifted from the app and the site — a plate is a photograph of the real control, not a drawing of one. |
| `src/components.js` | The ten components, plus the compose layer that turns one into a frame. |
| `src/copy.js` | The adaptive words. Three registers; `words(seed, register)` is pure, so a variant is reproducible and a board reloads identical. |
| `src/combine.js` | Generative combinatorics and the five formats. |
| `src/timeline.js` | Fusion: the manner table, the cadence, and the fused render. |
| `src/ui.js` | The studio's own chrome as a component library — shadcn's intent (real variants, real states, real disclosure) in the house register. |
| `src/app.js` | Nodes, inspector, timeline dock, export, autosave. |

## Fusion

A card is a still at a chosen moment. A timeline is an ORDER of cards, and
fusion reads what changes between two of them to pick the manner of the move.
That is the intelligence: the manner is derived from the diff, never chosen at
random and never one transition applied to everything.

| what changes | manner | why |
|---|---|---|
| the moment only | **Scrub** | one control carried through its own behaviour — ONE draw with interpolated parameters, because crossfading a control against itself is a double exposure |
| the framing | **Reframe** | the subject holds, the composition travels; the outgoing card keeps moving rather than sitting still under the incoming one |
| the subject | **Match** | a dissolve over a held surface |
| the surface | **Flip** | the ground itself turns over — fast, because two shots that share nothing should cut |

Cadence is the iOS curve `cubic-bezier(.32,.72,0,1)`, evaluated by bisection. A
shot is **held 720ms** before it is allowed to move: a frame nobody can read is
not a frame. Durations follow the size of the change — scrub 900, reframe 760,
match 560, flip 320.

**Auto-fuse** orders the cards greedily so that adjacent shots differ in as
little as possible, scoring subject over surface over layout over format. A pile
of cuts is not a sequence; ordering first gives the fusion something to carry.

## Reveal

A second motion axis, separate from the moment. `phase` is where a control is in
its own behaviour; `reveal` is **how much of its anatomy is disclosed** — the
panel's rows, the listening chip, a fact's value. Each component declares its
anatomy in tiers, so a reveal sweep is a cascading disclosure rather than a fade.

## Two generations

The parts cluster is split by generation so progress is something you can look
at rather than remember. A tab in the bar hides the one you are not reading and
frames the one you are — the nodes are never destroyed, so a hidden part keeps
its place and its state.

| | |
|---|---|
| **v1 · Product** | the Pass app's own controls — note row, panel, listening panel, ringed crop, status, actions, step, fact row, wordmark, claim |
| **v2 · System** | the studio's own chrome, made material — button, toggle group, select, slider, badge, accordion, tabs, empty state, shot chip |

The v2 set is drawn from `studio.css`, the same way v1 is drawn from the app: a
plate of the Button is a photograph of the button the inspector actually uses.
The chrome that builds the frames is itself material, which means a release note
about the design system can be staged in the design system.

`reveal` earns its keep here — the button row discloses variant by variant, the
badge row manner by manner, the accordion header by header.

## Explore — asking for a proposal

Select a component and ask for a **layout**, a set of **variations**, or an
**animation**, with an optional line saying what you are after.

Everything returned is DATA over a schema this studio already executes — a
layout spec, parameter sets, an ordered shot list. **Nothing returns code and
nothing is evaluated.** Every field is clamped to a known range at the door
(`sanitise`, `cleanVariant`, `cleanShot`), so the worst a bad answer can do is
look wrong. A proposal lands as ordinary nodes you can then edit, vary and
export — nothing arrives that the studio could not have made by hand.

That is why layouts became data first. While a layout was four `if` arms, the
only layouts that could exist were the ones already written, and "propose a
layout" could only ever mean "pick one of four".

**Every ask has a local proposer that runs with no model at all.** The model
makes proposals better; it is not what makes the feature exist. And a model that
is configured but fails says why — reporting a rejected key as "no model" is a
lie the user cannot debug.

The key lives on the server (`server.mjs`), never in the page: a browser holding
an API key has it in the DOM, in devtools, and in every screenshot of the tool.
`$ANTHROPIC_API_KEY`, else `~/.ambient/studio-key`. With neither, `/api/ask`
answers 503 and says so.

## The material string

    ui:<component>:<moment>:<scale>:<surface>

A plate is addressed, not embedded. It crops, scales, joins a frame and exports
with no special case downstream.

## Moments, not clocks

`phase` is a scrubbed state variable. Each component declares the moment at
which it reads as a finished frame (`rest`), so a plate dropped on the canvas is
never caught mid-transition by accident. Sweep animates the moment; it is not an
idle spin, and it holds when stopped.

## Ten versions, not ten dice rolls

`combine.js` walks the product space on a golden-ratio stride rather than
sampling it randomly — random draws from a small space return near-duplicates
and call them variety. Every variant differs from every other in at least two of
`component · moment · scale · surface · register · layout`. Locking an axis
sweeps the rest: lock the component and you get ten moments of one control.

---

## Laws paid for here

- **Never give a utility class a name a variant already uses.** The drag chip was
  `.ghost` and the button variant is `.btn.ghost`, so every ghost button was
  fixed to 0,0 in black and the toolbar collapsed to 164px. It looked like a
  render artifact and was a selector collision.
- **A blur you cannot verify is a blur you should not ship.** `backdrop-filter`
  renders black in headless without a GPU, which hid the bug above for two
  rounds. Near-opaque solids read the same over a dotted ground.

- **Back the bitmap at the device pixel ratio.** A canvas whose backing store
  matches its CSS size renders at half resolution on a Retina display, and the
  whole tool reads as soft. The CONTENT law about 1× copies is about not
  rendering a 1080×1440 plate at 2× — it is not licence to ship a blurry 300px
  one. Zoom raises the factor to a ceiling and re-renders once the camera
  settles, so a framed plate is sharp rather than an upscaled bitmap.
- **Pack a palette by real height.** The parts are different shapes; a fixed row
  pitch collides a tall one with the next label and leaves a hole under a short
  one.
- **A part with no background of its own disappears.** The actions, the claim
  and the wordmark are white on white against a light ground, so parts are drawn
  on the light surface whatever the app's own surface is.

- **Drawn material is composed for the rectangle it is asked for.** A 380px
  status bar centred in a 1080×1350 frame is a stamp in a field of white. The
  component was never wrong — the composition was missing. Hence the layout
  layer (`bare · titled · captioned · stated`), which reserves space for a line
  and a mark and hands the component only what is left.
- **Presence is per component.** Filling .78 of the width makes a full panel
  correct and an atom tiny. Each component carries how much room it needs to
  hold a frame — clamped so it can never exceed what it was handed unless it
  declares `bleed`.
- **The layout proposes, the material decides.** A component that *is* a line of
  copy cannot also be titled with one; `claim` and `wordmark` fall back to bare.
- **An arrival is not a lifetime.** `inOut()` fades back out at 1, so using it
  for rows arriving made the *rest* moment — the finished frame — render empty.
  Anything that arrives and stays is `easeOut`, not `inOut`. This was invisible
  on the canvas at phase .5 and only appeared at export.
- **Display copies at 1×.** A redrawn plate gains nothing from 2× and costs
  ~25 MB a frame once there are a few dozen on the plane.
- **Autosave compares the serialisation** every 1.2 s rather than asking thirty
  call sites to report mutations, and is never guarded on `document.hidden` — a
  preview pane and a backgrounded tab both report hidden, so saving would stop
  exactly where you cannot watch it.
- **A camera is never zero** (inherited): a ground reporting zero height writes
  `scale(0)` onto the plane, which looks exactly like a blank page and survives
  the reload once autosaved.

## Verifying

`timeline-test.html` drives auto-fuse and parks the playhead mid-transition, so
the dissolve can be looked at. `proof.html` renders plates at their real export
size, and `drag-test.html`
exercises part → card without a hand on the mouse (it asserts the card takes the
subject, keeps its treatment, and leaves the part on the canvas). The canvas is not a
sufficient check — a plate that reads fine at a third of its size can be empty
at 1080, as the arrival bug proved.

## Open

Components are stills at a chosen moment; a looping export (the moment sweeping
across a clip) is not wired. There is no multi-plate frame yet — one subject per
frame. Boards are localStorage only.
