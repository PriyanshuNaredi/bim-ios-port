# REA — `bim-17.apk` (Bim! 17) → iOS

Deep reverse-engineering analysis of the Android artefact, performed **before** any port
work. Every number below was produced by a command in §9, not estimated.

---

## 1. What the artefact is

| | |
|---|---|
| Package | `bim.app` |
| Version | `versionName 17`, `versionCode 1700` (APK signed 2026-11-15) |
| Label | `Bim!` |
| Size | 65,295,456 bytes; 302 zip entries, 76,152,678 bytes uncompressed |
| Permissions | `INTERNET`, `ACCESS_NETWORK_STATE`, `VIBRATE` — nothing else |
| Activities | one native activity (`android.app.lib_name`), no screens in `res/layout` |
| Upstream | **open source, AGPL-3.0**: <https://github.com/j-jorge/bim> |
| Upstream version 17 | commit `f3e0e72a` ("Bump version to 17."); `HEAD` is already 18 (`f744e54a`) |

Bim! describes itself as *"an open-source multiplayer online mobile game of the last man
standing genre"*: up to four players in a small arena, bombs destroy walls, broken walls
expose bonuses (extra bombs, longer blast), and players unlock gameplay *features* that
apply to everyone in the match.

**This changes the port completely.** The Android app is a build of a public AGPL source
tree — there is no need to reconstruct behaviour from a binary, and a clean-room Swift
reimplementation of a 46,685-line C++ game would be both enormous and *less* faithful.

---

## 2. Engine and binary layout

* Engine: **Axmol** `2.11.5.0j` — a maintained Cocos2d-x fork, from a *pinned fork*
  (`j-jorge/axmol`, tag `v2.11.5.0j`). Proof: `{}axmol: ERROR: Failed to compile shader`,
  `.backroom/packages/axmol/source/core/platform/android/Device-android.cpp`, and
  `setup/dependencies/recipes/10-axmol.sh` pinning the fork and version.
* Game logic: C++ in `libbim.so` — 13,416,264 bytes (arm64-v8a), 9,954,336 (armeabi-v7a),
  14,550,288 (x86_64). `nm -g` reports **0 exported symbols** and no `cocos2d`/`lua_*`/
  `JsEngine` strings: stripped native code, no scripting layer. There is nothing to patch
  in place and no script bundle to re-run.
* Java/Kotlin layer: a thin wrapper plus ordinary Android SDKs (androidx, Jetpack Startup,
  ProfileInstaller, Play billing/transport). It contains no game code.
* Networking: `boost::asio` inside the .so (UDP + asio socket services are in the symbol
  table), REST through libcurl. Business endpoints found in the binary:

```
https://bim-prod.jorge.st/client/authenticate
https://bim-prod.jorge.st/client/config
https://bim-prod.jorge.st/client/me
https://bim-prod.jorge.st/client/account/update-nickname
https://bim-prod.jorge.st/client/billing/validate-purchase
https://bim-prod.jorge.st/client/game-feature/{assign-slots,buy-feature,buy-slot,clear-slot}
https://bim-prod.jorge.st/client/game/consume-reward
https://bim-prod.jorge.st/client/transfer-legacy-inventory
https://bim-prod.jorge.st/client/users/profiles
```

`GET /client/config` answers **403 Forbidden** to an unauthenticated request, so the
server-side tunables (`arena-width-in-blocks`, `feature_flags.*`, page sizes) cannot be
read from the outside; they are fetched at run time by the client.

---

## 3. Assets — everything the look is made of

```
assets/
  animations.json          22,621 B    93 named animations
  colors.json                 491 B    23 named colours
  resources.json            1,557 B    font aliases, texture list, sheets, shaders, styles
  sprite-sheet-{1,2,3}.{plist,png}     347 atlas frames total
  style/application.json  337,185 B    the merged UI stylesheet (generated)
  style/launch/application.json
  audio/{menu.ogg 2.34 MB, tick.ogg}
  font/  (12 files: LuckiestGuy, OpenSans ×4, NotoSansKR ×2, NotoSansTamil ×2, DaysOne,
          BagelFatOne, NotoColorEmoji)
  i18n/  (20 gettext catalogues; en.mo has 90 messages)
  matchmaking/{en,fr}-{0,1,2,3}.txt
  texture/  (16 PNGs: arena/menu/victory/defeat/gifts/search/features patterns, grass,
             loading, stars, squares, carbon, bomb-stencil)
  shaders/shine_fs
  *.json / *_vs / *_fs          axmol shader programs, shipped as data
```

### 3.1 Atlas frame groups (sprite sheets 1–3)

| group | frames | meaning |
|---|---|---|
| `sprites/player` | 69 + 87 | 4 characters × idle/walk in 4 directions, shield variants |
| `sprites/flame` | 23 | bomb blast: `origin`, `arm`, `tip` × 4 directions |
| `sprites/fog` | 53 | fog-of-war overlay |
| `sprites/menu` | 50 + 11 + 3 | lobby, shop, matchmaking chrome |
| `sprites/smoke` | 11 | crate destruction puff |
| `sprites/crate` | 7 + 4 | destructible wall |
| `sprites/features` | 7 + 4 | feature icons |
| single frames | | `bomb.png`, `power-up-{bomb,flame,shield,invisibility}.png`, `solid-wall.png`, `fence-{up,down,left,right}.png`, `arena-{border,corner}.png`, `pixel.png`, `transparent.png` |

Common frame size is **128×128** (81 of 347 frames), which is the arena tile size in the
atlas; character frames are 124×188 … 128×192 (a player stands taller than one tile).

### 3.2 Animation timings — the one place the binary's tuning is fully visible

`animations.json` is plain data, so the game's animation clock is recoverable exactly:

| animation | frame | count | total |
|---|---|---|---|
| `walk_*_N` | 45 ms | 8 | 360 ms per walk cycle |
| `idle_*_N` | 100 ms | 1 | static |
| `burn` (player in flame) | 60 ms | 15 | 900 ms |
| `die_N` | 60 ms | 5 | 300 ms |
| `flame_*_warm_up` | 30 ms | 3 | 90 ms |
| `flame_*_burn` | 30 ms | 5 | 150 ms |
| `flame_*_cool_down` | 30 ms | 3 | 90 ms |
| `crate.burn` | 45 ms | 6 | 270 ms |
| `smoke.in_out` | 30 ms | 11 | 330 ms |

A flame's visible life is therefore **90 + 150 + 90 = 330 ms**; a crate takes 270 ms to
disappear; a walking player cycles every 360 ms.

### 3.3 UI is data, and its *source* is nicer than the APK's merge

The 337 KB `style/application.json` in the APK is **generated**: upstream keeps 25 small
style files (`assets/style/app/screen/{lobby,online-game,shop,matchmaking,end-game,
directional-pad,joystick,bomb-button,game-features}.json`, `assets/style/popup/*`,
`assets/style/layout/{center,fill}.json`, …) and merges them with a `style-merger` tool at
build time (`assets/style/CMakeLists.txt`, `find_program(style_merger style-merger
REQUIRED)`). The port gets the source files, not the blob: 446 distinct style keys, 75
`text.i18n` references, 40 icons, 63 sound-click hooks.

### 3.4 Text — the whole UI vocabulary

`i18n/en.mo` has 90 messages: menu (`NEW\nGAME`, `PLAY ONLINE`, `SHOP`, `STATISTICS`,
`Settings`, `Features`), lobby (`Waiting for your opponents…`, `You can start a
two/three-players game now or wait for more players!`), result screens (`You won!`,
`You lost!`, `Draw game!`, `FIGHT!`), shop (`You need more coins to purchase this item!`,
`×1000`), controls (`D-pad`, `Stick`, `Analog stick, it pops where you tap and follows the
drag.`, `Directions on the left, actions on the right.`), statistics (`Victories`,
`Defeats`, `Draws`, `Success rate`), plus **twelve gameplay-feature announcements**:

* fog of war — *"A thick fog covers the arena. You can't see were you did not go!"*
* shrinking arena — *"Falling blocks reduce the arena after two minutes!"*
* fences — *"Fences block the players, but the flames can go through!"*
* invisibility power-up — *"Find the invisibility power up to disappear from the screen of
  all other players!"*
* barrel — *"Find this incredibly strong barrel, it will save you from one hit!"*

Localised into 20 languages (br, de, en, es, fr, kab, ko, oc, pt, pt_BR, ru, ta, tr, uk, …).

---

## 4. Gameplay, as the data describes it

A Bomberman-shaped last-man-standing game on a **tile arena**:

* Arena composed of `arena-border`/`arena-corner` edges, `solid-wall` blocks, and
  destructible `crate`s; `fence-*` pieces come from the fences feature.
* Players walk in 4 directions (`idle_*`/`walk_*` per direction per character), drop
  bombs, and the blast is a cross of `flame` pieces: an `origin` in the bomb's cell, `arm`
  along the ray, `tip` at the end — so blast length is a data-driven count of `arm` tiles.
* Power-ups found under broken crates: extra bomb, longer flame, shield (the shield art is
  a full second set of walk/idle animations, 32 frames), invisibility, barrel.
* Death is `burn` (900 ms) then `die_N`; survivors get victory/defeat/draw screens with
  statistics (`arena_victories`, `arena_defeats`, `arena_draws`, `arena_games_total`).
* Matches are **online**: matchmaking, lobbies, nicknames, coins, IAP, a stats dashboard,
  and a live "N games being played right now" counter.
* Client settings: D-pad *or* analogue stick, left/right-handed layout, music, sound
  effects, vibrations, language.

---

## 5. Does the APK match the public source?

Yes — it is a build of it. Evidence:

* `assets/` diffs against upstream `f3e0e72a` in **17 files**, and every one is a build
  output: the six generated `.mo` catalogues, the merged style JSONs, the PNGs that
  `static-assets/` feeds into `assets/texture/`, and the shader text files. The APK also
  contains directories the source tree does not ship raw (`font/`, `audio/`) because
  upstream's CMake copies them from `static-assets/`.
* Version 17 matches upstream's `set(project_version 17)`; `HEAD` already says 18.
* Same package id, same label, same 93 animations, same 25 style sources.

**Conclusion: port the source at version 17, not the binary.**

---

## 6. Port surface — what iOS actually needs

Source size by module (files / lines, `.cpp/.h/.hpp`):

| module | files | lines |
|---|---|---|
| `modules/bim/game` (simulation, boards, players, features) | 257 | 15,832 |
| `modules/bim/server` (authoritative server; **not needed in the app**) | 76 | 10,965 |
| `modules/bim/net` (asio transport, message codec) | 58 | 3,092 |
| `modules/axmol` (engine-side rendering of the game) | 231 | 12,252 |
| `apps/axmol/main` (screens: lobby, shop, matchmaking, online-game, popups) | 68 | 10,994 |
| `modules/bim/core` (config, feature flags) | 13 | 665 |
| `modules/bim/app/android` (platform layer) | 6 | **267** |
| `modules/bim/app/desktop` (platform layer) | 6 | **232** |

Two facts decide the whole strategy:

1. The **platform layer is ~250 lines** — shop/analytics/vibration/asset hooks behind
   interfaces. Android's is 267 lines; a desktop one already exists at 232 lines.
2. In the entire client, only **three files** contain `__ANDROID__`/`ANDROID_NDK`:
   `apps/axmol/main/src/bim/axmol/app/application{,_event_dispatcher}.cpp` and
   `modules/axmol/display/main/src/bim/axmol/display/main_view.cpp`.

Axmol has an iOS backend upstream; the project is CMake (`CMakeLists.txt` +
`CMakeLists-common.txt` + `CMakeLists-android.txt`) with `apps/axmol` as the app target.

So the port is: **add the missing iOS platform layer and build the same game for iOS** —
not a reimplementation. Expected new code: an `app/ios` platform implementation (~250
lines mirroring `app/desktop`), an iOS app target/CMake wiring, Info.plist/asset catalog,
and touch-control parity (the D-pad and stick already exist in the style data).

### Verification path (this is what makes the port testable)

* `apps/bot-test` and `apps/player` are headless clients in-tree; upstream's CI runs
  `ci/run-test-programs.sh` and `ci/run-server-crash-test.sh`, so a **local server** can be
  started and the iOS client pointed at it. That gives end-to-end verification of
  authenticate → matchmaking → match → win/lose without touching production.
* Production `bim-prod.jorge.st` is reachable and is what real users play on.

### Risks

| risk | note |
|---|---|
| Axmol has never been built for iOS *in this fork* | highest technical risk; needs an iOS build of axmol 2.11.5.0j (setup recipe only covers android/linux today) |
| Dependency build time | axmol + boost + curl + freetype… — tens of minutes to hours on first build |
| AGPL-3.0 | the app may be built and shared, but the source must be offered with it; the name/art stay the author's (attribution, no relicensing) |
| No signing identity | unsigned IPA, SideStore/LiveContainer, exactly as with the previous ports |

---

## 7. Plan

1. **Pin the tree**: clone `j-jorge/bim`, check out `f3e0e72a` (version 17), keep it as
   `analysis/upstream/` (gitignored) exactly as the weather ports did.
2. **Build the axmol app for desktop macOS first** (same sources, a platform layer already
   exists) — this proves the tree builds on this machine and gives a running reference
   without waiting for the engine's iOS backend.
3. **Add `modules/bim/app/ios`** (shop/analytics/vibration/asset hooks) + `apps/ios` target
   wired into the existing CMake, Info.plist, launch storyboard, app icon from
   `metadata/en-US/images/icon.png`.
4. **Build axmol 2.11.5.0j for iOS** (device + simulator), then the app; fix compile and
   platform issues as they appear.
5. **Verify**: launch on the simulator, screenshots of every screen, then a real match
   against a locally-run upstream server with `apps/bot-test` as opponents; check the
   animation timings of §3.2 on screen (360 ms walk, 330 ms flame).
6. **Package**: unsigned IPA + CI workflow + docs, exactly like `weather-ios-port` and
   `gust`.

Estimate: step 2 ≈ 30–60 min, step 4 ≈ 60–180 min (dominated by engine compilation), steps
5–6 ≈ 60 min.

---

## 8. What this REA deliberately did not do

* Did not attempt to patch or repackage the APK: the native library is stripped and ABI-,
  not source-, portable.
* Did not reverse the network protocol by hand: the source is available, which is strictly
  better.
* Did not read the server's tunables (`/client/config` answers 403): they arrive at run
  time and the client already knows how to consume them.
* Did not port a single line of Swift. A Swift reimplementation is *possible* but is the
  worse option: it would replace 46,685 audited C++ lines with guesses about balance,
  blast propagation, feature interaction and netcode, and it could never play online.

---

## 9. Commands used

```bash
# inventory
unzip -l ~/Downloads/bim-17.apk
apktool d ~/Downloads/bim-17.apk -o analysis/apktool -f
grep -E "versionName|versionCode" analysis/apktool/apktool.yml
# engine and network facts
strings -a lib/arm64-v8a/libbim.so | grep -i "axmol"
strings -a lib/arm64-v8a/libbim.so | grep -oE "https?://[a-zA-Z0-9./_-]{6,60}" | sort -u
nm -g lib/arm64-v8a/libbim.so | wc -l
# assets
python3  # plistlib over sprite-sheet-{1,2,3}.plist -> frame groups and sizes
python3  # json over animations.json    -> 93 animations, durations
python3  # json over style/application.json -> 446 style keys
python3  # struct over i18n/en.mo       -> 90 messages
# upstream correspondence
git clone https://github.com/j-jorge/bim
diff -rq assets analysis/apktool/assets | grep -c differ          # 17
git log --oneline -S"set(project_version 17)" -- CMakeLists.txt   # f3e0e72a
grep -rl "__ANDROID__" apps/axmol/main modules --include=*.cpp    # 3 files
```