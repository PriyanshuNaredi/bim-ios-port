# Building Bim! for iOS

Status: the iOS build links, installs on the simulator and reaches the lobby, signed in
to the production server and drawn from the APK's own assets. This page records the exact steps and
every deviation the port had to make in or around the upstream tree.

## One command

```bash
01_port/tools/build-all.sh          # engine + dependencies into build/prefix-<arch>
01_port/tools/build-app.sh          # prepare tree, configure, build Bim.app
```

`ARCHS` defaults to `uname -m`. On this Hackintosh that is `x86_64`, which is also the
simulator runtime that exists here; an arm64 simulator binary installs with "Needs to Be
Updated". Set `ARCHS=arm64` on an Apple Silicon host (or `arm64` device builds).

`JOBS` defaults to 4. Building with every core has twice taken this machine down in a
kernel spinlock timeout, so the scripts leave headroom on purpose.

## Where things go

| Path | Contents |
| --- | --- |
| `analysis/axmol-v17` | axmol at the version 17 pin (`v2.11.2.3j`) |
| `analysis/iscool-core` | dependency at branch `1.31.2` |
| `build/axmol-ios-<arch>` | engine build tree (`lib/libaxmol.a`, `soft_oal.framework`) |
| `build/prefix-<arch>` | iOS install prefix: jsoncpp, entt, moFileReader, iscool-core, CMake package files |
| `build/ios-src` | prepared upstream tree: upstream + `01_port/overlay` + the edits below |
| `build/bim-ios-<arch>` | Bim!'s build tree; `apps/ios/Bim.app` is the product |

Nothing is built in `/tmp`: a kernel panic wipes it, and this machine panics.

## Dependency steps

1. **axmol** — configured with axmol's own `1k/ios.cmake` toolchain, `PLAT=iOS`,
   `SIMULATOR=TRUE`, `AXSLCC_EXE` pinned to the prebuilt shader compiler. Its
   `soft_oal.framework` and the `3rdparty/*/_x/lib/*/*simulator/*.a` archives are what the
   app links.
2. **boost 1.91.0** — headers only (asio is header-only and that is all Bim! uses).
3. **jsoncpp 1.9.6, entt 3.16.0, moFileReader 1.2, iscool-core 1.31.2** — cross-built for
   the simulator. `IOS_SDK_VERSION` must be passed to iscool-core, otherwise its CMake
   silently picks the no-platform branches and produces a library with no iOS code in it.
4. **CMake package files** — upstream's `setup/dependencies/recipes` generate
   `axmol-config.cmake`, `fmt-config.cmake` and friends, but only for Linux and Android. The
   port writes the same packages for iOS: one `axmol::axmol` INTERFACE target with the
   engine archives, third-party archives, OpenAL Soft and the system frameworks; `fmt` from
   the copy the engine already built; a headers-only `Boost` that reports
   `Boost_FOUND FALSE` when components are requested, so `iscool-locale` takes its
   "no Boost.Locale" branch instead of hunting for ICU.

## Edits to the upstream tree (`01_port/tools/prepare-tree.sh`)

| # | File | Why |
| --- | --- | --- |
| 1 | `modules/bim/app/CMakeLists.txt` | iOS platform branch: desktop analytics/shop, `ios/src/bim/app/shop_support.cpp` |
| 2 | `apps/CMakeLists.txt` | build `apps/ios` instead of the CLI programs |
| 3 | `CMakeLists-common.txt` | skip `add_subdirectory(assets)`: the asset pipeline needs host tools, the port ships the assets from the APK |
| 4 | `modules/CMakeLists.txt` | the server program is not part of an app |
| 5 | `modules/axmol/display/.../main_view.cpp` | iOS render view already exists (axmol creates it); the desktop header is GLFW and does not compile for iOS |
| 6 | as above | the body: set the design resolution on the existing view |

Plus one compiler-level fix: `-include cstddef -include cstdint -include span`. Upstream is
written against libstdc++, where those headers arrive transitively; libc++ does not.

## The port's own files (`01_port/overlay`)

| File | Purpose |
| --- | --- |
| `apps/ios/main.mm` | creates the Bim! application before `UIApplicationMain` |
| `apps/ios/GameAppController.{h,mm}` | axmol's controller does everything already |
| `apps/ios/Info.plist` | bundle `bim.app`, display name `Bim!`, version 17 / 1700 |
| `apps/ios/LaunchScreen.storyboard` | black launch screen |
| `apps/ios/CMakeLists.txt` | `Bim.app`, assets and OpenAL framework copying |
| `apps/ios/.../shop_support.cpp` | `is_shop_supported() == false`: no StoreKit yet, so upstream's own "shop not available on this platform" message shows |

## Dependency patches (`01_port/patches/iscool-core/*.patch.py`)

iscool-core 1.25.1's iOS branches have never been compiled. Two are broken:

1. `ios/language_name.mm` returns `std::string` while the header returns
   `iscool::language_name` — a translation unit that cannot compile.
2. The iOS file list omits `open_url.cpp` entirely, so `iscool::system::open_url` is
   undefined at link time. The patch adds `ios/open_url.mm` (UIApplication) and registers
   it.

Both patches are idempotent and run from `build-all.sh`.

## What this does not do yet

- No StoreKit: the shop hides itself.
- Online play is untested: it needs an upstream server (`apps/server`) and the
  `bim-prod.jorge.st` smoke test has not been run.
- Audio has not been heard, only linked.
- No device build: it needs a signing identity, which this machine does not have.

## Four things the port had to add to run at all

Each one is a real defect that only shows up off the upstream build farm, in the order they
appeared while getting the first frame onto the screen.

1. **The bundle needs the engine's shaders.** The APK ships one custom shader
   (`assets/shaders/shine_fs`); the other 55 are compiled into the app by axmol's build.
   Without them the first draw ends in `MTLReportFailure` from
   `validateWithDevice`. `apps/ios/CMakeLists.txt` copies
   `build/axmol-ios-<arch>/runtime/axslc` into `Bim.app/assets`, where it overwrites the
   APK's GLES versions name for name.

2. **Consumers must compile with the engine's own switches.** `axmol-config.cmake` now
   carries every `-DAX_*` the engine was built with (`AX_ENABLE_PHYSICS`, `AX_ENABLE_3D`,
   ...). They are not cosmetic: `Node` gains a `_physicsBody` member under
   `AX_ENABLE_PHYSICS`, so a consumer compiled without it reads the engine's objects at the
   wrong offsets and sees members that are silently null. The symptom was
   `apply_size()` dereferencing a null `reference` — a node whose parent the engine had
   set, read back as `nullptr`.

3. **`iscool::json` has no `std::size_t` cast on Darwin.** Upstream is Linux, where
   `uint64_t` *is* `unsigned long`; on Darwin it is `unsigned long long`, so
   `cast<std::size_t>` and `Json::Value::operator=(std::size_t)` resolve to nothing and the
   link fails. `patches/iscool-core/0003-json-cast-size-t.patch.py` adds the missing cast,
   and `prepare-tree.sh` casts the three `"slot_index" = i` assignments in the two feature
   slot jobs.

4. **The build must be a production build.** Without `-DBIM_PROD_BUILD=ON` the binary
   points at `http://localhost:4210` and shows "Failed to authenticate with the business
   server. Status -1." `build-app.sh` sets `BIM_PROD_BUILD=ON` and pins
   `BIM_BUSINESS_SERVER_URL=https://bim-prod.jorge.st` (it is a cache variable, so leaving
   it to the default keeps the old value in `CMakeCache.txt`).

## What is verified, and how

* `Bim.app` installs and launches on the iPhone 16 simulator (iOS 18, x86_64).
* The lobby renders from the APK's `style/application.json`: coin counter, gear, alpha
  banner, shop and statistics buttons, the profile card, the feature deck and PLAY ONLINE,
  with "24 games played in the last hour" fetched from the server.
* Authentication against `https://bim-prod.jorge.st` succeeds and returns a nickname
  (`user_1097` in the run recorded in `07_logs/sim-11.png`).

Not yet verified: a match in progress (the header needs a tap, see below), audio, the
shop (disabled on iOS: `is_shop_supported()` is false), and anything on a physical device.

## Next: play a match

The simulator has no input API, so the tap has to come from the host:

```bash
open -a Simulator                       # the app is already installed
# click PLAY ONLINE, then the game board should appear
```

A local server (`apps/server` from the upstream tree) is the repeatable alternative, but it
is a Linux/desktop program: it needs boost::program_options and a terminal, which is why
prepare-tree.sh leaves it out of the iOS build.
