// The module path matches the imports in this repo (openflux/transport,
// openflux/tunnel, ...). Do not rename it without updating every import.
module openflux

// Go 1.24 is where `tool` directives were introduced. The exact revision of
// golang.org/x/mobile lives in the require/tool lines below; bump both
// together (see MOBILE.md).
go 1.24

// --- Third-party modules the repo already depends on -----------------------
//
// The list below is what `go mod tidy` on this tree produces. It is NOT meant
// to be hand-edited: after adding a new import anywhere in the module, run
//
//     go mod tidy
//
// and commit both go.mod and go.sum. A hand-written require line without a
// matching go.sum entry is exactly what makes `go build`/`go vet` fail with
// "missing go.sum entry for module providing package ...".

require (
	github.com/gorilla/websocket v1.5.3
	github.com/klauspost/compress v1.18.0
	github.com/pierrec/lz4/v4 v4.1.22
	github.com/pion/webrtc/v3 v3.3.5
	github.com/xjasonlyu/windivert-go v0.0.0-20230207140701-cdcf41f5d17c
	golang.org/x/crypto v0.32.0
	golang.org/x/sys v0.29.0
	gvisor.dev/gvisor v0.0.0-20250503011750-9e2c3db1a5ec
)

require (
	github.com/google/btree v1.1.3 // indirect
	github.com/pion/datachannel v1.5.10 // indirect
	github.com/pion/dtls/v2 v2.2.12 // indirect
	github.com/pion/ice/v2 v2.3.37 // indirect
	github.com/pion/interceptor v0.1.37 // indirect
	github.com/pion/logging v0.2.2 // indirect
	github.com/pion/mdns v0.0.12 // indirect
	github.com/pion/randutil v0.1.0 // indirect
	github.com/pion/rtcp v1.2.15 // indirect
	github.com/pion/rtp v1.8.11 // indirect
	github.com/pion/sctp v1.8.35 // indirect
	github.com/pion/sdp/v3 v3.0.10 // indirect
	github.com/pion/srtp/v2 v2.0.20 // indirect
	github.com/pion/stun v0.6.1 // indirect
	github.com/pion/transport/v2 v2.2.10 // indirect
	github.com/pion/turn/v2 v2.1.6 // indirect
	github.com/pion/webrtc/v4 v4.0.8 // indirect
	github.com/wlynxg/anet v0.0.5 // indirect
	golang.org/x/net v0.34.0 // indirect
	golang.org/x/time v0.9.0 // indirect
)

// --- gomobile bind needs x/mobile in the module graph -----------------------
//
// Go 1.24's gomobile refuses to run when golang.org/x/mobile is not part of
// the current module (go.dev/issue/77183). The tool directive below is what
// records it, and mobile/bind_tool.go (//go:build tools) keeps the blank
// import reachable across `go mod tidy`.
//
// To (re)create these two lines:
//
//     go get -tool golang.org/x/mobile/cmd/gobind
//     go mod tidy
//
// CI (.github/workflows/ci.yml, job android-core) runs the same and then
// asserts the module is still here, so a future tidy cannot silently drop it.
tool golang.org/x/mobile/cmd/gobind

require golang.org/x/mobile v0.0.0-20260908204917-8b95e45f8d3e
