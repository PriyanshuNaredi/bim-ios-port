# Decisions

**D1 — Port the source, not the binary.** `libbim.so` is stripped (`nm -g` = 0 symbols),
has no script bundle, and its only embedded logic is C++ shared across three ABIs. The
upstream is AGPL-3.0 and version 17 of the APK matches commit `f3e0e72a`. Porting the
source keeps gameplay, balance, netcode and artwork exactly as shipped.

*Rejected: clean-room Swift/SpriteKit reimplementation.* It would replace 46,685 audited
C++ lines with inferred rules, could never play online against the real server, and would
still need every asset extracted from the APK.

*Rejected: patching or repackaging the APK.* Native code cannot be re-targeted to arm64
iOS.

**D2 — Pin version 17, not `HEAD`.** Upstream `HEAD` is already version 18; the artefact to
be matched is `versionName 17`. `analysis/upstream` is checked out at `f3e0e72a`.

**D3 — Desktop build before iOS build.** The source already ships a desktop platform
layer (232 lines) and axmol builds on macOS. Proving the tree compiles and runs natively
first separates "the tree is fine" from "the iOS engine build is broken", which are very
different debugging problems.

**D4 — Verify with a local server, not production.** Upstream ships the authoritative
server and two headless clients (`apps/bot-test`, `apps/player`), and its CI runs them.
Matches are verified against a server started on this machine; `bim-prod.jorge.st` is
only used for one smoke test of the real path.

**D5 — No reimplementation of the UI.** The APK's 337 KB `style/application.json` is a
*merge* of 25 style files that the source keeps separate and that a `style-merger` tool
combines at build time. The port uses the sources.
