#!/bin/bash
# Configure and build Bim.app for the iOS simulator from the prepared tree.
#
# Depends on build/prefix (01_port/tools/build-all.sh) holding the engine, jsoncpp, entt,
# moFileReader and iscool-core for iOS.
#
# Usage: 01_port/tools/build-app.sh [--clean]

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
build="$repo_root/build"
archs="${ARCHS:-$(uname -m)}"
prefix="$build/prefix-$archs"
axmol="$repo_root/analysis/axmol-v17"
source_tree="$build/ios-src"
build_dir="$build/bim-ios-$archs"
logs="$repo_root/07_logs"
deployment_target=17.0

if [[ "${1:-}" == "--clean" ]]; then
  rm -rf "$build_dir"
fi

mkdir -p "$logs"

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

"$script_dir/prepare-tree.sh" "$source_tree" >/dev/null

if [[ ! -f "$source_tree/CMakeLists.txt" ]]; then
  echo "prepared tree missing at $source_tree" >&2
  exit 1
fi

# -include cstddef/cstdint/span: upstream relies on libstdc++ pulling these in, libc++ does
# not. This is a compiler flag rather than a source edit so the tree stays upstream-shaped.
common_cxx_flags="-include cstddef -include cstdint -include span"

echo "==> configure"
cmake -S "$source_tree" -B "$build_dir" -G Ninja \
  -DCMAKE_MAKE_PROGRAM=/usr/local/bin/ninja \
  -DCMAKE_TOOLCHAIN_FILE="$axmol/1k/ios.cmake" \
  -DPLAT=iOS -DARCHS=$archs -DSIMULATOR=TRUE \
  -DDEPLOYMENT_TARGET=$deployment_target \
  -DCMAKE_BUILD_TYPE="${BUILD_TYPE:-Release}" \
  -DCMAKE_CXX_STANDARD=20 \
  "-DCMAKE_CXX_FLAGS=$common_cxx_flags" \
  -DCMAKE_PREFIX_PATH="$prefix" \
  -Daxmol_DIR="$prefix/lib/cmake/axmol" \
  -Dfmt_DIR="$prefix/lib/cmake/fmt" \
  -DEnTT_DIR="$prefix/lib/EnTT/cmake" \
  -DmoFileReader_DIR="$prefix/lib/cmake/moFileReader" \
  -Discool-core_DIR="$prefix/lib/cmake/iscool-core" \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
  -DBIM_TARGET=ios \
  -DBIM_BUILDING_FOR_IOS=TRUE \
  -DBIM_PROD_BUILD=ON \
  -DBIM_BUSINESS_SERVER_URL=https://bim-prod.jorge.st \
  -DBIM_PREBUILT_ASSETS_DIR="$repo_root/analysis/apktool/assets" \
  -DBIM_AXMOL_SHADERS_DIR="$build/axmol-ios-$archs/runtime/axslc" \
  -DBIM_OPENAL_FRAMEWORK="$build/axmol-ios-$archs/engine/3rdparty/openal/soft_oal.framework" \
  -DBIM_BUILD_TESTS=OFF -DBIM_BUILD_BENCHMARKS=OFF -DBIM_BUILD_SERVER=OFF \
  >"$logs/bim-ios-configure.log" 2>&1

echo "==> build"
cmake --build "$build_dir" --parallel "${JOBS:-$(( $(sysctl -n hw.ncpu) / 2 ))}" 2>&1 | tee "$logs/bim-ios-build.log" | tail -5

app="$build_dir/apps/ios/Bim.app"
if [[ ! -d "$app" ]]; then
  echo "no app bundle at $app" >&2
  exit 1
fi
echo "==> $app"
