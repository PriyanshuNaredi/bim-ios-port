#!/usr/bin/env bash
# Regenerate the iOS home-screen icon set from the APK's own launcher icon.
#
# The APK ships one bitmap, res/mipmap-xxxhdpi/ic_launcher.png (432x432), plus an adaptive-icon
# XML that points its background at ic_launcher_round. There is no vector source, so this script
# scales that bitmap with sips and writes the flat PNG set an iOS bundle needs. The largest size
# (1024) is an upscale and is slightly soft; every other size is a downscale and is clean.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src="${BIM_ICON_SRC:-$repo_root/analysis/apktool/res/mipmap-xxxhdpi/ic_launcher.png}"
out="${BIM_ICON_OUT:-$repo_root/01_port/overlay/apps/ios/icons}"

if [[ ! -f "$src" ]]; then
  echo "no launcher icon at $src" >&2
  exit 1
fi

mkdir -p "$out"

# name:points -> pixels at @2x / @3x. iOS asks for these sizes and no others on iPhone.
while read -r name px; do
  [[ -z "$name" ]] && continue
  sips -s format png -z "$px" "$px" "$src" --out "$out/$name.png" >/dev/null
  echo "  $name.png ${px}x${px}"
done <<'SIZES'
Icon-20@2x 40
Icon-20@3x 60
Icon-29@2x 58
Icon-29@3x 87
Icon-40@2x 80
Icon-40@3x 120
Icon-60@2x 120
Icon-60@3x 180
Icon-76@2x 152
Icon-83.5@2x 167
Icon-1024 1024
SIZES

echo "wrote $(ls "$out" | wc -l | tr -d ' ') icons into $out"
