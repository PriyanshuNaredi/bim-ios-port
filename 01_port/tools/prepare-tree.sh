#!/bin/bash
# Prepare an iOS build tree from the pinned upstream + this port's overlay.
#
# The upstream tree stays pristine in analysis/upstream (checked out at the version-17
# commit). Everything the port changes is either a new file in overlay/ or a small,
# explicit edit applied here, so `git diff` against the upstream pin always shows exactly
# what the port adds.
#
# Usage: 01_port/tools/prepare-tree.sh [build-dir]      (default: build/ios-src)

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
port_root="$(cd "$script_dir/.." && pwd)"
repo_root="$(cd "$port_root/.." && pwd)"
upstream="$repo_root/analysis/upstream"
target="${1:-$repo_root/build/ios-src}"

if [[ ! -d "$upstream" ]]; then
  echo "Missing $upstream. Clone j-jorge/bim there at the version-17 commit." >&2
  exit 1
fi

echo "==> tree: $target"
rm -rf "$target"
mkdir -p "$target"

# The analysis clone carries our own notes; only the sources are needed.
# The APK is version 17 but built from the *end* of the version-17 line, after the
# "Bump version to 17" tag: its style data contains the player profile button and the
# nickname editor, which landed on master 73 commits after the tag. The last commit
# whose version is still 17 is the one this port must follow.
pin="${BIM_PIN:-cfa6d5a5f66b0465e5d77a435515450947e16a9f}"

git -C "$upstream" archive --format=tar "$pin" | tar -x -C "$target"

echo "==> overlay"
cp -R "$port_root/overlay/." "$target/"

echo "==> patches"
python3 - "$target" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])


def edit(relative, old, new, description):
    path = root / relative
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"patch point not found in {relative}: {description}")
    path.write_text(text.replace(old, new, 1))


# 1. The platform layer: iOS reuses the desktop implementations (mock shop, logging
#    analytics) and overrides is_shop_supported() to false, because no StoreKit path is
#    wired.
edit(
    "modules/bim/app/CMakeLists.txt",
    """else()
  set(platform_sources
    desktop/src/bim/app/analytics_service.cpp
    desktop/src/bim/app/shop_implementation.cpp
    desktop/src/bim/app/shop_support.cpp
  )
  set(platform_includes desktop/include)
endif()""",
    """elseif(BIM_BUILDING_FOR_IOS)
  set(platform_sources
    desktop/src/bim/app/analytics_service.cpp
    desktop/src/bim/app/shop_implementation.cpp
    ios/src/bim/app/shop_support.cpp
  )
  set(platform_includes desktop/include)
else()
  set(platform_sources
    desktop/src/bim/app/analytics_service.cpp
    desktop/src/bim/app/shop_implementation.cpp
    desktop/src/bim/app/shop_support.cpp
  )
  set(platform_includes desktop/include)
endif()""",
    "iOS platform branch",
)

# 2. Apps: only the iOS app, and not the CLI programs (linux/player/bot-test/server) that
#    need boost::program_options and a terminal.
edit(
    "apps/CMakeLists.txt",
    """else()
  add_subdirectory(bot-test)
  add_subdirectory(linux)
  add_subdirectory(player)
  add_subdirectory(server)
endif()""",
    """elseif(BIM_BUILDING_FOR_IOS)
  add_subdirectory(ios)
else()
  add_subdirectory(bot-test)
  add_subdirectory(linux)
  add_subdirectory(player)
  add_subdirectory(server)
endif()""",
    "iOS app target",
)

# 3. Assets: the generated assets need host tools (style-merger, pack-my-sprites,
#    ImageMagick) that only upstream's setup installs. The port ships the *shipped*
#    assets instead: the ones inside bim-17.apk, which are the output of that pipeline.
edit(
    "CMakeLists-common.txt",
    """add_subdirectory(apps)

add_subdirectory(assets)""",
    """add_subdirectory(apps)

# The iOS port takes the prebuilt asset directory from the APK (see ASSETS.md) instead of
# regenerating it, so the host-only asset tools are not needed.
if(NOT BIM_BUILDING_FOR_IOS)
  add_subdirectory(assets)
endif()""",
    "prebuilt assets",
)

# 4. The server is a separate program with its own dependencies (maxminddb, ROCm-free
#    maths, …); the app does not need it.
edit(
    "modules/CMakeLists.txt",
    "add_subdirectory(bim/server)",
    """if(NOT BIM_BUILDING_FOR_IOS)
  add_subdirectory(bim/server)
endif()""",
    "server out of the app build",
)

# 5. The render view: on iOS axmol's AxmolAppController has already created it and handed
#    it to the director before the game exists, and the desktop header (GLFW) does not
#    compile for iOS at all. So the iOS version only sets the design resolution.
edit(
    "modules/axmol/display/main/src/bim/axmol/display/main_view.cpp",
    """#ifdef __ANDROID__
  #include <axmol/platform/android/RenderViewImpl-android.h>
#else
  #include <axmol/platform/RenderViewImpl.h>
#endif""",
    """#ifdef __ANDROID__
  #include <axmol/platform/android/RenderViewImpl-android.h>
#elif defined(__APPLE__)
  #include <TargetConditionals.h>
  #if TARGET_OS_IPHONE
    #include <axmol/platform/ios/RenderViewImpl-ios.h>
  #else
    #include <axmol/platform/RenderViewImpl.h>
  #endif
#else
  #include <axmol/platform/RenderViewImpl.h>
#endif""",
    "iOS render view header",
)

edit(
    "modules/axmol/display/main/src/bim/axmol/display/main_view.cpp",
    """  ax::RenderView* view = director->getRenderView();

  if (view != nullptr)
    return;""",
    """  ax::RenderView* view = director->getRenderView();

#if defined(__APPLE__) && TARGET_OS_IPHONE
  // axmol creates the iOS render view in AxmolAppController before the game is
  // constructed, so there is never one to create here.
  if (view != nullptr)
    {
      view->setDesignResolutionSize(size.width, size.height,
                                    ResolutionPolicy::SHOW_ALL);
      return;
    }
#endif

  if (view != nullptr)
    return;""",
    "iOS render view body",
)

# 7. Json::Value has separate assignment overloads for `unsigned int` and for
#    `unsigned long long`. On Darwin `std::size_t` is `unsigned long`, so assigning one is
#    ambiguous there and nowhere else (Linux defines uint64_t as `unsigned long`, which
#    makes the same line an exact match). Upstream's CI is Linux, which is why upstream
#    never sees it.
for relative in (
    "modules/bim/app/main/src/bim/app/job/assign_feature_slots_job.cpp",
    "modules/bim/app/main/src/bim/app/job/buy_feature_slot_job.cpp",
):
    path = root / relative
    text = path.read_text()
    if '["slot_index"] = i;' not in text:
        raise SystemExit(f"patch point not found in {relative}: json slot_index")
    path.write_text(text.replace('["slot_index"] = i;',
                                 '["slot_index"] = Json::UInt64(i);'))


# 8. A test seam for hosts that cannot send touches. The iOS simulator has no input API and
#    this machine has no Accessibility permission for synthetic clicks, so there is no way
#    to press PLAY ONLINE from outside the app. With BIM_AUTOPLAY=1 in the environment the
#    lobby presses it for us three seconds after being built. Inert unless the variable is
#    set, which makes it usable as a UI-test entry point without shipping a behaviour.
edit(
    "apps/axmol/main/src/bim/axmol/app/screen/lobby.cpp",
    """  m_inputs.push_back(m_controls->play_button->input_node());""",
    """  if (std::getenv("BIM_AUTOPLAY") != nullptr)
    ax::Director::getInstance()->getScheduler()->schedule(
        [this](float) { play_online(); }, this, 0.f, 0, 3.f, false,
        "port-autoplay");

  // BIM_AUTOPRESS opens one of the lobby's popups, which no host can click either.
  {
    const char* press = std::getenv("BIM_AUTOPRESS");

    if (press != nullptr)
      {
        const std::string which(press);

        ax::Director::getInstance()->getScheduler()->schedule(
            [this, which](float)
            {
              if (which == "shop")
                open_shop_from_button();
              else if (which == "settings")
                show_settings();
              else if (which == "stats")
                open_player_stats();
              else if (which == "nickname")
                open_nickname_editor();
            },
            this, 0.f, 0, 4.f, false, "port-autopress");
      }
  }

  m_inputs.push_back(m_controls->play_button->input_node());""",
    "autopress seam",
)

# The seams need a scheduler and getenv, which the screens do not otherwise include.
edit(
    "apps/axmol/main/src/bim/axmol/app/screen/lobby.cpp",
    "#include <axmol/2d/Label.h>",
    """#include <axmol/2d/Label.h>
#include <axmol/base/Director.h>
#include <axmol/base/Scheduler.h>

#include <cstdlib>""",
    "lobby seam includes",
)

print("   applied 13 edits")
PY

echo "==> done"

