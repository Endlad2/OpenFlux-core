#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
NDK_ROOT="${ANDROID_NDK_HOME:-$SDK_ROOT/ndk/27.0.12077973}"
GOMOBILE_BIN="${GOMOBILE_BIN:-$(command -v gomobile || true)}"

# Platforms to build AAR for.
# gomobile -target=android/<arch> produces an AAR with JNI libs for that ABI only.
# Mapping: arm64 -> arm64-v8a, arm -> armeabi-v7a, amd64 -> x86_64
PLATFORMS=(
    "arm64:arm64-v8a"
    "arm:armeabi-v7a"
    "amd64:x86_64"
)

if [ -z "$SDK_ROOT" ] || [ ! -d "$SDK_ROOT" ]; then
    echo "Android SDK not found. Set ANDROID_SDK_ROOT or ANDROID_HOME."
    exit 1
fi
if [ ! -x "$GOMOBILE_BIN" ]; then
    echo "gomobile not found in PATH."
    echo "Install it with: go install golang.org/x/mobile/cmd/gomobile@latest"
    exit 1
fi
if [ ! -d "$NDK_ROOT" ]; then
    echo "Android NDK not found at $NDK_ROOT"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/go.mod" ]; then
    echo "go.mod not found at $SCRIPT_DIR — run this script from the repository root."
    exit 1
fi
if [ ! -d "$SCRIPT_DIR/mobile" ]; then
    echo "The mobile package is missing at $SCRIPT_DIR/mobile"
    exit 1
fi

OUTPUT_DIR="$SCRIPT_DIR/dist"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/openflux-*.aar

export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_NDK_HOME="$NDK_ROOT"
export PATH="$(dirname -- "$GOMOBILE_BIN"):$PATH"

for ENTRY in "${PLATFORMS[@]}"; do
    GOARCH="${ENTRY%%:*}"
    ABI="${ENTRY##*:}"
    OUT_AAR="$OUTPUT_DIR/openflux-android-${ABI}.aar"

    echo ">>> Building AAR for android/${GOARCH} (${ABI}) ..."

    (
        # The mobile bridge lives in ./mobile as part of the root module,
        # so gomobile must run from the repo root and bind the ./mobile package.
        cd "$SCRIPT_DIR"
        # github.com/wlynxg/anet (pulled in transitively by the oneme/WebRTC
        # transport) still uses a //go:linkname into net.zoneCache that Go's
        # linker rejects by default since the 1.23 linkname hardening; no
        # release of anet has adapted to it yet. -checklinkname=0 downgrades
        # that to the old permissive behavior instead of a hard link failure.
        "$GOMOBILE_BIN" bind \
            -target="android/${GOARCH}" \
            -androidapi=26 \
            -javapkg=io.openflux.bridge \
            -ldflags="-checklinkname=0" \
            -o "$OUT_AAR" \
            ./mobile
    )

    echo "    -> $OUT_AAR"
done

echo
echo "Built AARs:"
find "$OUTPUT_DIR" -maxdepth 1 -name "openflux-*.aar" -print | sort