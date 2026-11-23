# Credits and licences

This is an **unofficial iOS port** of **Bim!**, a game by **Jorge Jiménez** (`j-jorge`). It is
not published by the author, and nothing here should be read as his endorsement. The code is
the upstream code, compiled for iOS with the additions recorded in `01_port/`.

## Upstream

| Project | Author | Licence | Used for |
| --- | --- | --- | --- |
| [Bim!](https://github.com/j-jorge/bim) `cfa6d5a5` | Jorge Jiménez | AGPL-3.0 | the entire game: `modules/bim`, the axmol app, the UI style data, the art and the audio |
| [Axmol](https://github.com/axmolengine/axmol) `2.11.2.3j` | Axmol Engine contributors | MIT | the engine (`libaxmol.a`, Metal shaders) |
| [IsCool Core](https://github.com/j-jorge/iscool-core) `1.31.2` | Jorge Jiménez | Apache-2.0 | platform services, audio, networking, JSON, logging |
| [Boost](https://www.boost.org) `1.91.0` | Boost contributors | BSL-1.0 | `asio`, `signals2`, `iostreams` and friends |
| [jsoncpp](https://github.com/open-source-parsers/jsoncpp) `1.9.6` | open-source-parsers | MIT | wire format |
| [EnTT](https://github.com/skypjack/entt) `3.16.0` | Michele Caini | MIT | the game's ECS |
| [moFileReader](https://github.com/0xphk/moFileReader) `1.2` | Peter Kollmann | MIT | the gettext catalogues |
| [libfpm](https://github.com/MikeLankamp/fpm) `1.1.1` | Mike Lankamp | MIT | fixed-point arithmetic in the physics |
| [freetype](https://freetype.org) | The FreeType Project | FTL | bundled with axmol |

The engine's Metal shaders are compiled from axmol's own shader sources; the APK ships only
GLES bytecode, so `runtime/axslc` from the engine build travels in the bundle.

## What the port adds

`01_port/overlay/` and `01_port/patches/` contain the only code that is not upstream's:

* `apps/ios/` — the iOS entry point (`main.mm`), the app delegate, `Info.plist`, the launch
  storyboard and the CMake target.
* an iOS branch for the shop, which has no StoreKit implementation, so the lobby shows the
  upstream "not available on this platform" dialog with the donation link;
* an iOS implementation of `iscool::system::haptic_feedback` on top of
  `UIImpactFeedbackGenerator`;
* an `iscool::system::open_url` implementation for iOS, and a `std::size_t` cast fix in
  `iscool::json` that Darwin's `unsigned long long` needs;
* test seams (`BIM_AUTOPLAY`, `BIM_AUTOFIGHT`, `BIM_AUTORETURN`, `BIM_AUTOPRESS`) documented
  in `01_port/TEST_SEAMS.md`.

## Licence of this repository

Because Bim! is AGPL-3.0, this port is AGPL-3.0 as well: see `LICENSE`. If you distribute a
binary built from this tree, you must make the complete corresponding source available,
including the port additions above. The upstream `LICENSE_ADDITIONAL`-style restrictions of
other projects do not apply here, but the authorship of the game itself does: it is Jorge
Jiménez's work, and this repository only carries it to another platform.

Assets (sprites, animations, audio, translation catalogues) come from the APK of the upstream
release and remain under the same AGPL-3.0.
