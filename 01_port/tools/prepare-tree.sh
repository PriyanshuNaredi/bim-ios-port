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

# A fresh clone has no analysis/ directory at all; fetch the pinned sources and the APK's
# prebuilt assets instead of failing with an instruction to go and do it by hand.
if [[ ! -d "$upstream" || ! -d "$repo_root/analysis/apktool/assets" ]]; then
  "$script_dir/fetch-sources.sh"
fi

if [[ ! -d "$upstream" ]]; then
  echo "Missing $upstream even after fetch-sources.sh." >&2
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
    """#if BIM_TEST_SEAMS
  if (std::getenv("BIM_AUTOPLAY") != nullptr)
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
              else if (which == "features")
                open_game_features();
              else if (which == "language")
                show_settings();
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


# 9. Accept the match proposal without a tap. The FIGHT button calls accept_game(); the seam
#    does the same thing on the same signal, one second after an opponent arrives.
edit(
    "apps/axmol/main/src/bim/axmol/app/screen/matchmaking.cpp",
    """  m_controls->ready_button->connect_to_clicked(
      [this]()
        {
          accept_game();
        });""",
    """  m_controls->ready_button->connect_to_clicked(
      [this]()
        {
          accept_game();
        });

#if BIM_TEST_SEAMS
  if (std::getenv("BIM_AUTOFIGHT") != nullptr)
    ax::Director::getInstance()->getScheduler()->schedule(
        [this](float) { accept_game(); }, this, 0.f, 0, 1.f, false,
        "port-autofight");
#endif""",
    "matchmaking seam",
)

edit(
    "apps/axmol/main/src/bim/axmol/app/screen/matchmaking.cpp",
    """#include <bim/axmol/app/screen/matchmaking.hpp>""",
    """#include <bim/axmol/app/screen/matchmaking.hpp>

#include <axmol/base/Director.h>
#include <axmol/base/Scheduler.h>

#include <cstdlib>""",
    "matchmaking seam includes",
)

# 10. Take the "new game" path without a tap. Scheduled from displayed(), because the screen is
#     constructed while the match is still running; a constructor-time schedule presses NEW GAME
#     before a result exists and leaves a blank arena (see 01_port/TEST_SEAMS.md).
edit(
    "apps/axmol/main/src/bim/axmol/app/screen/end_game.cpp",
    """void bim::axmol::app::end_game::displayed()
{
  m_displayed = true;""",
    """void bim::axmol::app::end_game::displayed()
{
#if BIM_TEST_SEAMS
  if (std::getenv("BIM_AUTORETURN") != nullptr)
    ax::Director::getInstance()->getScheduler()->schedule(
        [this](float) { dispatch_revenge(); }, this, 0.f, 0, 2.f, false,
        "port-autoreturn");
#endif

  m_displayed = true;""",
    "end game seam",
)

edit(
    "apps/axmol/main/src/bim/axmol/app/screen/end_game.cpp",
    """#include <bim/axmol/app/screen/end_game.hpp>""",
    """#include <bim/axmol/app/screen/end_game.hpp>

#include <axmol/base/Director.h>
#include <axmol/base/Scheduler.h>

#include <cstdlib>""",
    "end game seam includes",
)

# 15. A seam for the audio check: nothing on this machine can hear the simulator, so the only
#     way to prove music and effects reach the mixer is to render the game twice, once muted
#     and once not, and compare. BIM_AUTOMUTE=music|effects|all forces the mute; the rest of the
#     pipeline (assets, OpenAL, mixer) is untouched.
edit(
    "apps/axmol/main/src/bim/axmol/app/application.cpp",
    """  if (!bim::app::music_enabled(preferences))
    audio.set_music_muted(true);

  if (!bim::app::effects_enabled(preferences))
    audio.set_effects_muted(true);""",
    """#if BIM_TEST_SEAMS
  const char* const automute = std::getenv("BIM_AUTOMUTE");
  const std::string muted(automute != nullptr ? automute : "");

  if ((!bim::app::music_enabled(preferences)) || (muted == "music")
      || (muted == "all"))
    audio.set_music_muted(true);

  if ((!bim::app::effects_enabled(preferences)) || (muted == "effects")
      || (muted == "all"))
    audio.set_effects_muted(true);
#endif""",
    "audio mute seam",
)

edit(
    "apps/axmol/main/src/bim/axmol/app/application.cpp",
    """#include <bim/app/preference/haptic.hpp>""",
    """#include <bim/app/preference/haptic.hpp>

#include <cstdlib>
#include <string>""",
    "audio seam includes",
)

# 16. No machine here can hear the simulator: the built-in speaker does not reach the built-in
#     microphone (afplay and the game's music both leave the mic at the same floor), so the
#     audio claim is checked one level down -- did axmol open the OGG and hand OpenAL a live
#     source? BIM_AUDIOLOG appends one line per play to $HOME/audio.log. Inert when unset.
edit(
    "modules/axmol/audio/main/src/bim/axmol/audio/mixer.cpp",
    """#include <axmol/audio/AudioEngine.h>""",
    """#include <axmol/audio/AudioEngine.h>

#include <cstdio>
#include <cstdlib>
#include <string>

#if BIM_TEST_SEAMS
namespace bim::axmol::audio::detail
{
  inline void audio_log(const char* kind, const std::string& path, int id)
  {
    if (std::getenv("BIM_AUDIOLOG") == nullptr)
      return;

    const char* const home = std::getenv("HOME");
    const std::string file(std::string(home != nullptr ? home : ".") + "/audio.log");
    FILE* f = std::fopen(file.c_str(), "a");

    if (f == nullptr)
      return;

    std::fprintf(f, "%s %s id=%d%s\\n", kind, path.c_str(), id,
                 id == ax::AudioEngine::INVALID_AUDIO_ID ? " (FAILED)" : "");

    std::fclose(f);
  }
}
#endif""",
    "audio log helper",
)

edit(
    "modules/axmol/audio/main/src/bim/axmol/audio/mixer.cpp",
    """  if (!m_music_muted)
    m_current_music_id = ax::AudioEngine::play2d(file_path, repeat_forever);""",
    """  if (!m_music_muted)
    m_current_music_id = ax::AudioEngine::play2d(file_path, repeat_forever);

#if BIM_TEST_SEAMS
  bim::axmol::audio::detail::audio_log("music", file_path, m_current_music_id);
#endif""",
    "music log seam",
)

edit(
    "modules/axmol/audio/main/src/bim/axmol/audio/mixer.cpp",
    """  return ax::AudioEngine::play2d(file_path, false, m_effects_muted ? 0 : 1);""",
    """  const int id = ax::AudioEngine::play2d(file_path, false, m_effects_muted ? 0 : 1);

#if BIM_TEST_SEAMS
  bim::axmol::audio::detail::audio_log("effect", file_path, id);
#endif

  return id;""",
    "effects log seam",
)

# 17. The effects channel needs its own lever. In the arena nothing is clicked, because the
#     seams call the handlers directly, so no click sound is ever requested. BIM_AUTOEFFECT
#     plays one named effect through the real mixer after the lobby settles, which proves the
#     asset, the mixer and OpenAL, leaving only the (engine, not port) click-to-sound mapping.
edit(
    "apps/axmol/main/src/bim/axmol/app/screen/lobby.cpp",
    """  m_inputs.push_back(m_controls->play_button->input_node());""",
    """#endif  // BIM_TEST_SEAMS

#if BIM_TEST_SEAMS
  if (const char* const effect = std::getenv("BIM_AUTOEFFECT"))
    {
      const std::string name(effect);

      ax::Director::getInstance()->getScheduler()->schedule(
          [name](float) {
            iscool::audio::play_effect(name, iscool::audio::loop_mode::once);
          },
          this, 0.f, 0, 4.f, false, "port-autoeffect");
    }
#endif  // BIM_TEST_SEAMS

  m_inputs.push_back(m_controls->play_button->input_node());""",
    "effect seam",
)

edit(
    "apps/axmol/main/src/bim/axmol/app/screen/lobby.cpp",
    """#include <bim/axmol/find_child_by_path.hpp>""",
    """#include <bim/axmol/find_child_by_path.hpp>

#include <iscool/audio/default_effect_player.hpp>
#include <iscool/audio/loop_mode.hpp>""",
    "effect seam include",
)

# 19. Reach the language popup. It lives inside the settings popup, so the lobby seam shows the
#     settings popup first and this opens the language selection a few seconds later, once the
#     popup is actually on screen.
edit(
    "apps/axmol/main/src/bim/axmol/app/popup/settings_popup.cpp",
    """  m_controls->language_button->connect_to_clicked(""",
    """#if BIM_TEST_SEAMS
  if (std::getenv("BIM_AUTOPRESS") != nullptr
      && std::string(std::getenv("BIM_AUTOPRESS")) == "language")
    ax::Director::getInstance()->getScheduler()->schedule(
        [this](float) { show_language_selection(); }, this, 0.f, 0, 8.f,
        false, "port-autolanguage");
#endif

  m_controls->language_button->connect_to_clicked(""",
    "language popup seam",
)

edit(
    "apps/axmol/main/src/bim/axmol/app/popup/settings_popup.cpp",
    """#include <bim/axmol/app/popup/settings_popup.hpp>""",
    """#include <bim/axmol/app/popup/settings_popup.hpp>

#include <axmol/base/Director.h>
#include <axmol/base/Scheduler.h>

#include <cstdlib>
#include <string>""",
    "language popup seam includes",
)

print("   applied 26 edits")
PY

# 14. Keep the top row out of the notch. The Android manifest has no safe area, and the style
#     data puts the wallet, the settings gear, the arena timer and every popup title at 0.90 to
#     0.99 of the screen height - which on iOS is behind the status bar, the Dynamic Island or
#     the notch. Insetting the whole layout is not an option: the backdrop, the pattern and the
#     edge glows bleed off screen by design and would leave black bands. So the *data* is moved
#     instead: every anchor between 0.90 and 0.99 is lowered by the safe top margin, and the
#     1.0 anchors (glows, patterns, bleed layers) are left alone.
#
#     The APK's own prebuilt `style/application.json` is what the app reads, so the port works
#     on a copy of the assets rather than editing the extraction in place.
safe_top=0.062  # 59 pt of a 950 pt screen: the iPhone 16 safe-area top, as a fraction
assets_copy="$repo_root/build/assets-ios"
rm -rf "$assets_copy"
cp -R "$repo_root/analysis/apktool/assets" "$assets_copy"

python3 - "$assets_copy/style/application.json" "$safe_top" <<'PY'
import json
import sys

path, safe_top = sys.argv[1], float(sys.argv[2])
low, high = 0.90, 0.995

with open(path) as f:
    data = json.load(f)

moved = []


def walk(node, trail):
    if isinstance(node, dict):
        y = node.get("anchor.reference.y")

        if isinstance(y, (int, float)) and low <= y <= high:
            node["anchor.reference.y"] = round(y - safe_top, 4)
            moved.append(trail)

        for key, value in node.items():
            walk(value, trail + "/" + key)
    elif isinstance(node, list):
        for value in node:
            walk(value, trail)


walk(data, "")

with open(path, "w") as f:
    json.dump(data, f, separators=(",", ":"))

print("   moved %d anchors clear of the notch" % len(moved))
PY

echo "==> done"

