#!/usr/bin/env bash
# Fetch everything the port builds from, at the exact versions it is pinned to.
#
# A fresh clone has no sources: `analysis/` is ignored because it holds several large upstream
# repositories plus a decompiled APK. This script recreates it, so the repository is
# self-contained in the sense that matters -- one command and a network connection, no manual
# steps, no guessing which commit.
#
# Fetching is shallow and by ref, so this is a few tens of megabytes rather than a full clone of
# axmol's history. Existing directories are left alone unless FORCE=1.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
analysis="$repo_root/analysis"

ok() { echo "   $*"; }

# fetch <dir> <url> <ref>
fetch()
{
  local dir="$analysis/$1" url="$2" ref="$3" name="$1"

  if [[ -d "$dir/.git" ]]; then
    ok "$name: present ($(git -C "$dir" describe --tags --always 2>/dev/null || echo unknown))"
    return
  fi

  if [[ -e "$dir" && "${FORCE:-0}" != "1" ]]; then
    ok "$name: present, not a git clone; leaving it alone (FORCE=1 replaces it)"
    return
  fi

  rm -rf "$dir"
  mkdir -p "$dir"
  git -C "$dir" init --quiet
  git -C "$dir" remote add origin "$url"
  # --depth 1 with a bare sha only works if the server allows fetching arbitrary commits; the
  # fallback below does a full fetch for the repos that do not.
  if ! git -C "$dir" fetch --quiet --depth 1 origin "$ref" 2>/dev/null; then
    git -C "$dir" fetch --quiet origin "$ref"
  fi
  git -C "$dir" checkout --quiet FETCH_HEAD
  ok "$name: $ref"
}

echo "==> sources"
# The game itself, at the last commit that still reports version 17 (see 00_recon/DECISIONS.md
# D6: the v17 tag is older than the APK, which was built 73 commits later).
fetch upstream      https://github.com/j-jorge/bim.git        "${BIM_PIN:-cfa6d5a5f66b0465e5d77a435515450947e16a9f}"
fetch axmol-v17     https://github.com/j-jorge/axmol.git      v2.11.2.3j
fetch iscool-core   https://github.com/j-jorge/iscool-core.git 1.31.2
fetch jsoncpp       https://github.com/open-source-parsers/jsoncpp.git 1.9.6
fetch entt          https://github.com/skypjack/entt.git      v3.16.0
fetch fpm           https://github.com/j-jorge/fpm.git        v1.1.1

echo "==> tools"
# axmol compiles its GLSL to Metal at build time with axslcc, and expects a prebuilt binary at
# tools/external/axslcc/axslcc -- which is not in the axmol repository and is not created by the
# engine's CMake. Without it the engine build dies at the first shader with code=127. The version
# is pinned to the one this port is built against.
axslcc="$analysis/axmol-v17/tools/external/axslcc/axslcc"
axslcc_version="${AXSLCC_VERSION:-1.14.0}"
if [[ ! -x "$axslcc" ]]; then
  case "$(uname -m)" in
    arm64) slug=osx-arm64 ;;
    *)     slug=osx-x64 ;;
  esac
  mkdir -p "$(dirname "$axslcc")"
  echo "   downloading axslcc $axslcc_version ($slug)"
  curl -fsSL -o "$analysis/axslcc.tar.gz" \
    "https://github.com/simdsoft/axslcc/releases/download/v$axslcc_version/axslcc-$axslcc_version-$slug.tar.gz"
  tar -xzf "$analysis/axslcc.tar.gz" -C "$(dirname "$axslcc")"
  rm -f "$analysis/axslcc.tar.gz"
  chmod +x "$axslcc"
fi
ok "axslcc: $("$axslcc" --version 2>&1 | head -1)"

echo "==> assets"
# The prebuilt assets (atlas, style declarations, fonts, gettext catalogues, audio) exist only
# inside the APK that upstream publishes. Decompiling it is how the port gets them: the pipeline
# that would generate them needs ImageMagick, pack-my-sprites and a full desktop build.
apk="$analysis/bim-17.apk"
if [[ ! -f "$apk" ]]; then
  echo "   downloading bim-17.apk from the upstream release"
  curl -fsSL -o "$apk" \
    "https://github.com/j-jorge/bim/releases/download/v17/bim-17.apk"
fi

if [[ ! -d "$analysis/apktool/assets" ]]; then
  if ! command -v apktool >/dev/null; then
    echo "apktool is required to extract the assets: brew install apktool" >&2
    exit 1
  fi
  echo "   decompiling the APK"
  apktool d -f -q -o "$analysis/apktool" "$apk"
fi
ok "apktool: $(find "$analysis/apktool/assets" -type f | wc -l | tr -d ' ') asset files"

echo "==> done"
