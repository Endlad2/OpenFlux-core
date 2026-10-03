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

## Building the Android `.aar`

```bash
scripts/build-android-core.sh
```

Needs Go 1.24+, `gomobile` (`go install golang.org/x/mobile/cmd/gomobile@latest`)
and the Android SDK with NDK 27.

### gomobile bind and [golang.org/x/mobile](https://golang.org/x/mobile) in the module graph

Go 1.24 changed `gomobile bind` to refuse to run when `golang.org/x/mobile` is
not part of the current module ([go.dev/issue/77183](https://go.dev/issue/77183)). Without that, the very
first run after a `go mod tidy` fails with:

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

If you ever see the failure, restore both:

```
go get -tool golang.org/x/mobile/cmd/gobind
go mod tidy
```

and do not delete `mobile/bind_tool.go`. CI verifies this before every build
(`Ensure x/mobile stays in the module graph` step).

### What the script looks for

1. **SDK:** `ANDROID_HOME` → `ANDROID_SDK_ROOT` → the conventional per-OS
locations (`~/Library/Android/sdk`, `~/Android/Sdk`, `%LOCALAPPDATA%\Android\Sdk`).
2. **NDK:** `ANDROID_NDK_HOME` first, otherwise the newest `$SDK/ndk/<ver>`
directory (sort -V, so `27.0.12077973` beats `26.x`).

It prints both paths before building, and fails with an actionable message if
either is missing.

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

