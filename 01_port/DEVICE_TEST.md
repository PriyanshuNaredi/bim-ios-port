# Running Bim! on a phone

Everything below the hardware line is done and checked: the game builds for arm64, the bundle is
complete, and the simulator runs it against the production server. The line itself is signing.
This Mac has no Apple ID configured and no signing identity, and nothing in the port may touch
Apple's services on your behalf, so the last step is yours and takes about five minutes.

## 1. Put the unsigned IPA on the phone

The artefact is `04_release/Bim-unsigned.ipa` (arm64, iOS 17+, portrait, no
`_CodeSignature`, no `mobileprovision`). It cannot be installed by Xcode or by `ios-deploy`;
iOS refuses to launch unsigned code. Two tools install and re-sign it *on the device* with your
own Apple ID, which is why they work without a Mac in the loop:

* **SideStore** — <https://sidestore.io/> — the friendlier of the two. Pair once with your
  Apple ID in its settings, then "Install IPA" → pick the file. Free Apple IDs get a 7-day
  provisioning profile that SideStore renews for you in the background.
* **LiveContainer** — <https://github.com/LiveContainer/LiveContainer> — if you would rather not
  let a store manage a profile. It hosts the app inside its own signed container.

Both need the IPA copied to the phone (AirDrop, iCloud Drive, Files).

## 2. What to look at, in order

The order matters: each line exercises a path the simulator cannot.

| # | Do this | Expect | If not |
|---|---|---|---|
| 1 | Launch | Lobby, full screen, no letterboxing, no black bands; "user_NNNN" nickname appears within ~3 s | Bands → the Info.plist lost `UILaunchStoryboardName`; see `BUILD.md`, it is a launch-screen problem, not a renderer one |
| 2 | Look at the top row | Wallet and gear sit clear of the notch/Dynamic Island | On a notched phone the gear sits lower than in the simulator, never higher: the port assumes the 59 pt iPhone 16 safe top |
| 3 | Listen | Menu music. It is the same `audio/menu.ogg` the APK ships | Tell me — the simulator can only prove that OpenAL created a source, not that you hear it |
| 4 | Gear → Music off, then on | Music stops and restarts immediately | Preference is `music.enabled`; the state is applied in `application::apply_local_preferences` |
| 5 | Gear → Vibrations off/on, then tap a button | Haptic tap when on. This is `UIImpactFeedbackGenerator`, added by patch `0004` | Two simulators have no haptics at all; a phone is the only place this can fail |
| 6 | FIGHT | Matchmaking finds a live opponent; the arena appears with a running clock | The lobby is talking to `https://bim-prod.jorge.st`; a failure here is a network or TLS problem, and `Documents/log.txt` in the container says which |
| 7 | Play a full match | Crates, bombs, kings, the clock counting down, then a result screen and coins | |
| 8 | Statistics | Counters increase | |
| 9 | Rotate the phone | Nothing rotates: portrait only, matching `screenOrientation="portrait"` in the Android manifest | |
| 10 | Shop | Upstream's own "not available on this platform" dialog, with the donation link | This is deliberate: the server validates Google Play purchase tokens, so there is nothing an iOS client could send it |

## 3. If something looks wrong

* Screenshots are the fastest signal. A full-screen capture (not a crop) shows layout, safe area
  and whether the artwork is letterboxed, all at once.
* The app writes a plain-text log to its own container, `Documents/log.txt`; `iscool`'s `ic_log`
  is currently unusable (it prints literal `[{}][{}]` placeholders), so the useful lines are the
  `fprintf`-style ones the port adds.
* Performance on real hardware is unmeasured. The game is a 2D tile arena on Metal, and the
  simulator is software-rendered, so if the phone is slow the problem is somewhere else.

## 4. What "done" would mean

A phone run that reaches an arena, plays to a result, and produces sound is the last unverified
claim in `README.md`. Everything else in that table has been run, and there is evidence for it in
`03_evidence/`.
