# Pass — press kit

**Point at it. Say what's wrong.**
A macOS app that turns a spoken design review into a brief a coding agent can act on.

---

## Descriptions

**One line (12 words)**
Talk through an interface. Pass writes the brief, with the pixels attached.

**Short (28 words)**
Pass is a macOS app for reviewing interfaces out loud. Hold one chord, walk the
screen, say what's wrong. Each remark is captured with a crop of what you pointed at.

**Medium (58 words)**
Pass turns a spoken design review into something a coding agent can act on. Hold
control and fn, walk an interface, and say what's wrong as you point at it. Every
pause becomes a note, each carrying the page URL and a screenshot with a ring on the
element you meant. Let go and the pass appears for review.

**Long (110 words)**
Reviewing an interface is fast; writing the review down is not. The cost is the
screenshotting, the cropping, and the sentence explaining which of four similar
buttons you meant.

Pass removes that step. Hold control and fn, walk the screen, and talk. It records
what you said and — using the cursor position at the instant each word was spoken —
what you said it about. A pass across a whole page becomes an ordered list of notes,
each with the page URL, the element, and a crop with a ring on the thing in question.

Let go and the pass appears for review. Copy it, or paste it into Claude, Cursor or
Codex. Pass never sends anything on your behalf.

---

## What makes it different

**It resolves "this".** Most tools attach a screenshot to a comment. Pass samples the
cursor ten times a second and timestamps every transcribed word, then joins them: when
you say "this", it looks up where you were pointing *at that word*. Say "move this
above that" and two different elements are marked. The screenshot arrives with a ring
already on the subject.

**A pass is one take.** One hold covers a whole page. Pauses close notes; it keeps
listening. Twenty remarks become twenty entries, not one paragraph.

**It doesn't decide for you.** The pass ends in a review panel, not in a chat window.
Choosing where the work goes is the user's call.

---

## Facts

| | |
|---|---|
| Platform | macOS 26+, Apple silicon |
| Transcription | On device, system speech model |
| Screen capture | In memory while held; only claimed crops written to disk |
| Secure input | Capture halts automatically at password fields and auth sheets |
| Network | None required. Nothing is uploaded. |
| Output | Plain text with image paths |
| Price | Free during beta |

---

## Maker

Finn Hanberg — designer and design engineer, Antwerp. Works on brand and interface
systems, and builds the instruments that produce them. Pass came out of doing UI
review passes for AI coding agents and getting tired of describing in a sentence what
a cursor had already pointed at.

hansonmethod.com · finn@hansonmethod.com

---

## Assets

| File | Use |
|---|---|
| `assets/review.png` | Primary product shot — a finished pass |
| `assets/pointing.png` | A captured crop with the cursor ring |
| `assets/states.png` | Panel states during a pass |

Monochrome throughout. No accent colour, no alternate logo lockups.

---

## Boilerplate

Pass is a macOS app that turns spoken interface feedback into agent-ready briefs.
It runs on device and sends nothing on its own.
