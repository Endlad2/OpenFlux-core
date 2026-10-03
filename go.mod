module openflux

go 1.24

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

// The gomobile toolchain. In Go 1.24+ `gomobile bind` refuses to run when
// golang.org/x/mobile is not in the module graph (go.dev/issue/77183):
// "gomobile bind requires golang.org/x/mobile in the current module".
// The tool directive keeps it there across `go mod tidy`, matching the
// version CI installs into $GOBIN (see .github/workflows/*.yml).
tool golang.org/x/mobile/cmd/gobind

require golang.org/x/mobile v0.0.0-20260908204917-8b95e45f8d3e
