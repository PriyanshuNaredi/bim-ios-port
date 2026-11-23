# Test seams

An iOS simulator cannot be tapped by anything outside the app: `simctl` has no input API, and
synthetic clicks need Accessibility permission, which this host does not grant
(`AXIsProcessTrusted()` is false, so CGEvents are dropped). A port that cannot press its own
buttons can only be checked up to the first screen.

So the port adds six seams, all inert unless the matching environment variable is set, all
applied to the prepared tree by `prepare-tree.sh`. They are the difference between "the
lobby renders" and "a match was played and scored".

**They are compiled out of device builds.** Every seam sits inside `#if BIM_TEST_SEAMS`;
`build-app.sh` defines it as 1 for a simulator build and 0 for a device build, and
`make-ipa.sh` refuses to package a binary that still contains `BIM_AUTO*` strings. Automation
that ships is automation that can drive someone else's phone.

| Variable | Where | What it does |
| --- | --- | --- |
| `BIM_AUTOPLAY` | `lobby` constructor | presses PLAY ONLINE 3 s after the lobby is built |
| `BIM_AUTOFIGHT` | `matchmaking` constructor | accepts the proposal 1 s later, on the same slot the FIGHT button uses |
| `BIM_AUTORETURN` | `end_game::displayed` | takes the "new game" path 2 s after the result is shown |
| `BIM_AUTOPRESS` | `lobby` constructor | 4 s after the lobby is built: `shop`, `settings`, `stats`, `nickname`, `features` (opens the features screen) or `language` (settings, then the language popup 8 s after the settings popup is built) |
| `BIM_AUTOEFFECT` | `lobby` constructor | plays the named effect (`tick`, `click`, …) through the real mixer 4 s after the lobby is built |
| `BIM_AUTOMUTE` | `application::apply_local_preferences` | forces `music`, `effects` or `all` muted without touching the stored preference |
| `BIM_LANGUAGE` | `language_popup` constructor | picks a locale (`es_ES`, …) 12 s later through the same confirm path the button uses |
| `BIM_AUTOMESSAGE` | `message_popup::show_yes_no` | answers OK 1 s later, so the language change actually commits |
| `BIM_AUDIOLOG` | `bim/axmol/audio/mixer.cpp` | appends one line per `play2d` to `$HOME/audio.log`, with the source id, so you can see whether axmol opened the file |

They read `getenv` at the moment they matter, so a build with the seams compiled in behaves
exactly like a plain build when the variables are unset. Launch them through the simulator
with the `SIMCTL_CHILD_` prefix, which is how `simctl` forwards an environment to the app:

```bash
UDID=C5E1129B-3ED4-4BD0-8073-5E1FA6B8A10D
SIMCTL_CHILD_BIM_AUTOPLAY=1 \
SIMCTL_CHILD_BIM_AUTOFIGHT=1 \
SIMCTL_CHILD_BIM_AUTORETURN=1 \
  xcrun simctl launch --console-pty "$UDID" bim.app
```

## What the seams have already proven

In one run of the command above, without a single tap:

* the lobby authenticates against `https://bim-prod.jorge.st`,
* PLAY ONLINE joins a real lobby with another player (`Nimue Alban` next to `user_1097`),
* the FIGHT proposal launches the arena with crates, two kings, bombs and a running clock,
* the match ends with **YOU LOST!**, a `+10` coin reward and a NEW GAME button,
* and NEW GAME starts a second match, which renders correctly.

Screenshots: `03_evidence/{lobby-simulator,matchmaking,game-board,end-of-game}.png`.

## One seam that had to be corrected

`BIM_AUTORETURN` was first scheduled from the `end_game` constructor. The screen is
constructed early, while the match is still running, so the seam pressed "new game" before
the result existed and left the arena blank and oversized
(`07_logs/sim-27.png`). It now hangs off `displayed()`, which is the same moment a player
could press the button. Worth remembering: a seam scheduled from a constructor tests a state
transition the UI does not allow.

## The seams that exist only because nothing here can hear

The simulator's audio goes to the host, and this host's speaker does not reach its microphone:
`afplay /System/Library/Sounds/Glass.aiff` and the game's menu music both leave the mic at the
same floor (`rms≈0.008`, peak matched), so a recording proves nothing either way. Rather than
claim "audio works, trust me", the port checks the layer underneath:

```bash
SIMCTL_CHILD_BIM_AUDIOLOG=1 SIMCTL_CHILD_BIM_AUTOEFFECT=tick xcrun simctl launch "$UDID" bim.app
# then, from the app's container:
#   music audio/menu.ogg id=1
#   effect audio/tick.ogg id=2
```

An id other than `-1` is not a guess. `ax::AudioEngine::play2d` returns
`INVALID_AUDIO_ID` if the file is missing, if `lazyInit()` fails, or if the backend cannot create
a player; so `id=1` means the OGG was found, decoded and handed to OpenAL as a live source. Run
with `BIM_AUTOMUTE=all` and the same line reads `music audio/menu.ogg id=-1 (FAILED)`, which is
the mute branch doing its job.

What that does *not* prove is audibility on a real phone — codec, route and volume are the
device's business. That check is item 3 in `DEVICE_TEST.md`.

## Two ways this file has been wrong

Both are worth reading before trusting any seam here.

**A seam scheduled from a constructor tests a transition the UI does not allow.** `BIM_AUTORETURN`
was first scheduled from the `end_game` constructor, pressed NEW GAME while the match was still
running, and produced a blank arena. It is now scheduled from `displayed()`, which is the moment
the result is actually on screen.

**This file described seams that no longer existed.** `BIM_AUTOFIGHT` and `BIM_AUTORETURN` were
documented here for a whole round while a rewrite of `prepare-tree.sh` had silently dropped the
edits that install them: `grep BIM_ build/ios-src/.../matchmaking.cpp` returned nothing, yet this
table said the seam worked. The port still reached an arena during that round — because a real
opponent accepted the match. Documentation of an automation path is worthless if nothing checks
that the path exists; `prepare-tree.sh` now prints how many edits it applied, and the two seams
are back with a compile-time guard.
