# Test seams

An iOS simulator cannot be tapped by anything outside the app: `simctl` has no input API, and
synthetic clicks need Accessibility permission, which this host does not grant
(`AXIsProcessTrusted()` is false, so CGEvents are dropped). A port that cannot press its own
buttons can only be checked up to the first screen.

So the port adds four seams, all inert unless the matching environment variable is set, all
applied to the prepared tree by `prepare-tree.sh`. They are the difference between "the
lobby renders" and "a match was played and scored".

| Variable | Where | What it does |
| --- | --- | --- |
| `BIM_AUTOPLAY` | `lobby` constructor | presses PLAY ONLINE 3 s after the lobby is built |
| `BIM_AUTOFIGHT` | `matchmaking::update_display_with_game_proposal` | accepts the proposal 1 s after a second player arrives |
| `BIM_AUTORETURN` | `end_game::displayed` | takes the "new game" path 2 s after the result is shown |
| `BIM_AUTOPRESS` | `lobby::displayed` | presses `shop`, `settings` or `stats` 1 s after the lobby is shown |

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
