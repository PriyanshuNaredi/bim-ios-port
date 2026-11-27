#!/usr/bin/env bash
# Package a built Bim.app into an unsigned .ipa.
#
# An unsigned IPA is only installable on a jailbroken device or through SideStore /
# LiveContainer, which re-sign it with the user's own Apple ID. That is the same constraint
# the weather and Gust ports ship under.
#
# Usage: 01_port/tools/make-ipa.sh [path/to/Bim.app]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app="${1:-$root/build/bim-ios-arm64/apps/ios/Bim.app}"
out_dir="${OUT_DIR:-$root/04_release}"

if [[ ! -d "$app" ]]; then
  printf 'no app at %s\n' "$app" >&2
  exit 1
fi

name="$(basename "$app" .app)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/Payload"
cp -R "$app" "$work/Payload/"

mkdir -p "$out_dir"
ipa="$out_dir/$name-unsigned.ipa"
rm -f "$ipa"

# The zip has to keep the bundle's symlinks and executable bits; -y does both.
(cd "$work" && /usr/bin/zip -qry "$ipa" Payload)

# A signed IPA has _CodeSignature/ and an embedded.mobileprovision. Ours must have neither,
# otherwise the claim "unsigned" is a lie.
if [[ -d "$app/_CodeSignature" ]]; then
  printf 'warning: %s still has _CodeSignature\n' "$app" >&2
fi

# No automation in a shipped binary. The seams are compiled out of device builds, so the strings
# must be absent; if they are here, something built this bundle with BIM_TEST_SEAMS=1 and the
# app can be driven by an environment variable on someone else's phone.
# Every seam name, not a prefix: BIM_NETLOG and BIM_LANGUAGE do not begin with BIM_AUTO, and a
# check that only knows the AUTO family passes a binary that still logs every request.
seams='BIM_AUTOPLAY BIM_AUTOFIGHT BIM_AUTORETURN BIM_AUTOPRESS BIM_AUTOEFFECT BIM_AUTOMUTE BIM_AUDIOLOG BIM_AUTOMESSAGE BIM_LANGUAGE BIM_NETLOG'
for seam in $seams; do
  if /usr/bin/strings "$app/$name" | /usr/bin/grep -q -- "$seam"; then
    printf 'error: %s contains the %s seam; rebuild with BIM_TEST_SEAMS=0\n' "$app/$name" "$seam" >&2
    exit 1
  fi
done

printf 'wrote %s (%s bytes)\n' "$ipa" "$(stat -f %z "$ipa")"
printf 'bundle: %s\n' "$(basename "$app")"
printf 'arch:   %s\n' "$(lipo -archs "$app/$name" 2>/dev/null || echo unknown)"
