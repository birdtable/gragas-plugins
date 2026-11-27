// Command eslint is the ESLint plugin of plugin contract 1: ESLint's adapter, a flat list of rules, served by the
// SDK's declarative package. Built for wasip1 it is plugins/eslint/<version>/plugin.wasm.
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

// probe is the one file a config read prints the config for: an empty file the plan places in the scratch folder. A
// config scoped to other paths prints none of those entries.
const probe = "probe.js"

// Eslint is the declarative plugin with the two things ESLint adds: the probe file a config read asks for, and the
// isolated level, the level of the embedded adapter today.
type Eslint struct{ *declarative.Plugin }

// Plan is the declarative plan, with the probe placed for a config read and the isolated level on every run.
func (e Eslint) Plan(req wire.PlanRequest) (wire.PlanResponse, error) {
	if err := refuseUnsafeConfig(req.Config); err != nil {
		return wire.PlanResponse{}, err
	}
	if err := refuseReachingConfig(req.Config); err != nil {
		return wire.PlanResponse{}, err
	}
	if req.For == wire.ForConfig {
		req.Fixtures = []string{probe}
	}
	resp, err := e.Plugin.Plan(req)
	if err != nil {
		return resp, err
	}
	for _, s := range resp.Steps {
		if s.Run == nil {
			continue
		}
		// Isolated is the level gragas runs the embedded eslint adapter at today (release-1,
		// internal/host/assets/adapters/eslint/1.1.0.yaml: config_loads_code: false). It is raised
		// once an adapter exists; the sandbox of this build reaches isolated only.
		s.Run.Level = wire.LevelIsolated
		if req.For == wire.ForConfig {
			s.Run.Place = []wire.File{{Path: probe, Data: wire.Bytes{Data: []byte{}}}}
		}
	}
	return resp, nil
}

// New reads the adapter embedded here.
func New() (plugin.Plugin, error) {
	p, err := declarative.New(adapter)
	if err != nil {
		return nil, err
	}
	return newGuard(Eslint{p})
}

func main() {
	p, err := New()
	if err != nil {
		fmt.Fprintln(os.Stderr, "eslint: the embedded adapter is refused:", err)
		os.Exit(2)
	}
	plugin.Serve(p)
}
