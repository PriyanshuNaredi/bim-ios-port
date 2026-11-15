# Port plan — Bim! 17 on iOS

Ground truth: [`00_recon/REA.md`](../00_recon/REA.md). The target is the upstream C++ game
at version 17 (`analysis/upstream` @ `f3e0e72a`) built for iOS with the same Axmol fork the
upstream pins (`v2.11.2.1j`, per `setup/dependencies/recipes/10-axmol.sh` at that commit —
**not** `v2.11.5.0j`, which is what `HEAD` pins).

## Stages

| # | stage | state |
|---|---|---|
| 0 | REA of the APK | done |
| 1 | Pin upstream v17 + the exact dependency versions it names | done |
| 2 | **Axmol `v2.11.2.1j` built for the iOS simulator** | building |
| 3 | Cross-build bim's dependencies for iOS (the real long pole) | next |
| 4 | `modules/bim/app/ios` platform layer (~250 lines, mostly copied from `app/desktop`) | next |
| 5 | `apps/ios` target: `main.mm` + `AppDelegate` + Info.plist + asset bundle | next |
| 6 | Build `Bim.app` for the simulator, then device | |
| 7 | Verify: screens, then a real match against a locally-hosted upstream server + `apps/bot-test` | |
| 8 | Unsigned IPA + CI + docs, as with `weather-ios-port` and `gust` | |

## Stage 3 — the dependency chain

The client's `CMakeLists-common.txt` needs these, none of which an iOS build can borrow
from Homebrew (macOS libraries cannot link into an iOS app):

| package | version pinned by upstream | iOS difficulty |
|---|---|---|
| Axmol | `2.11.2.1j` (fork) | **done** for the simulator; device build still to do |
| Boost | `1.89.0` | header-only usage (asio, beast, container, signals) → no compiled libs needed |
| EnTT | `3.16.0` | header-only |
| fmt | (pulled by axmol/iscool) | header + one small .cc; axmol already ships a built `libfmt.a` |
| jsoncpp | `1.9.6` | CMake, cross-compiles cleanly |
| mofilereader | `1.2` | tiny, C++ |
| iscool-core | `1.25.1` (**branch**, not a tag) | 8 components |
| curl | (recipe `20-curl.sh`) | hardest; needed by `iscool/http` |

`iscool-core` components the client pulls: `audio http i18n net preferences random style
system`. Each may need its own dependency (http → curl; i18n → mofilereader; style →
jsoncpp; system → cpptrace/libunwind on Linux, likely optional on iOS).

Strategy: build each into a shared iOS prefix and install a `*-config.cmake` there, so the
bim configure only needs `CMAKE_FIND_ROOT_PATH` pointed at it:

```bash
TOOLCHAIN=analysis/axmol-v17/1k/ios.cmake
cmake -S <pkg> -B /tmp/ios-build/<pkg> -G Xcode \
      -DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN -DPLAT=iOS -DARCHS=arm64 -DSIMULATOR=TRUE \
      -DCMAKE_INSTALL_PREFIX=/tmp/ios-prefix -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/ios-build/<pkg> --config Release --target install
```

## Stage 4 — the platform layer

`modules/bim/app/CMakeLists.txt` selects sources by platform:

```cmake
if (BIM_BUILDING_FOR_ANDROID)   # android/src/...: analytics, shop_service, shop_support
else()                          # desktop/src/...: the same three files, mock implementations
```

iOS adds a third branch that reuses the desktop implementations (mock shop, logging
analytics) but overrides `is_shop_supported()` to `false`, because no StoreKit purchase
path is wired: the app then hides the shop and shows the existing "shop is not available on
this platform" message instead of offering purchases that cannot complete.

## Stage 5 — the app target

Axmol's iOS template is `UIApplicationMain(…, @"GameAppController")` with an
`AxmolAppController` subclass; bim's own entry (`apps/linux/main.cpp`) constructs
`bim::axmol::app::application(asset_directories, size, scale, debug, script_info)` and calls
`axmol::Application::getInstance()->run()`. The iOS target does the same from
`application:didFinishLaunchingWithOptions:`, with the asset directory taken from the app
bundle (`[NSBundle mainBundle].resourcePath`), no CLI parsing, and `main.mm` replacing
`main()`.

## Verification (stage 7)

Upstream ships the authoritative server and two headless clients, and its CI runs them
(`ci/run-test-programs.sh`, `ci/run-server-crash-test.sh`). A match can therefore be
verified end to end on this machine:

1. start `apps/server` locally,
2. point the iOS app at it (the business URL is a build-time template,
   `modules/bim/business/business_url.hpp.in`),
3. let `apps/bot-test` join and play,
4. check the animations against the measured timings in `REA.md` §3.2 (walk 360 ms, flame
   330 ms, crate 270 ms).