// Command tsc is the TypeScript compiler plugin of plugin contract 1: tsc's adapter, a flat list of compiler options,
// served by the SDK's declarative package. Built for wasip1 it is plugins/tsc/<version>/plugin.wasm.
package main

import (
	_ "embed"
	"fmt"
	"os"

	"github.com/birdtable/gragas-plugin-sdk/declarative"
	"github.com/birdtable/gragas-plugin-sdk/plugin"
	"github.com/birdtable/gragas-plugin-sdk/wire"
)

//go:embed adapter.yaml
var adapter []byte

// Tsc is the declarative plugin with one thing added: a plan refuses a config path that is not a plain relative path.
type Tsc struct{ *declarative.Plugin }

// Plan refuses an unsafe config path, then is the declarative plan.
func (t Tsc) Plan(req wire.PlanRequest) (wire.PlanResponse, error) {
	if err := refuseUnsafeConfig(req.Config); err != nil {
		return wire.PlanResponse{}, err
	}
	if err := refuseReachingConfig(req.Config); err != nil {
		return wire.PlanResponse{}, err
	}
	return t.Plugin.Plan(req)
}

// New is the plugin: the adapter, read by the SDK.
func New() (plugin.Plugin, error) {
	p, err := declarative.New(adapter)
	if err != nil {
		return nil, err
	}
	return newGuard(Tsc{p})
}

func main() {
	p, err := New()
	if err != nil {
		fmt.Fprintln(os.Stderr, "tsc: the embedded adapter is refused:", err)
		os.Exit(2)
	}
	plugin.Serve(p)
}
