#!/usr/bin/env bash
# Builds the core the Android app bundles: the gomobile library from the
# mobile/ package of this OpenFlux core checkout, into
# androidApp/libs/openflux.aar, plus openflux-core.version
# (branch@commit, shown under Settings → About).
#
#   scripts/build-android-core.sh              # uses this checkout
#   scripts/build-android-core.sh ../OpenFlux  # or any other checkout
#
# Needs Go, gomobile (go install golang.org/x/mobile/cmd/gomobile@latest) and
# the Android SDK with NDK 27 (ANDROID_HOME / ANDROID_NDK_HOME, or the SDK in
# its default place).
#
# This is the OpenFlux-core side of the build. The Android app's own
# scripts/build-android-core.sh calls exactly this, so keeping the two in
# sync (same -javapkg, same -androidapi, same -ldflags) is what makes the
# Java class io.openflux.bridge.mobile.Mobile line up with
# AndroidConnectionService.kt.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
core=$(cd "${1:-$root}" && pwd)
[ -d "$core/mobile" ] || {
  echo "$core has no mobile/ package. Run from an OpenFlux core checkout that ships mobile/." >&2
  exit 1
}

# Output goes to the Android app's libs/ when we are inside it, otherwise to
# the core's own output/ so a standalone build still works.
if [ -d "$root/androidApp/libs" ]; then
  out="$root/androidApp/libs"
elif [ -n "${OPENFLUX_ANDROID_APP:-}" ] && [ -d "$OPENFLUX_ANDROID_APP/androidApp/libs" ]; then
  out="$OPENFLUX_ANDROID_APP/androidApp/libs"
else
  out="$root/output/android"
fi
mkdir -p "$out"

sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
if [ -z "$sdk" ]; then
  for guess in "${LOCALAPPDATA:-}/Android/Sdk" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [ -d "$guess" ] && sdk=$guess && break
  done
fi
[ -d "$sdk" ] || { echo "Android SDK not found: set ANDROID_HOME" >&2; exit 1; }
ndk=${ANDROID_NDK_HOME:-$sdk/ndk/27.0.12077973}
[ -d "$ndk" ] || { echo "Android NDK not found at $ndk: set ANDROID_NDK_HOME" >&2; exit 1; }

gomobile=${GOMOBILE_BIN:-$(command -v gomobile || true)}
[ -n "$gomobile" ] || gomobile=$(go env GOPATH)/bin/gomobile
[ -x "$gomobile" ] || [ -x "$gomobile.exe" ] || {
  echo "gomobile not found: go install golang.org/x/mobile/cmd/gomobile@latest" >&2
  exit 1
}

export ANDROID_HOME=$sdk ANDROID_SDK_ROOT=$sdk ANDROID_NDK_HOME=$ndk
export PATH="$(dirname "$gomobile"):$PATH"
# gomobile's javac reads the generated sources (Russian doc comments) in the
# platform encoding, which is not UTF-8 on Windows.
export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF-8 ${JAVA_TOOL_OPTIONS:-}"
trap '[ -s "$out/openflux.aar" ] || rm -f "$out/openflux.aar"' EXIT

# github.com/wlynxg/anet (pulled in by the oneme/WebRTC transport) still uses
# a //go:linkname Go's linker rejects since 1.23; -checklinkname=0 lets it link.
(cd "$core/mobile" && "$gomobile" bind \
  -target=android \
  -androidapi=26 \
  -javapkg=io.openflux.bridge \
  -ldflags="-checklinkname=0 -s -w" \
  -o "$out/openflux.aar" \
  .)
rm -f "$out/openflux-sources.jar"

branch=$(git -C "$core" rev-parse --abbrev-ref HEAD)
rev=$(git -C "$core" describe --always --dirty)
printf '%s@%s\n' "$branch" "$rev" > "$out/openflux-core.version"
echo "core $(cat "$out/openflux-core.version") -> $out/openflux.aar"
