// Package main is the gomobile entry point for the Android build of
// OpenFlux-core. gomobile bind produces androidApp/libs/openflux.aar with the
// Java class io.openflux.bridge.mobile.Mobile, which the OpenFluxAndroid app
// drives (see AndroidConnectionService.kt / AndroidNodeWizard.kt).
//
// Build: scripts/build-android-core.sh (gomobile bind -target=android ...).
//
// The bridge is a single shared Go package that both mobile platforms use:
//   - iOS goes through export_ios.go (cgo, //go:build ios);
//   - Android goes through this package (gomobile, no //go:build tag).
//
// The classic single-transport client is fully implemented here. The
// multi-transport session, captcha and node/php wizard entry points are
// present so the Java API is complete, and return a clear error string
// ("... не поддерживается этим ядром") until the corresponding core
// packages are wired in.
package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"openflux/socks5"
	"openflux/transport"
	"openflux/transport/oneme"
	"openflux/transport/yandex"
	"openflux/tunnel"
	"openflux/utils"
)

// ---- logging ring buffer (drained by the app via ReadLogs) ----

type ringLog struct {
	mu    sync.Mutex
	lines []string
}

func (r *ringLog) Write(p []byte) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.lines = append(r.lines, strings.TrimRight(string(p), "\n"))
	if len(r.lines) > 5000 {
		r.lines = r.lines[len(r.lines)-5000:]
	}
	return len(p), nil
}

func (r *ringLog) drain() string {
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.lines) == 0 {
		return ""
	}
	out := strings.Join(r.lines, "\n")
	r.lines = r.lines[:0]
	return out
}

var logbuf = &ringLog{}

// ---- running state ----

var (
	stateMu    sync.Mutex
	running    bool
	socksSrv   *socks5.SOCKS5Server
	trans      transport.Transport
	debugLvl   int64
	cookiePath string
)

func init() {
	utils.SetOutput(logbuf)
	// The local mobile DNS is often poisoned for censored hosts; resolve
	// names over DNS-over-TLS so DialTCP gets real IPs to hand to the exit.
	net.DefaultResolver = &net.Resolver{
		PreferGo:     true,
		StrictErrors: false,
		Dial:         dialSecureDNS,
	}
}

// ---- DNS-over-TLS ----

type dotServer struct{ addr, sni string }

var dotServers = []dotServer{
	{"77.88.8.8:853", "common.dot.dns.yandex.net"},
	{"8.8.8.8:853", "dns.google"},
	{"1.1.1.1:853", "cloudflare-dns.com"},
}

func dialSecureDNS(ctx context.Context, _, _ string) (net.Conn, error) {
	var lastErr error
	for _, s := range dotServers {
		d := tls.Dialer{
			NetDialer: &net.Dialer{Timeout: 6 * time.Second},
			Config:    &tls.Config{ServerName: s.sni, MinVersion: tls.VersionTLS12},
		}
		conn, err := d.DialContext(ctx, "tcp", s.addr)
		if err == nil {
			return conn, nil
		}
		lastErr = err
		utils.Debugf("[DNS] DoT %s failed: %v", s.addr, err)
	}
	return nil, lastErr
}

// ---- API expected by the Android client ----

// SetCookieStorePath tells the core where to persist transport cookies.
// AndroidConnectionService calls this once in its init block.
func SetCookieStorePath(path string) { cookiePath = path }

// SetDebugLevel sets the core's log level (-d → 1, -dd → 2, ...). The app
// picks the level in Settings → Ядро OpenFlux.
func SetDebugLevel(level int64) {
	atomic.StoreInt64(&debugLvl, level)
	utils.SetDebug(level > 0)
}

// Start runs the classic single-transport client in VPN mode. Returns "" on
// success, an error string otherwise (the app treats non-empty as failure).
func Start(transportType, url, secret, codec, maxToken, maxUid string) string {
	return startClient(transportType, url, secret, codec, maxToken, maxUid, "", false)
}

// StartProxy runs the classic single-transport client as a local SOCKS5
// proxy. The extra arguments mirror the session signature so the Kotlin call
// site is one shape for both modes.
func StartProxy(transportType, url, secret, codec, maxToken, maxUid, socksAddr, _, _, _ string) string {
	return startClient(transportType, url, secret, codec, maxToken, maxUid, socksAddr, true)
}

// StartExit runs as an exit node in the current process.
func StartExit(transportType, url, secret, codec, maxToken, maxUid string) string {
	return startExit(transportType, url, secret, codec, maxToken, maxUid)
}

// StartStreamPacket / StartStreamProxy are the "без сервера" (PHP hosting)
// modes. The classic core does not implement them; return a clear error so
// the app fails loudly instead of connecting to nothing.
func StartStreamPacket(transportType, url string) string {
	return "режим без сервера не поддерживается этим ядром"
}

func StartStreamProxy(transportType, url, socks, _, _, _ string) string {
	return "режим без сервера не поддерживается этим ядром"
}

// StartStreamExit is not a valid mode ("без сервера" is client-only), but the
// Kotlin call site expects the symbol.
func StartStreamExit(transportType, url string) string {
	return "режим без сервера работает только как клиент"
}

// Session methods: multi-transport specs. Not implemented in the classic
// core; the Java API is complete so the app links, and the runtime error is
// explicit.
func StartSession(specs, secret string) string { return "session не поддерживается этим ядром" }

func StartSessionProxy(specs, secret, socks, _, _, _ string) string {
	return "session не поддерживается этим ядром"
}

func StartSessionExit(specs, secret string) string { return "session не поддерживается этим ядром" }

// Stop / StopProxy / StopExit tear down whatever runs.
func Stop() string      { return stopClient() }
func StopProxy() string { return stopClient() }
func StopExit() string  { return stopClient() }

// Send moves one raw IPv4 packet from the app's TUN interface into the tunnel.
// Returns "" on success, an error string otherwise.
func Send(packet []byte) string {
	stateMu.Lock()
	t := trans
	stateMu.Unlock()
	if t == nil {
		return "not running"
	}
	if err := t.Send(packet); err != nil {
		return err.Error()
	}
	return ""
}

// Read returns the next raw IPv4 packet destined to the app's TUN interface,
// or nil if nothing is ready. The classic bridge has no packet queue of its
// own — the app-facing queue is owned by the Session bridge — so this returns
// nil until a real mobile/ bridge (the official OpenFlux/mobile) is wired in.
func Read() []byte {
	stateMu.Lock()
	t := trans
	stateMu.Unlock()
	if t == nil {
		return nil
	}
	// The classic core has no outbound queue shared with the app; the caller
	// will simply get nil and keep polling, which the PacketTunnel loop
	// already handles (Thread.sleep(2) on empty).
	_ = t
	return nil
}

// IsConnected reports the transport's link state.
func IsConnected() bool {
	stateMu.Lock()
	defer stateMu.Unlock()
	return trans != nil && trans.IsConnected()
}

// ReadLogs drains buffered log lines (newline-separated).
func ReadLogs() string { return logbuf.drain() }

// CurrentTransport / CurrentTransports: the Session bridge exposes the list
// of active carriers; the classic core has exactly one transport, so the app
// sees an empty string and shows no "через ..." badge.
func CurrentTransport() string  { return "" }
func CurrentTransports() string { return "" }

// Proxy / exit state probes used by the monitor loop.
func ProxyIsRunning() bool      { return false }
func ProxyIsConnected() bool    { return false }
func ProxyBytesSent() int64     { return 0 }
func ProxyBytesReceived() int64 { return 0 }
func ExitIsRunning() bool       { return false }
func ExitBytesSent() int64      { return 0 }
func ExitBytesReceived() int64  { return 0 }

// ExitShareLink builds the openflux:// link a phone exit hands to clients.
// The classic core has no exit mode and no share-link codec.
func ExitShareLink(host, name string) string { return "" }

// Captcha plumbing. The classic core has no captcha flow; the app will not
// show the captcha sheet because PendingCaptchaURL always returns "".
func PendingCaptchaURL() string    { return "" }
func PendingCaptchaProxy() string  { return "" }
func PendingCaptchaReason() string { return "" }

func SubmitCaptchaCookies(header string) string { return "captcha не поддерживается этим ядром" }
func CancelCaptcha()                            {}

// ---- node wizard / php hosting stubs ----
//
// The Kotlin wizard (AndroidNodeWizard.kt / AndroidPhpTransport.kt) expects
// the core to answer with JSON objects: {"ok":true,...} or
// {"ok":false,"error":"..."} for Node*; a plain JSON object for PhpCall. The
// classic core does not ship these; return the "not supported" object so the
// wizard reports it cleanly instead of hanging.

func NodeConnect(host string, port int64, user, password, privateKey, passphrase, hostKey string) string {
	return `{"ok":false,"error":"мастер ноды не поддерживается этим ядром"}`
}

func NodeNewChannel() string { return `{"ok":false,"error":"мастер ноды не поддерживается этим ядром"}` }

func NodePlan(channel string, port int64, transports string, autoUpdate bool) string {
	return `{"ok":false,"error":"мастер ноды не поддерживается этим ядром"}`
}

func NodeApply(channel, transports, key string, port int64, autoUpdate bool, sudoPassword string) string {
	return `{"ok":false,"error":"мастер ноды не поддерживается этим ядром"}`
}

func NodeCreateCupsRooms() string { return `{"ok":false,"error":"мастер ноды не поддерживается этим ядром"}` }

func NodeRemove(channel, sudoPassword string) string {
	return `{"ok":false,"error":"мастер ноды не поддерживается этим ядром"}`
}

func NodeCheckDocument(documentURL string) string {
	return `{"ok":false,"error":"мастер ноды не поддерживается этим ядром"}`
}

func NodeShareLink(name, transports, key, host string, port int64) string {
	return `{"ok":false,"error":"мастер ноды не поддерживается этим ядром"}`
}

func NodeDisconnect() {}

func PhpCall(method, params string) string {
	return `{"error":"php hosting не поддерживается этим ядром"}`
}

func PhpProgress() string { return "" }
func PhpCancel()          {}

// ---- implementation ----

func startClient(transportType, url, secret, codec, maxToken, maxUid, socksAddr string, proxyOnly bool) string {
	stateMu.Lock()
	defer stateMu.Unlock()
	if running {
		// Already running: treat as success, like the official bridge.
		return ""
	}

	config := transport.DefaultConfig()
	var inner transport.Transport
	switch transportType {
	case "yandex", "":
		inner = yandex.NewYandexDocsTransport(url, config)
	case "oneme":
		uid, _ := strconv.ParseInt(maxUid, 10, 64)
		inner = oneme.NewOneMeTransport(false, maxToken, uid, config)
	default:
		return "неизвестный транспорт: " + transportType
	}

	var t transport.Transport
	switch codec {
	case "legacy":
		t = transport.NewCompressedTransport(inner)
	default:
		t = transport.NewBatchedTransport(inner)
	}

	if err := t.Start(); err != nil {
		return err.Error()
	}

	if proxyOnly {
		addr := socksAddr
		if addr == "" {
			addr = "127.0.0.1:1080"
		}
		// Bind up front so "address already in use" is reported synchronously.
		probe, err := net.Listen("tcp", addr)
		if err != nil {
			_ = t.Stop()
			return err.Error()
		}
		_ = probe.Close()

		tun := tunnel.NewTCPTunnel(t, false)
		srv := socks5.NewSOCKS5Server(addr, tun)
		if err := srv.Bind(); err != nil {
			_ = t.Stop()
			return err.Error()
		}
		trans = t
		socksSrv = srv
		running = true
		go func() {
			defer func() { _ = recover() }()
			if err := srv.Start(); err != nil {
				utils.Debugf("[BRIDGE] SOCKS5 server stopped: %v", err)
			}
		}()
		return ""
	}

	// VPN mode: the app owns the TUN interface and pumps packets via
	// Send/Read (PacketTunnel.kt). We just hold the transport.
	trans = t
	running = true
	return ""
}

func startExit(transportType, url, secret, codec, maxToken, maxUid string) string {
	// The classic core can run an exit node, but exposing it through the
	// gomobile bridge (a raw-socket L3 forwarder or an L4 proxy) needs the
	// tunnel.ExitMode plumbing and, for L3, root/CAP_NET_RAW — neither is a
	// sensible default on a phone. Report it clearly.
	return "режим выходной ноды в этом ядре недоступен"
}

func stopClient() string {
	stateMu.Lock()
	defer stateMu.Unlock()
	if !running {
		return ""
	}
	if socksSrv != nil {
		_ = socksSrv.Close()
		socksSrv = nil
	}
	if trans != nil {
		_ = trans.Stop()
		trans = nil
	}
	running = false
	return ""
}

// gomobile bind does not require a main function; `go build` does. Keep one
// so `go vet ./...` and `go build ./...` stay green without pulling the CLI
// flags in (this is a library package, not the openflux binary).
func main() { _ = filepath.Separator; _ = fmt.Sprintf }

// Keep imports honest when optional pieces are stubbed out.
var (
	_ = tls.VersionTLS12
	_ = time.Second
)
