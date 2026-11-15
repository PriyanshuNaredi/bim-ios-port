# Bim! for iOS

An iOS port of [Bim!](https://github.com/j-jorge/bim) — an open-source (AGPL-3.0)
multiplayer online game of the last-man-standing genre — built from the upstream C++
source at version 17, the version shipped as `bim-17.apk`.

The Android artefact is a build of the public source tree (see
[`00_recon/REA.md`](00_recon/REA.md)), so this port reuses the game itself, the
Axmol engine it is written against, and all artwork and text, rather than
reimplementing them. Only the platform layer and the app packaging are new.

## Licence and credits

* Game, artwork, text: **Bim! by J. Jorge** — AGPL-3.0, © the Bim! authors. This port is
  a derivative work under the same licence and ships with the same licence text.
* Engine: **Axmol** `2.11.5.0j` (the `j-jorge` fork the upstream pins).
* Upstream: <https://github.com/j-jorge/bim> · Discord/donations links belong to the
  author and are untouched.

If you were redirected here looking for the game itself, install **Bim!** from your
store, or build it from upstream — this repository only adds the iOS target.

## State

| stage | status |
|---|---|
| REA of `bim-17.apk` | done — `00_recon/REA.md` |
| Upstream tree pinned at version 17 | done — `analysis/upstream` @ `f3e0e72a` |
| Desktop build that proves the tree compiles here | pending |
| `modules/bim/app/ios` platform layer | pending |
| Axmol `2.11.5.0j` built for iOS | pending |
| iOS app + verification match | pending |
| Unsigned IPA + CI | pending |
