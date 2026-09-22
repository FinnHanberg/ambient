# Ambient — design notes

## What went wrong in v1, and what it taught

The first build listened constantly, judged every sentence with a local
heuristic, and showed a bar that was always on screen. It transcribed nothing at
all, for a reason no part of the system could report: macOS refuses
`SFSpeechRecognizer` unless Dictation is enabled system-wide, and returns
`kLSRErrorDomain 201` — onto an error path that restarted the request forever.
A dead recogniser and a quiet room produced identical output.

The second build then hung. The panel read *reading* and stayed there. The cause
was one line: when a turn produced no text, `release()` returned early — without
ever moving the session out of `.thinking`. Underneath it were two reasons the
text came back empty. Word timestamps were being mapped against wall clock from
engine start, but audio time only advances while the keys are held, so every
word fell outside its own turn's window and was filtered away. And the tap buffer
was being handed to another actor before conversion — by the time it ran, the
audio engine had already reused that memory.

Four corrections came out of the two failures, and they shape everything here.

**Errors must reach the surface.** Every failure the listener can hit is now a
state with a sentence attached, rendered on the panel. `--check` runs the whole
pipeline and prints why it didn't start, `--selftest` drives an entire turn with
a synthetic utterance, and `~/.ambient/debug.log` traces every step of every
turn, always on.

**No state may wait forever.** Anything pending is armed with a watchdog that
resolves it into a visible, named timeout. A turn that produces nothing still
ends — out loud, with "I didn't catch that" — because an interface that simply
stops is the one failure a user cannot report usefully.

**Do not build on a dependency you cannot see.** Transcription is now macOS 26's
`SpeechAnalyzer` / `SpeechTranscriber`, which carries its own downloadable model
and has no Dictation dependency. It also reports real audio time ranges per
word — which the deixis join needed and the old API only faked.

**Always-on was the wrong default.** Not for privacy reasons first, but because
it forced the hardest problem — deciding what was addressed to the machine —
before anything else worked. Hold-to-engage deletes that problem entirely.

## Hold ⌃ fn

Two modifiers, neither of which you type with, both of which you can hold
comfortably while moving a mouse. While held: the microphone is live, the panel
is up, and audio is fed to the analyser. On release, feeding stops.

This makes the system legible. There is no question of whether it is listening,
no wake word, no gate that might silently decline you, and no bar sitting on
screen reminding you it exists. Idle is *gone*.

It also removes an entire subsystem. The v1 gate — verb lists, deictic scoring,
dwell weighting, a confidence threshold — was an elaborate answer to "was that
meant for me". Holding a key answers it exactly.

## Deixis, properly this time

The cursor is sampled at 10 Hz into a 60-second ring. Each transcribed word now
carries its true audio time range from the transcriber, converted to wall clock.
A pointing word joins back to the pointer sample at its own instant, and the
accessibility element at those coordinates is resolved then.

"Move this above that" resolves to two different elements because you were
pointing at two different things when you said each word.

While you hold the keys the panel names what the cursor is over, live. You see
what "this" will bind to *before* you commit the sentence — which turns a guess
into something you can aim.

## It answers

Replies are spoken and written. Spoken lines are capped at one short sentence,
because speech cannot be skimmed; anything with detail goes on the panel where
the eye can jump around it.

The reply is never just an echo. It states what it understood in its own words
and, when acting would change something, ends in a question. You answer by
speaking — hold the keys again and say yes — or by clicking, or with ⌥↩ / ⌥.
Three ways, because the whole point is not having to reach for the keyboard.

The panel only accepts the mouse while it is waiting on an answer. The rest of
the time it ignores clicks entirely, so it can never swallow a click meant for
the thing underneath.

## Consequence

Nothing runs unasked. Locally, anything with a verb gets confirmed and anything
in the consequential set — delete, push, deploy, send, rename — is confirmed
more firmly. With a model connected, that judgement moves to the model, which is
told to ask whenever acting would change a file, send something, or the target
is ambiguous.

Execution stays a shell hook. Where work goes is the part most likely to change,
so it lives in five editable lines outside the binary, and whatever it prints is
read back aloud.

## The surface

Solid near-black, not a blur. A floating panel sits over unknown content, and a
material that samples a white document renders its own text unreadable. Opacity
carries the hierarchy; mono type for anything technical; five bars that answer
to the microphone so a dead input cannot look like a quiet room.

It appears where speech should — bottom centre — scales up from 96%, and leaves
on its own a few seconds after the exchange settles.

## What is deliberately missing

- **Idle suggestions.** He asked for it; it isn't built. Unprompted speech is
  only tolerable if it is right almost every time, and the local reading is not
  good enough to earn an interruption. It belongs behind the model path.
- **Continuous conversation.** Each hold is one turn. Multi-turn context is
  cheap to add and easy to make annoying; it should wait for evidence that a
  single turn is actually the limitation.
