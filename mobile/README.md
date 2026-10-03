# mobile/ — the gomobile bridge

This package is the Android entry point of the OpenFlux core. `gomobile bind`
compiles it into `openflux.aar`, whose Java class the OpenFluxAndroid app
imports as:

```kotlin
import io.openflux.bridge.mobile.Mobile
```

The class name is derived by gomobile from the Go package name (`mobile`) plus
the `-javapkg` flag (`io.openflux.bridge`). Both are fixed by
`scripts/build-android-core.sh`; renaming either here or there breaks every
Kotlin call site.

## Build

```
scripts/build-android-core.sh
```

Outputs:

- `output/android/openflux.aar` — the library
- `output/android/openflux-core.version` — `branch@commit`, shown under
Settings → About in the app

If you build from inside the OpenFluxAndroid tree (or set
`OPENFLUX_ANDROID_APP=/path/to/OpenFluxAndroid`), the `.aar` lands directly in
`androidApp/libs/`.

## API surface

The Kotlin side (`AndroidConnectionService.kt`, `AndroidNodeWizard.kt`,
`AndroidPhpTransport.kt`) drives these entry points. See `mobile.go` for the
full list. Implemented:

- `Start / StartProxy / StartExit` — classic single-transport client
(VPN, SOCKS5 proxy, exit)
- `Stop / StopProxy / StopExit`
- `Send / Read / IsConnected`
- `ReadLogs / SetDebugLevel`
- `SetCookieStorePath`

Present so the Kotlin API is complete, but not implemented in this core
(they return a clear error string):

- `StartSession*` — multi-transport sessions with failover
- `StartStream*` — "без сервера" PHP-hosting profiles
- `PendingCaptchaURL / SubmitCaptchaCookies / CancelCaptcha` — captcha flow
- `Node*` — the node-deployment wizard over SSH
- `Php*` — the PHP-hosting wizard

The official OpenFlux repository (`p1neappleXpress/OpenFlux`, submodule of
OpenFluxAndroid) ships a `mobile/` package that implements all of them. If you
want the full feature set here, port that package (it is bigger than this one
and depends on packages not present in this repo).

</BDS:create_file>
<BDS:create_file fileName="OpenFlux-core/MOBILE.md">

```markdown
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

Needs Go, `gomobile` (`go install golang.org/x/mobile/cmd/gomobile@latest`)
and the Android SDK with NDK 27. The script finds the SDK via `ANDROID_HOME` /
`ANDROID_SDK_ROOT` / the usual default locations, and NDK 27 via
`ANDROID_NDK_HOME` or `<sdk>/ndk/27.0.12077973`.

`build_android.sh` at the repo root is a thin shim that forwards to the same
script, kept because the old name is muscle memory.

## Why the old `build_android.sh` was wrong

The previous version ran `go build -o output/android/.../openflux .`, which
builds the **CLI binary** — the one with flag parsing, `tun_darwin.go`,
`signals_*.go`, `bench.go`, etc. An Android app cannot link against that: it
needs a `.aar` produced by `gomobile bind` over a package that exports a
`Mobile` Java class. That is what `scripts/build-android-core.sh` (and the
`mobile/` package) provide.

The CI job `android-core` in `.github/workflows/ci.yml` builds the `.aar` on
every push and asserts that the Java class inside it is
`io/openflux/bridge/mobile/Mobile.class`, so a rename in `mobile/` fails CI
before it fails the app.

## Interop with the OpenFluxAndroid app

OpenFluxAndroid ships its own copy of `scripts/build-android-core.sh`; it calls
this repo's `mobile/` package as a submodule (`OpenFlux/mobile`). The two
scripts must produce the same Java class name and the same API — hence the
`-javapkg=io.openflux.bridge` and `-androidapi=26` flags, and the
`-checklinkname=0 -s -w` linker flags ([github.com/wlynxg/anet](https://github.com/wlynxg/anet), pulled in by the
oneme/WebRTC transport, still uses a `//go:linkname` the Go linker rejects
since 1.23).

