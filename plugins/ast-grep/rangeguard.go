package main

import (
	"github.com/birdtable/gragas-plugin-sdk/declarative"
	"github.com/birdtable/gragas-plugin-sdk/plugin"
	"github.com/birdtable/gragas-plugin-sdk/wire"
)

// toolVersions is plugin.yaml's tool_versions: a request for a tool version outside it answers unsupported (check
// C16). A test holds it to the adapter's and the manifest's.
const toolVersions = ">=0.51.0 <0.52.0"

// guard answers unsupported for a tool version outside the range, and passes every other request on.
type guard struct {
	plugin.Plugin
	in func(version string) error
}

func newGuard(p plugin.Plugin) (guard, error) {
	r, err := declarative.ParseRange(toolVersions)
	if err != nil {
		return guard{}, err
	}
	return guard{Plugin: p, in: func(v string) error {
		ok, err := declarative.InRange(r, v)
		if err != nil {
			return plugin.Unsupportedf("the tool version %q is not major.minor.patch", v)
		}
		if !ok {
			return plugin.Unsupportedf("this plugin serves ast-grep %s, and the request is for %s", toolVersions, v)
		}
		return nil
	}}, nil
}

func (g guard) Plan(r wire.PlanRequest) (wire.PlanResponse, error) {
	if err := g.in(r.ToolVersion); err != nil {
		return wire.PlanResponse{}, err
	}
	return g.Plugin.Plan(r)
}

func (g guard) Entries(r wire.EntriesRequest) (wire.EntriesResponse, error) {
	if err := g.in(r.ToolVersion); err != nil {
		return wire.EntriesResponse{}, err
	}
	return g.Plugin.Entries(r)
}

func (g guard) Findings(r wire.FindingsRequest) (wire.FindingsResponse, error) {
	if err := g.in(r.ToolVersion); err != nil {
		return wire.FindingsResponse{}, err
	}
	return g.Plugin.Findings(r)
}

// Rank is not served: a rule file's value is a rule, a mapping no order ranks, and the adapter holds no scale, so the
// only answers would be same and unknown. An operation the manifest does not provide answers unsupported.
func (g guard) Rank(wire.RankRequest) (wire.RankResponse, error) {
	return wire.RankResponse{}, plugin.Unsupportedf("this plugin ranks no values: a rule file's value is a rule, which no order ranks")
}

func (g guard) Preset(r wire.PresetRequest) (wire.PresetResponse, error) {
	if err := g.in(r.ToolVersion); err != nil {
		return wire.PresetResponse{}, err
	}
	return g.Plugin.Preset(r)
}
