// Command golangci-lint is the plugin for golangci-lint v2, built for wasip1 as plugin.wasm: one request on stdin,
// one answer on stdout.
package main

import (
	_ "embed"
	"fmt"
	"os"

	"github.com/birdtable/gragas-plugin-sdk/plugin"
)

//go:embed adapter.yaml
var adapter []byte

func main() {
	p, err := newPlugin(adapter)
	if err != nil {
		fmt.Fprintln(os.Stderr, "golangci-lint plugin: the adapter is refused:", err)
		os.Exit(2)
	}
	g, err := newGuard(p)
	if err != nil {
		fmt.Fprintln(os.Stderr, "golangci-lint plugin: the tool version range is refused:", err)
		os.Exit(2)
	}
	plugin.Serve(g)
}
