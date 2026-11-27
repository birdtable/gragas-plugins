package main

import (
	_ "embed"
	"strings"

	"go.yaml.in/yaml/v3"

	"github.com/birdtable/gragas-plugin-sdk/wire"
)

// standard.yaml is the knowledge of the tool that was gragas's `standardLinters`: the linters golangci-lint v2 runs
// when a config says `linters.default: standard`. It is data of the plugin, so gragas's Go names no tool.
//
//go:embed standard.yaml
var standardData []byte

// standardLinters is the list of standard.yaml.
func standardLinters() []string {
	var d struct {
		Standard []string `yaml:"standard"`
	}
	if err := yaml.Unmarshal(standardData, &d); err != nil {
		panic(err)
	}
	return d.Standard
}

// staticEntries are the entries of a config read with no run: a preset is asked what it holds without the tool being
// started. linters.default of all, none or fast names no list here: only standard does, so those give the enable list
// alone (a choice, held by TestOtherDefaultsGiveNoList). A linter is on when the config enables it in linters.enable, or when linters.default is standard and it is
// one of the standard five; a block under linters.settings is on too.
func staticEntries(root *yaml.Node, f folded) []wire.Entry {
	var out []wire.Entry
	seen := map[string]bool{}
	add := func(k string) {
		if !seen[k] {
			seen[k] = true
			out = append(out, wire.Entry{Key: k, On: true})
		}
	}
	if d := valueAt(root, []string{"linters", "default"}); d != nil && d.Kind == yaml.ScalarNode && strings.EqualFold(d.Value, "standard") {
		for _, k := range standardLinters() {
			add(k)
		}
	}
	if en := valueAt(root, []string{"linters", "enable"}); en != nil && en.Kind == yaml.SequenceNode {
		for _, e := range en.Content {
			if e.Kind == yaml.ScalarNode && e.Value != "" {
				add(e.Value)
			}
		}
	}
	// linters.disable takes a linter out, by its exact name, as the tool compares it.
	if dis := valueAt(root, []string{"linters", "disable"}); dis != nil && dis.Kind == yaml.SequenceNode {
		off := map[string]bool{}
		for _, e := range dis.Content {
			if e.Kind == yaml.ScalarNode {
				off[e.Value] = true
			}
		}
		kept := out[:0]
		for _, e := range out {
			if !off[e.Key] {
				kept = append(kept, e)
			}
		}
		out = kept
	}
	// A settings block is its own entry, as in the run form: a linter and a block of one name are two entries.
	for _, name := range f.under("linters.settings") {
		out = append(out, wire.Entry{Key: name, On: true})
	}
	return out
}
