# Ambient

Hold **⌃ fn**, talk while you point, let go. It tells you what it understood,
asks before it does anything that matters, and gets out of the way.

    ./make.sh && open Ambient.app

## How it behaves

| | |
|---|---|
| **idle** | nothing on screen, microphone off |
| **hold ⌃ fn** | panel appears, transcribes, and names what your cursor is over |
| **release** | it reads the instruction and answers out loud |
| **it asks** | say "yes" / "no", click, or press **⌥↩** / **⌥.** |
| **after** | panel fades on its own |

It is not always listening. Audio is only fed to the recogniser while both keys
are down — releasing them genuinely stops it.

## Permissions

| Permission | Why | Without it |
|---|---|---|
| Microphone | hearing you | nothing works |
| Speech Recognition | transcription | nothing works |
| Accessibility | reading what's under the cursor **and seeing the ⌃ fn chord** | the hotkey does nothing at all |

Accessibility is the one that silently breaks everything — a global hotkey is
invisible without it. If it isn't granted the panel says so on launch and clears
itself the moment you grant it.

System Settings → Privacy & Security → Accessibility → add `Ambient.app`.
**After every rebuild, remove and re-add it** — the ad-hoc signature changes and
macOS treats it as a different app.

No Screen Recording, ever. Grounding is read from the accessibility tree.

## Connecting a model

Out of the box the reading is local and deterministic: it recognises an
instruction, names the target, and asks to send it. It does not converse.

To change that: **copy an Anthropic API key, then menu bar → "Connect model —
paste API key from clipboard."** It checks the key immediately and tells you
whether it worked. The key is stored in the Keychain, not on disk.

    Ambient --model      # is a key stored, and does it still work?

Connected, it reads each utterance properly — answers questions about what
you're pointing at, judges for itself when something needs confirming, and
replies in its own words.

**That path sends the transcript and the on-screen text context to the API.**
Never pixels, never the audio. With no key present nothing leaves the machine.

A key that is present but failing says so — "That API key was rejected",
"Couldn't reach the API" — rather than claiming no model is connected.

## What it's for

Walk an interface. Hold ⌃ fn, say what's wrong while pointing at it, let go.
Nothing replies, nothing asks permission, nothing interrupts — the note is
captured with whatever you were pointing at and you keep going.

When you've said everything: **"send it."** The batch goes into your open Claude
conversation and submits, so the work happens where the context already is.

| say | |
|---|---|
| anything | becomes a note, bound to what you pointed at |
| "send it" / "ship it" / "that's it" | sends the batch to Claude |
| "scratch that" | drops the last note |
| "how many notes" | says where you are |
| "clear the notes" | starts over |
| "show bottom ui" / "hide bottom ui" | the bottom rail |
| "show my cursor" / "hide my cursor" | the cursor pill |

Notes survive quitting. `~/.ambient/notes.json`, or `Ambient --notes` to read
the batch as it stands.

**It is silent by default.** Turn spoken replies on in the menu if you want them.

In a browser each note records the page URL, not just "a scroll area".

## Direct commands

If the on-device model is on, clear instructions still act directly rather than
becoming notes — "click this", "copy this", "open Figma", "read this". Without
it, everything is a note, which is the main job anyway.

## Where work goes

Confirmed instructions go to `~/.ambient/dispatch.sh` — the default queues them
to `~/.ambient/queue/` and copies to the clipboard. Whatever the script prints
is spoken back, so keep it to one line. Point it wherever you want work to run.

## When something doesn't work

    tail -f ~/.ambient/debug.log   # every step of every turn, always on

    Ambient --check                # proves transcription reaches ready, or says why not
    Ambient --selftest             # drives a whole turn with a fake utterance
    Ambient --selftest --empty     # the same with nothing transcribed
    Ambient --render out.png       # draws every panel state to an image
    ~/.ambient/ledger.log          # every exchange

No state waits forever. Anything still pending after a few seconds resolves
itself into a visible timeout that names the log.

## Known scope

Idle suggestions — it noticing something and speaking first — are not built.
That needs the model path connected to be anything but noise.
