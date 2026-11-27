# Parity inventory

Every surface the upstream app has, with the source that implements it, what this port does with
it, and the evidence that it works. Written because "it runs and reaches the arena" says nothing
about the screens nobody has opened yet. The rule for this file: **no row may say "done" without
a file in `03_evidence/`, a log line, or a server-side observation behind it.**

Upstream paths are relative to `build/ios-src/` (the prepared tree from `prepare-tree.sh`).

## Screens — `apps/axmol/main/src/bim/axmol/app/screen/`

| Surface | Source | Status | Evidence |
|---|---|---|---|
| Lobby | `lobby.cpp` | verified | `03_evidence/lobby-safe-area.png` — gear, coin wallet and title clear of the Dynamic Island |
| Matchmaking | `matchmaking.cpp` | verified | `03_evidence/matchmaking.png`; paired with a real opponent on `bim-prod.jorge.st` |
| Arena | `online_game.cpp` | verified | `03_evidence/live-arena.png`, `game-board.png`, `arena-safe-area.png` — d-pad and bomb not clipped |
| End of game | `end_game.cpp` | verified | `03_evidence/end-of-game.png` — result, wallet reward, NEW GAME |
| Features | `game_features.cpp` | verified | `03_evidence/features-screen.png` — 4 assigned slots, one buyable at 1,000, 19 locked, the "up to 2 features" footer, RANDOM / ERASE / back. The catalogue and prices arrive in `/client/config`; the player's own slots come with the profile; `/client/game-feature/*` is only called when a slot is changed |
| Shop | `shop.cpp` | **not ported** | no StoreKit; the lobby shows upstream's "not available on this platform" path |

Note on the features screen: the prices and the locked/assigned split are server data, so the row
is evidence that the config and profile endpoints work on iOS. It is **not** evidence for
`/client/game-feature/*`: the network log shows no request from that family when the screen opens
(the network log, whose raw output was withdrawn from the repository because the first version of
the seam recorded request bodies), which corrected an earlier claim in this file.

## Popups — `apps/axmol/main/src/bim/axmol/app/popup/`

| Surface | Source | Status | Evidence |
|---|---|---|---|
| Settings | `settings_popup.cpp` | verified | `03_evidence/settings-safe-area.png` — music, effects, vibrations, language, links |
| Statistics | `player_statistics_popup.cpp` | verified with data | `03_evidence/statistics-played.png` — after a real match: Games 1, Defeats 1, Victories 0, Draws 0, success rate **0%** (the gauge shows a dash only when there are no games, `03_evidence/statistics-popup.png`) |
| Nickname editor | `nickname_editor_popup.cpp` | verified | the account's nickname changed server-side (`user_1097` → `user_1102`) |
| Language | `language_popup.cpp` | verified | `03_evidence/language-popup.png` — 8 of the 14 shipped locales listed, current one ticked, Weblate footer; switching goes through the "change the language setting?" yes/no |
| Message | `message.cpp` | verified | `03_evidence/no-server-dialog.png` — the offline path renders through it |
| Debug | `debug_popup.cpp` | **out of scope** | upstream dev tool, no entry point without the debug gesture |

## Parts and subsystems

| Surface | Source | Status | Evidence |
|---|---|---|---|
| Wallet | `app/part/wallet.cpp` | verified | coins drawn in the lobby and in the end-of-game reward |
| Audio mixer | `modules/axmol/audio/` | **source-level only** | `play2d` returns ids 1 and 2 for `menu.ogg` and `tick.ogg` with `BIM_AUDIOLOG`; `-1` when the file is missing. Nothing here can hear it |
| Haptics | `iscool-core` iOS patch 0004 | **source-level only** | `UIImpactFeedbackGenerator` compiled and reached; a simulator has no motor |
| Preferences | `iscool/preferences`, `bim/app/preference/` | verified | music/effects/vibrations/rules accepted at launch; `BIM_AUTOMUTE` proves the mute path |
| Localization | 14 `.mo` files in `assets/i18n/` | verified | chose `es_ES` through the popup, quit, relaunched: the lobby comes back in Spanish (`03_evidence/lobby-spanish.png` — TIENDA, ESTADÍSTICAS, JUGAR EN LÍNEA) |
| Analytics | `bim/app/analytics_service.hpp` | events emitted, no HTTP | the log shows `Event 'button', id='play' where='lobby'`, `Screen 'online-game', player-count='2'`, `Event 'credit', currency='coins' cause='game-reward' amount='10'`. `BIM_NETLOG` shows **no** request to any analytics host during launch, a match or a reward, so either it batches elsewhere or it is compiled without a key |
| Screen rotation | `Info.plist` (portrait only) | **unverified on hardware** | the plist declares portrait only; upstream is portrait too, so this is a deliberate lock, not a port |
| Background / foreground | `ax::Director` pause path | **unverified** | nothing has stopped and resumed this app on a real phone |

## Server API — `https://bim-prod.jorge.st`

The same twelve endpoints the APK's `libbim.so` contains. A row is "exercised" only if something
in this port called it and the result was observed.

| Endpoint | Used by | Status |
|---|---|---|
| `/client/authenticate` | launch | exercised — account created, nickname returned |
| `/client/me` | launch | exercised — 200 with user_id, nickname, coins |
| `/client/config` | launch | exercised — `POST /client/config` → **200**, and the returned catalogue is what the features screen lists; one earlier session saw a 403 |
| `/client/game-feature/assign-slots` | features screen, on change | **not** called when the screen opens (network log); fires only when slots are assigned |
| `/client/game-feature/buy-slot`, `/buy-feature`, `/clear-slot` | features screen | present, **not exercised** (would spend coins from a live account) |
| `/client/account/update-nickname` | nickname editor | exercised |
| `/client/users/profiles`, `/client/transfer-legacy-inventory` | matchmaking / migration | presence only, not exercised |
| `/client/game/consume-reward` | end of game | exercised — reward credited |
| `/client/billing/validate-purchase` | shop | **unreachable**, no StoreKit |

## What the README is allowed to claim

Verified above: six screens (one not ported), five of six popups, wallet, preferences, the
multiplayer round trip, and the CI-built artefact.

Verified at source level only, and stated as such: audio, haptics.

Not verified anywhere: analytics delivery (events exist, no request observed), foreground and
background, device performance, and every purchase path.

## How to re-check a row

Simulator seams live in `01_port/TEST_SEAMS.md` and are compiled **only** when
`BIM_TEST_SEAMS=1`, which `build-app.sh` sets for simulator builds and clears for device builds.
A release IPA therefore cannot be driven by an environment variable, and `make-ipa.sh` fails if
`BIM_AUTO*` strings are found in the binary.
