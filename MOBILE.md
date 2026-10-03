# Mobile build (Android + iOS)

The desktop CLI (`go build -o openflux .`) and the two mobile artifacts are
built from the same Go module but different entry points:

| Target | Entry point | Output | Consumed by |
|---|---|---|---|
| Desktop / exit node | `main.go` (package `main` at the repo root) | `openflux` binary | Yours, `openflux --role=...` |
| Android | `mobile/mobile.go` (gomobile) | `openflux.aar` | OpenFluxAndroid |
| iOS | `export_ios.go` + `export_ios_packet.go` (`//go:build ios`) | `liboflux.a` | OpenFlux iOS app |

Android and iOS both go through the same underlying Go packages
(`transport/`, `tunnel/`, `socks5/`, `utils/`) — the bridge layer is the only
thing that differs (gomobile for Android, cgo `//export` for iOS).

## Dependency hygiene (this is what broke CI last time)

Two separate, easy-to-confuse failures:

### 1. "missing go.sum entry for module providing package ..."

`go.sum` is the checksum file that goes with `go.mod`. If `go.mod` lists a
`require X vY.Z` but `go.sum` has no matching line, every `go build` / `go vet`
that touches a package importing `X` fails with:

```

missing go.sum entry for module providing package <path> (imported by <your pkg>);
to add: go get <your pkg>

```

The fix is always the same, and it is always a **single command**:

```bash
go mod tidy
```

Run it at the repo root. It reads every import in the module, fetches what is
missing, removes what is no longer used, and rewrites `go.sum` to match. **Do
not hand-edit `go.mod` or `go.sum`** — a manually written `require` line
without its `go.sum` entry is exactly what produces the error above.

Every CI job now runs `go mod tidy` as its first step ("Sync go.sum"),
including the android-core job, so a stale `go.sum` cannot reach `gomobile
bind`.

### 2. "gomobile bind requires [golang.org/x/mobile](https://golang.org/x/mobile) in the current module"

Go 1.24's `gomobile bind` refuses to run when `golang.org/x/mobile` is not
part of the current module ([go.dev/issue/77183](https://go.dev/issue/77183)). Without that, the very first
run after a `go mod tidy` fails with:

```
gomobile bind requires golang.org/x/mobile in the current module, but it is
not in the module dependency graph.
```

Two things in this repo keep it there:

1. `go.mod` has a `tool golang.org/x/mobile/cmd/gobind` directive and a
`require golang.org/x/mobile vX.Y.Z` line for the exact revision CI uses.
2. `mobile/bind_tool.go` has a `//go:build tools` blank import of
`golang.org/x/mobile/bind`, so the package is still reachable from the
module even if `go mod tidy` is run with `-compat` flags that would
otherwise prune a pure tool dependency.

If you ever see the failure, restore both and re-tidy:

```
go get -tool golang.org/x/mobile/cmd/gobind
go mod tidy
```

and do not delete `mobile/bind_tool.go`. CI verifies this before every build
(`Sync go.sum and keep x/mobile in go.mod` step), so a future tidy cannot
silently drop the module.

## Building the Android `.aar`

```
scripts/build-android-core.sh
```

Needs Go 1.24+, `gomobile` (`go install golang.org/x/mobile/cmd/gomobile@latest`)
and the Android SDK with NDK 27.

### What the script looks for

1. **SDK:** `ANDROID_HOME` → `ANDROID_SDK_ROOT` → the conventional per-OS
locations (`~/Library/Android/sdk`, `~/Android/Sdk`, `%LOCALAPPDATA%\Android\Sdk`).
2. **NDK:** `ANDROID_NDK_HOME` first, otherwise the newest `$SDK/ndk/<ver>`
directory (sort -V, so `27.0.12077973` beats `26.x`).

It prints both paths before building, runs `go mod tidy` up front (so
`go.sum` is consistent), and fails with an actionable message if either path
is missing.

### Why `${{ env.ANDROID_HOME }}` in CI was wrong

`env.ANDROID_HOME` in a GitHub Actions workflow is **not** the runner's own
`ANDROID_HOME`. `${{ env.ANDROID_HOME }}` only sees variables declared in the
workflow's `env:` block, so it expanded to the empty string and produced
`/ndk/27.0.12077973`. The current CI computes `ANDROID_NDK_HOME` **inside the
shell** from `$ANDROID_HOME` (the runner's variable) and passes it to the
script.

## Interop with the OpenFluxAndroid app

OpenFluxAndroid ships its own copy of `scripts/build-android-core.sh`; it calls
this repo's `mobile/` package as a submodule (`OpenFlux/mobile`). The two
scripts must produce the same Java class name and the same API — hence the
`-javapkg=io.openflux.bridge` and `-androidapi=26` flags, and the
`-checklinkname=0 -s -w` linker flags ([github.com/wlynxg/anet](https://github.com/wlynxg/anet), pulled in by the
oneme/WebRTC transport, still uses a `//go:linkname` the Go linker rejects
since 1.23).

</BDS:create_file>
<BDS:create_file fileName="OpenFlux-core/build_android.sh">

```bash
#!/usr/bin/env bash
# Legacy entry point kept for compatibility. The Android client builds the
# gomobile library from the mobile/ package itself (see
# scripts/build-android-core.sh). This wrapper just forwards to it, so anyone
# with muscle memory for ./build_android.sh gets the right thing.
#
# The old version of this file ran `go build -o output/android/.../openflux .`,
# which produced the CLI binary (with main.go, flag parsing, tun_darwin.go,
# signals_*.go, bench.go ...). That is not what an Android app links against:
# the app wants a .aar from `gomobile bind` over mobile/.
set -euo pipefail
exec "$(dirname "$0")/scripts/build-android-core.sh" "$@"

