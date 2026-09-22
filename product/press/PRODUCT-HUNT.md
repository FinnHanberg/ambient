# Product Hunt — launch staging

## Listing

**Name** Pass
**Tagline** (60 char max)
`Talk through your UI. Get a brief your agent can act on.` — 56

**Alternates**
`Point at it, say what's wrong, get the ticket` — 45
`Spoken design reviews, with the pixels attached` — 47

**Description** (260 char max)
Hold one chord and walk an interface out loud. Pass captures each remark with the page,
the element, and a crop with a ring on what you pointed at — then hands it to Claude,
Cursor or Codex. On device. It never sends anything for you. — 243

**Topics** Design Tools · Developer Tools · Artificial Intelligence · Mac
**Pricing** Free
**Launch** Tuesday 00:01 PT — the crowded days are Wed/Thu; Tue clears the weekend backlog
without competing with the midweek peak.

---

## Built assets

| File | What it is |
|---|---|
| `gallery/01.png` … `06.png` | The six slides, 2540×1520 (2× of PH's 1270×760) |
| `assets/icon.png` | App icon, 1024² — the ring mark on black |
| `launch.html` | Feed row + product page staging, rendered to `press/launch-staging.png` |

The upvote counts in the staging render are placeholders for composition only.
They are not projections and must not be quoted anywhere.

## Gallery (6 slides, monochrome, no captions burned in)

1. **The finished pass** — the review panel with three real notes and their thumbnails.
   The output leads; the input method is never the hook.
2. **The ring** — cropped tight on the marked element, with the spoken line beneath.
   Browser chrome is cropped out: it adds nothing and leaks tab titles.
3. **One hold** — the panel mid-pass, counter climbing.
4. **Per word** — two crops from "move this above that", resolved at different instants.
5. **What you get** — the literal output format, set as type.
6. **On device** — the spec, reversed out.

---

## Maker's first comment

> I build interface systems, and most of my day is now spent telling a coding agent
> what's wrong with a screen.
>
> The reviewing part takes seconds. Writing it down takes ten times longer —
> screenshot, crop, then a sentence explaining which of four similar buttons I meant.
>
> Pass is the fix. Hold control and fn, walk the page, say what's wrong while pointing
> at it. It samples the cursor continuously and timestamps every word, so when you say
> "this" it knows what you were pointing at *at that word*, not where the mouse ended
> up. Say "move this above that" and two different elements get marked.
>
> A pass is one take — pauses close notes and it keeps listening. Let go and you get a
> review panel: every note with its page, its element, and a crop with a ring on the
> subject. Copy it, or paste it into your agent and send it yourself. It never sends
> anything for you, and nothing leaves the Mac unless you do.
>
> Free while it's in beta. I'd like to know where the transcription falls down on
> accents and jargon — that's the part I can't test alone.

---

## Anticipated questions

**"How is this different from dictation apps?"**
Dictation gives you text. Pass gives you text bound to a place on screen. The output
format is the product.

**"Isn't this just screenshot + comment?"**
Those tools attach a picture to a comment. Pass resolves which element a pointing word
referred to, per word, and rings it.

**"Does it work outside the browser?"**
Yes — it captures pixels, so it works in any app. In a browser it additionally records
the page URL and the element's accessibility role and label.

**"Privacy?"**
On-device transcription, frames held in memory and discarded when the pass ends, and
capture halts at password fields. No account, no network requirement.

---

## Honest risk

Aloud (aloud.sh) ships a free tool in this space with a transcript-cleanup and
disambiguation layer Pass does not have. Launching without a clear answer on
per-word pointing as the wedge means being read as a lesser clone. Either lead
hard on the ring, or don't launch.
