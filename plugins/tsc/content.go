package main

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/birdtable/gragas-plugin-sdk/plugin"
	"github.com/birdtable/gragas-plugin-sdk/wire"
)

// refuseReachingConfig refuses a config whose content reaches beyond its one file: an extends of a file path (the plan
// places only the config, so the base it names is not there), a references list (each entry is another project), or a
// compiler plugin (a language-service plugin is code the run would load). An extends of a package name is the wiring
// the plugin writes itself and is let through. The refusal names the config's data, so gragas can say which file of
// the project held it. A config that is not plain JSON is not read here: tsc reads it, and says what it finds.
func refuseReachingConfig(config []wire.Config) error {
	for i, f := range config {
		if f.Data == nil {
			continue
		}
		var cfg struct {
			Extends         json.RawMessage `json:"extends"`
			References      json.RawMessage `json:"references"`
			CompilerOptions struct {
				Plugins json.RawMessage `json:"plugins"`
			} `json:"compilerOptions"`
		}
		if json.Unmarshal(f.Data.Raw(), &cfg) != nil {
			continue
		}
		at := fmt.Sprintf("/config/%d/data/text", i)
		var one string
		var many []string
		if json.Unmarshal(cfg.Extends, &one) == nil {
			many = []string{one}
		} else {
			_ = json.Unmarshal(cfg.Extends, &many)
		}
		for _, e := range many {
			if strings.HasPrefix(e, ".") || strings.HasPrefix(e, "/") {
				return plugin.Refusedf(at, "the config file %q reaches beyond its one file: it extends %q, and the plan places only the config", f.Path, e)
			}
		}
		if len(cfg.References) > 0 && string(cfg.References) != "null" {
			return plugin.Refusedf(at, "the config file %q reaches beyond its one file: it references other projects, and the plan places only the config", f.Path)
		}
		if len(cfg.CompilerOptions.Plugins) > 0 && string(cfg.CompilerOptions.Plugins) != "null" {
			return plugin.Refusedf(at, "the config file %q names compiler plugins, which are code the run would load", f.Path)
		}
	}
	return nil
}
