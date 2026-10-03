// The gomobile bind code generator is not a normal import of this package,
// but Go 1.24+ requires golang.org/x/mobile to be present in the module
// graph for `gomobile bind` to run (go.dev/issue/77183: "gomobile bind
// requires golang.org/x/mobile in the current module, but it is not in the
// module dependency graph").
//
// A blank import of golang.org/x/mobile/bind pins the module in go.mod, so
// `go mod tidy` cannot drop it and CI's `gomobile bind` keeps working. The
// file is intentionally excluded from every build: it only exists to hold
// the import for dependency tracking.
//
//go:build tools

package main

import (
	// gomobile bind's code generator.
	_ "golang.org/x/mobile/bind"
)
