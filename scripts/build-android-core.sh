#!/usr/bin/env bash
# Builds the core the Android app bundles: the gomobile library from the
# mobile/ package of this OpenFlux core checkout, into
# androidApp/libs/openflux.aar, plus openflux-core.version
# (branch@commit, shown under Settings → About).
#
#   scripts/build-android-core.sh              # uses this checkout
#   scripts/build-android-core.sh ../OpenFlux  # or any other checkout
#
# Needs Go 1.24+, gomobile (go install golang.org/x/mobile/cmd/gomobile@latest)
# and the Android SDK with NDK 27 (ANDROID_HOME / ANDROID_NDK_HOME, or the SDK
# in its default place).
#
# gomobile bind in Go 1.24+ refuses to run when golang.org/x/mobile is not in
# the module graph (go.dev/issue/77183). go.mod keeps it via the `tool`
# directive and mobile/bind_tool.go, so a plain `go mod tidy` will not drop it.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
core=$(cd "${1:-$root}" && pwd)
[ -d "$core/mobile" ] || {
  echo "$core has no mobile/ package. Run from an OpenFlux core checkout that ships mobile/." >&2
  exit 1
}

# ---- preflight: gomobile and x/mobile in the module graph ----------------
# Fail here, with an actionable message, instead of inside `gomobile bind`
# after it has already spent time on the NDK/SDK discovery.
if ! grep -q 'golang.org/x/mobile' "$core/go.mod"; then
  cat >&2 <<'EOF'
go.mod does not reference golang.org/x/mobile, so `gomobile bind` will refuse
to run (go.dev/issue/77183). Add it with:

    go get -tool golang.org/x/mobile/cmd/gobind
    go mod tidy

and make sure mobile/bind_tool.go exists (the //go:build tools blank import
keeps the module in the graph across `go mod tidy`).
EOF
  exit 1
fi

# ---- preflight: go.sum is consistent with go.mod --------------------------
# `go mod tidy` is what repairs go.sum after a go.mod edit. Do it here rather
# than in CI alone, so a local build and CI agree, and the "missing go.sum
# entry for module providing package X" class of failures cannot reach
# gomobile bind.
if ! (cd "$core" && go mod tidy >/dev/null 2>&1); then
  echo "go mod tidy failed; run it manually and fix the first error:" >&2
  (cd "$core" && go mod tidy) >&2 || true
  exit 1
fi

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

# ---- SDK ----------------------------------------------------------------
sdk="${ANDROID_HOME:-}"
[ -n "$sdk" ] || sdk="${ANDROID_SDK_ROOT:-}"
if [ -z "$sdk" ]; then
  for guess in \
    "${LOCALAPPDATA:-}/Android/Sdk" \
    "$HOME/Library/Android/sdk" \
    "$HOME/Android/Sdk"; do
    [ -n "$guess" ] && [ -d "$guess" ] && sdk="$guess" && break
  done
fi
[ -n "$sdk" ] && [ -d "$sdk" ] || {
  echo "Android SDK not found: set ANDROID_HOME (or ANDROID_SDK_ROOT)" >&2
  exit 1
}

# ---- NDK ----------------------------------------------------------------
# ANDROID_NDK_HOME wins (CI sets it); otherwise the newest side-by-side
# install under $SDK/ndk, so a fresh `sdkmanager "ndk;27.x"` keeps working
# even if the exact folder name changes.
ndk="${ANDROID_NDK_HOME:-}"
if [ -z "$ndk" ] && [ -d "$sdk/ndk" ]; then
  ndk=$(find "$sdk/ndk" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
        | sort -V | tail -n1)
  [ -n "$ndk" ] && ndk="$sdk/ndk/$ndk"
fi
[ -n "$ndk" ] && [ -d "$ndk" ] || {
  echo "Android NDK not found. Set ANDROID_NDK_HOME, or install one with:" >&2
  echo "  sdkmanager \"ndk;27.0.12077973\"" >&2
  echo "Looked in: ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-<unset>} and $sdk/ndk/*" >&2
  exit 1
}
echo "Using SDK: $sdk"
echo "Using NDK: $ndk"

# ---- gomobile -----------------------------------------------------------
gomobile=${GOMOBILE_BIN:-$(command -v gomobile || true)}
[ -n "$gomobile" ] || gomobile="$(go env GOPATH)/bin/gomobile"
[ -x "$gomobile" ] || [ -x "$gomobile.exe" ] || {
  echo "gomobile not found: go install golang.org/x/mobile/cmd/gomobile@latest" >&2
  exit 1
}

export ANDROID_HOME="$sdk"
export ANDROID_SDK_ROOT="$sdk"
export ANDROID_NDK_HOME="$ndk"
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

# The version marker: the app shows it under Settings → About.
if git -C "$core" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$core" rev-parse --abbrev-ref HEAD)
  rev=$(git -C "$core" describe --always --dirty)
  printf '%s@%s\n' "$branch" "$rev" > "$out/openflux-core.version"
else
  printf 'unknown@unknown\n' > "$out/openflux-core.version"
fi
echo "core $(cat "$out/openflux-core.version") -> $out/openflux.aar"
