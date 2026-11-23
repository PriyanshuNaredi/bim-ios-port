#!/bin/bash
# Build everything the Bim! iOS port needs, into build/ (never /tmp — a reboot wipes it).
#
# Stages, in order, each skipped when its output already exists:
#   1. engine   axmol v2.11.2.3j for the iOS simulator       -> build/axmol-ios
#   2. boost    headers only (asio is header-only)           -> build/boost-<version>
#   3. prefix   jsoncpp, entt, moFileReader                   -> build/prefix
#   4. packages the CMake package files upstream's setup would generate -> build/prefix/lib/cmake
#   5. iscool  iscool-core 1.31.2 for the iOS simulator        -> build/prefix
#
# Usage: 01_port/tools/build-all.sh [stage ...]     (default: all stages)

# -E so the ERR trap also fires inside the stage functions.
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
port_root="$(cd "$script_dir/.." && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
analysis="$repo_root/analysis"
build="$repo_root/build"
logs="$repo_root/07_logs"
# The host is x86_64 (Hackintosh), so the simulator runtime is x86_64 too; an arm64
# simulator binary installs nowhere here.
archs="${ARCHS:-$(uname -m)}"
simulator="${SIMULATOR:-TRUE}"
prefix="$build/prefix-$archs"
engine_build="$build/axmol-ios-$archs"
engine_install="$build/axmol-ios-install-$archs"
axmol="$analysis/axmol-v17"
# Dependency versions, as pinned by the upstream commit this port follows
# (setup/dependencies/recipes/*.sh at cfa6d5a5). Everything below derives from these.
boost_version="${BOOST_VERSION:-1.91.0}"
boost_slug="boost_${boost_version//./_}"
boost_dir="$build/boost-$boost_version"
boost_package_dir="$prefix/lib/cmake/Boost-$boost_version"
deployment_target=17.0
# Half the cores by default: an all-core compile has already taken this machine down with
# a kernel spinlock timeout (the panic names UVCAssistant), so leave headroom.
jobs="${JOBS:-4}"

mkdir -p "$build" "$logs" "$prefix/lib/cmake"

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# Ninja lives under /usr/local/bin on an Intel Homebrew and /opt/homebrew/bin on Apple
# silicon; a hard-coded path is a CI failure on the other kind of runner.
ninja="$(command -v ninja || true)"
if [[ -z "$ninja" ]]; then
  echo "ninja is not on PATH; brew install ninja" >&2
  exit 1
fi
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# iscool-core's CMake only takes its iOS branches when IOS_SDK_VERSION is set.
ios_sdk_version="$(xcrun --sdk iphonesimulator --show-sdk-version)"

say() { echo "[$(date +%H:%M:%S)] $*"; }

# Every stage redirects its compiler output to 07_logs. On a remote runner that means a failed
# stage prints "exit code 1" and nothing else, so print the tail of whatever log it just wrote.
on_error()
{
  local last
  last="$(ls -t "$logs"/*.log 2>/dev/null | head -1)"

  if [[ -n "$last" ]]; then
    echo "---- last 40 lines of $last ----" >&2
    tail -40 "$last" >&2
  fi
}
trap on_error ERR

stage_engine()
{
  if [[ -f "$engine_build/lib/libaxmol.a" ]]; then
    say "engine: already built"
    return
  fi

  # Port patch: core/media/AvfMediaEngine.mm declares a __weak reference, which clang
  # rejects in a file compiled without ARC.
  python3 - "$axmol/core/media/AvfMediaEngine.mm" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path).read()
needle = "        __weak AVPlayer* player = _player;"
if needle in text:
    open(path, "w").write(text.replace(
        needle,
        "        // Port patch: compiled without ARC, where __weak is not allowed.\n"
        "        AVPlayer* player = _player;"))
PYEOF

  say "engine: configuring"
  cmake -S "$axmol" -B "$engine_build" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$ninja" \
    -DCMAKE_TOOLCHAIN_FILE="$axmol/1k/ios.cmake" \
    -DPLAT=iOS -DARCHS=$archs -DSIMULATOR=$simulator \
    -DDEPLOYMENT_TARGET=$deployment_target \
    -DCMAKE_BUILD_TYPE=Release \
    -DAX_ENABLE_TESTS=OFF -DAX_ENABLE_TRACY=OFF \
    -DAXSLCC_EXE="$axmol/tools/external/axslcc/axslcc" \
    >"$logs/axmol-ios-configure.log" 2>&1

  say "engine: building ($jobs jobs)"
  cmake --build "$engine_build" --config Release --parallel "$jobs" \
    >"$logs/axmol-ios-build.log" 2>&1

  say "engine: built $(stat -f%z "$engine_build/lib/libaxmol.a") bytes"
}

stage_boost()
{
  if [[ -d "$boost_dir/boost/asio" ]]; then
    say "boost: $boost_version already extracted"
    return
  fi

  say "boost: downloading $boost_version"
  curl -fsSL -o "$boost_dir.tar.gz" \
    "https://archives.boost.io/release/$boost_version/source/$boost_slug.tar.gz"
  tar -xzf "$boost_dir.tar.gz" -C "$build"
  mv "$build/$boost_slug" "$boost_dir"
  say "boost: $boost_version extracted"
}

stage_jsoncpp()
{
  if [[ -f "$prefix/lib/libjsoncpp.a" ]]; then
    say "jsoncpp: already installed"
    return
  fi

  say "jsoncpp: building"
  cmake -S "$analysis/jsoncpp" -B "$build/jsoncpp-ios-$archs" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$ninja" \
    -DCMAKE_TOOLCHAIN_FILE="$axmol/1k/ios.cmake" \
    -DPLAT=iOS -DARCHS=$archs -DSIMULATOR=$simulator \
    -DDEPLOYMENT_TARGET=$deployment_target \
    -DCMAKE_BUILD_TYPE=Release \
    -DJSONCPP_WITH_CMAKE_PACKAGE=ON -DJSONCPP_WITH_TESTS=OFF \
    -DJSONCPP_WITH_POST_BUILD_UNITTEST=OFF \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    >"$logs/jsoncpp-ios-configure.log" 2>&1
  cmake --build "$build/jsoncpp-ios-$archs" --parallel "$jobs" \
    >"$logs/jsoncpp-ios-build.log" 2>&1
  cmake --install "$build/jsoncpp-ios-$archs" >>"$logs/jsoncpp-ios-build.log" 2>&1
  say "jsoncpp: installed"
}

stage_entt()
{
  if [[ -d "$prefix/include/entt" ]]; then
    say "entt: already installed"
    return
  fi
  say "entt: installing headers"
  cmake -S "$analysis/entt" -B "$build/entt" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$ninja" \
    -DCMAKE_INSTALL_PREFIX="$prefix" -DENTT_INSTALL=ON \
    >"$logs/entt-configure.log" 2>&1
  cmake --build "$build/entt" --target install >>"$logs/entt-configure.log" 2>&1
}

stage_mofilereader()
{
  if [[ -f "$prefix/lib/libmoFileReader.a" && "${FORCE:-0}" != "1" ]]; then
    say "mofilereader: already built"
    return
  fi
  say "mofilereader: compiling"
  local source="$analysis/iscool-core/build/ios/mofilereader-src"
  if [[ ! -d "$source" ]]; then
    echo "mofilereader source missing: $source" >&2
    echo "Configure iscool-core once (it downloads it) or fetch it from fagbokforlaget/mofilereader." >&2
    exit 1
  fi
  # moFileReader is one .cpp, so it is compiled directly rather than through CMake. The SDK and
  # the target triple have to follow the platform: an archive built for iOS-simulator links
  # into a device binary and the linker stops with "built for 'iOS-simulator'".
  local sdk sdk_name suffix
  if [[ "$simulator" == "TRUE" ]]; then
    sdk_name=iphonesimulator
    suffix=-simulator
  else
    sdk_name=iphoneos
    suffix=
  fi
  sdk="$(xcrun --sdk "$sdk_name" --show-sdk-path)"
  xcrun --sdk "$sdk_name" clang++ -std=c++17 -O2 \
    -isysroot "$sdk" -target $archs-apple-ios$deployment_target$suffix \
    -I"$source/include" -c "$source/src/moFileReader/moFileReader.cpp" \
    -o "$build/moFileReader-$archs.o"
  xcrun --sdk "$sdk_name" libtool -static -o "$prefix/lib/libmoFileReader.a" \
    "$build/moFileReader-$archs.o"
  say "mofilereader: built"
}

stage_iscool()
{
  if [[ -f "$prefix/lib/libiscool_core.a" && "${FORCE:-0}" != "1" ]]; then
    say "iscool-core: already installed"
    return
  fi
  # Dependency patches: iscool-core 1.25.1 has iOS code paths that never compiled.
  for patch in "$port_root"/patches/iscool-core/*.patch.py; do
    [[ -e "$patch" ]] || continue
    say "iscool-core: $(basename "$patch")"
    python3 "$patch" "$analysis/iscool-core"
  done

  say "iscool-core: configuring"
  cmake -S "$analysis/iscool-core/build-scripts/cmake" -B "$build/iscool-ios-$archs" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$ninja" \
    -DCMAKE_TOOLCHAIN_FILE="$axmol/1k/ios.cmake" \
    -DPLAT=iOS -DARCHS=$archs -DSIMULATOR=$simulator \
    -DDEPLOYMENT_TARGET=$deployment_target \
    -DCMAKE_BUILD_TYPE=release \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DBoost_DIR="$boost_package_dir" \
    -Djsoncpp_DIR="$prefix/lib/cmake/jsoncpp" \
    -DCMAKE_PREFIX_PATH="$prefix" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
    -DCMAKE_CXX_STANDARD=20 -DCMAKE_CXX_STANDARD_REQUIRED=ON \
    -DIOS_SDK_VERSION="$ios_sdk_version" \
    -DUSE_DEFAULT_JSONCPP=ON -DISCOOL_TEST_ENABLED=0 \
    -DISCOOL_CORE_WITH_CMAKE_PACKAGE=ON \
    >"$logs/iscool-ios-configure.log" 2>&1
  say "iscool-core: building"
  cmake --build "$build/iscool-ios-$archs" --parallel "$jobs" \
    >"$logs/iscool-ios-build.log" 2>&1
  cmake --install "$build/iscool-ios-$archs" >>"$logs/iscool-ios-build.log" 2>&1
  say "iscool-core: installed"
}

stage_packages()
{
  say "packages: writing CMake package files"
  mkdir -p "$prefix/lib/cmake/axmol" "$prefix/lib/cmake/fmt" \
           "$prefix/lib/cmake/moFileReader" "$boost_package_dir"

  # The iOS headers are laid out the way upstream's `make install` lays them out:
  # <prefix>/include/axmol/... so that <axmol/math/Vec2.h> resolves.
  rm -rf "$prefix/include/axmol"
  mkdir -p "$prefix/include/axmol"
  for entry in "$axmol"/core/*; do
    ln -sfn "$entry" "$prefix/include/axmol/$(basename "$entry")"
  done
  ln -sfn "$axmol/extensions/GUI/src" "$prefix/include/axmol/extensions"
  ln -sfn "$axmol/extensions" "$prefix/include/extensions"
  ln -sfn "$axmol/3rdparty/fmt/include/fmt" "$prefix/include/fmt"
  ln -sfn "$axmol/3rdparty/yasio/yasio" "$prefix/include/yasio"
  cp -R "$analysis/fpm/include/fpm" "$prefix/include/" 2>/dev/null || true

  # The engine's own test apps show the full link set: its archives, the prebuilt
  # xcframework archives (curl, jpeg, openssl, opus, zlib), then the system frameworks.
  local third_party
  third_party="$(ls "$engine_build"/lib/*.a | grep -v libaxmol.a | tr '\n' ';')"
  # The prebuilt xcframeworks ship one slice per platform. The slice has to match the target:
  # picking the simulator archive for a device build links "built for iOS-simulator" code into
  # an iOS binary, which the linker rejects. Nothing warns earlier.
  local xc_slice
  if [[ "$simulator" == "TRUE" ]]; then
    xc_slice="ios-arm64_x86_64-simulator"
  else
    xc_slice="ios-arm64"
  fi
  third_party="$third_party$(ls "$axmol"/3rdparty/*/_x/lib/*/"$xc_slice"/*.a 2>/dev/null | tr '\n' ';')"
  # axmol builds OpenAL Soft as a dynamic framework on iOS; it must also be embedded in
  # the app bundle, which the app target does.
  third_party="$third_party$engine_build/engine/3rdparty/openal/soft_oal.framework/soft_oal;"

  # The engine is compiled with a set of AX_ENABLE_* / AX_USE_* switches, and some of them
  # change struct layouts in the public headers (Node gains a member with
  # AX_ENABLE_PHYSICS, for instance). Consumers must be compiled with the same switches
  # or they read the engine's objects at the wrong offsets, which looks like members that
  # are silently null.
  local engine_defines
  engine_defines="$(grep -o '\-DAX_[A-Z_0-9]*=[0-9]*' "$engine_build/build.ninja" \
    | sort -u | sed 's/^-D//' | tr '\n' ';')"

  local frameworks
  frameworks=""
  for name in AudioToolbox AVFoundation AVKit CoreGraphics CoreMedia CoreMotion \
              CoreText CoreVideo Foundation GameController Metal QuartzCore \
              MessageUI Security UIKit WebKit; do
    frameworks="$frameworks;-framework $name"
  done

  # Consumers include axmol's headers that in turn include third-party headers
  # ("llhttp.h", "3rdparty/openal/…"), so every third-party include directory joins the
  # interface.
  local third_party_includes
  third_party_includes="$(ls -d "$axmol"/3rdparty/*/include 2>/dev/null | tr '\n' ';')"

  cat >"$prefix/lib/cmake/axmol/axmol-config.cmake" <<EOF
# axmol for iOS, written by the port: upstream's setup script generates the same file but
# only for Linux and Android.
set(axmol_root "$axmol")
if(NOT TARGET axmol::axmol)
  add_library(axmol::axmol INTERFACE IMPORTED)
  set_target_properties(axmol::axmol PROPERTIES
    INTERFACE_COMPILE_DEFINITIONS "AX_PLATFORM_IOS=1;$engine_defines"
    INTERFACE_INCLUDE_DIRECTORIES
      "$prefix/include;$axmol;$axmol/core;$axmol/3rdparty;$axmol/3rdparty/robin-map/include;$third_party_includes"
    INTERFACE_LINK_LIBRARIES
      "$engine_build/lib/libaxmol.a;$third_party$frameworks;-lc++;-lobjc")
endif()
set(axmol_FOUND TRUE)
set(AX_ROOT "\${axmol_root}")
EOF
  printf 'set(PACKAGE_VERSION "2.11.2.3j")\nset(PACKAGE_VERSION_COMPATIBLE TRUE)\nset(PACKAGE_VERSION_EXACT FALSE)\n' \
    >"$prefix/lib/cmake/axmol/axmol-config-version.cmake"

  mkdir -p "$prefix/lib/cmake/fmt"
  cat >"$prefix/lib/cmake/fmt/fmt-config.cmake" <<EOF
set(fmt_FOUND TRUE)
set(fmt_VERSION "11.2.0")
if(NOT TARGET fmt::fmt)
  add_library(fmt::fmt STATIC IMPORTED)
  set_target_properties(fmt::fmt PROPERTIES
    IMPORTED_LOCATION "$engine_build/lib/libfmt.a"
    INTERFACE_INCLUDE_DIRECTORIES "$axmol/3rdparty/fmt/include")
  add_library(fmt::fmt-header-only INTERFACE IMPORTED)
  set_target_properties(fmt::fmt-header-only PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "$axmol/3rdparty/fmt/include")
endif()
EOF
  cp "$prefix/lib/cmake/fmt/fmt-config.cmake" "$prefix/lib/cmake/fmt/fmtConfig.cmake"

  mkdir -p "$prefix/lib/cmake/moFileReader"
  cat >"$prefix/lib/cmake/moFileReader/moFileReader-config.cmake" <<EOF
set(moFileReader_FOUND TRUE)
if(NOT TARGET moFileReader)
  add_library(moFileReader STATIC IMPORTED)
  set_target_properties(moFileReader PROPERTIES
    IMPORTED_LOCATION "$prefix/lib/libmoFileReader.a"
    INTERFACE_INCLUDE_DIRECTORIES "$analysis/iscool-core/build/ios/mofilereader-src/include")
endif()
EOF
  cp "$prefix/lib/cmake/moFileReader/moFileReader-config.cmake" \
     "$prefix/lib/cmake/moFileReader/moFileReaderConfig.cmake"

  # Boost: headers only. Saying so explicitly makes iscool-locale skip Boost.Locale, which
  # needs ICU data that the iOS SDK does not ship in a form CMake can find.
  mkdir -p "$boost_package_dir"
  cat >"$boost_package_dir/BoostConfig.cmake" <<EOF
if(Boost_FIND_COMPONENTS)
  set(Boost_FOUND FALSE)
  return()
endif()
set(Boost_FOUND TRUE)
set(Boost_VERSION "$boost_version")
set(Boost_VERSION_STRING "$boost_version")
if(NOT TARGET Boost::headers)
  add_library(Boost::headers INTERFACE IMPORTED)
  set_target_properties(Boost::headers PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "$boost_dir")
  add_library(Boost::boost ALIAS Boost::headers)
endif()
EOF
  printf 'set(PACKAGE_VERSION "%s")\nset(PACKAGE_VERSION_COMPATIBLE TRUE)\n' \
    "$boost_version" >"$boost_package_dir/BoostConfigVersion.cmake"

  say "packages: done"
}

stages=("$@")
if [[ ${#stages[@]} -eq 0 ]]; then
  # packages comes before iscool: the Boost stub it writes is what makes iscool-core
  # take its "no Boost.Locale" branch.
  stages=(engine boost jsoncpp entt mofilereader packages iscool)
fi

for stage in "${stages[@]}"; do
  "stage_$stage"
done

say "all stages complete"
