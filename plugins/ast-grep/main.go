// Command ast-grep is the plugin for ast-grep, built for wasip1 as plugin.wasm: one request on stdin, one answer on
// stdout. It is the declarative plugin of adapter.yaml, with no code of its own: the config read is of files (the rule
// folders sgconfig.yml names), asked for in rounds.
package main

import (
	_ "embed"
	"fmt"
	"os"

	"github.com/birdtable/gragas-plugin-sdk/declarative"
	"github.com/birdtable/gragas-plugin-sdk/plugin"
)

//go:embed adapter.yaml
var adapter []byte

func main() {
	p, err := declarative.New(adapter)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ast-grep plugin: the adapter is refused:", err)
		os.Exit(2)
	}
	g, err := newGuard(p)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ast-grep plugin: the tool version range is refused:", err)
		os.Exit(2)
	}
	plugin.Serve(g)
}
