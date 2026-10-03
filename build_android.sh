#!/usr/bin/env bash
# Legacy entry point kept for compatibility. The Android client builds the
# gomobile library from the mobile/ package itself (see
# scripts/build-android-core.sh, and OpenFluxAndroid's own copy of the same
# script). This wrapper just forwards to it.
#
# The old version of this file ran `go build -o output/android/.../openflux .`,
# which produced the CLI binary (with main.go, flag parsing, tun_darwin.go,
# signals_*.go, bench.go ...). That is not what an Android app links against:
# the app wants a .aar from `gomobile bind` over mobile/. Kept as a shim so
# anyone with muscle memory for ./build_android.sh still gets the right thing.
set -euo pipefail
exec "$(dirname "$0")/scripts/build-android-core.sh" "$@"
