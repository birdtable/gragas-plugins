package main

import (
	"fmt"
	"regexp"

	"github.com/birdtable/gragas-plugin-sdk/plugin"
	"github.com/birdtable/gragas-plugin-sdk/wire"
)

// beyond matches an import, a dynamic import or a require of a file by a relative or absolute specifier. The plan places
// one config file in its scratch folder, so such a specifier names a file that is not there: the config reaches beyond
// its one file, and the plan refuses it rather than let the run fail on a path of the caller's tree.
var beyond = regexp.MustCompile(`(?:\bfrom|\bimport|\brequire)\s*\(?\s*["']((?:\.{1,2}/|/)[^"']*)["']`)

// refuseReachingConfig refuses a config whose content imports or requires a file beside it or above it. The refusal
// names the config's data, so gragas can say which file of the project held it.
func refuseReachingConfig(config []wire.Config) error {
	for i, f := range config {
		if f.Data == nil {
			continue
		}
		if m := beyond.FindStringSubmatch(f.Data.Text()); m != nil {
			return plugin.Refusedf(fmt.Sprintf("/config/%d/data/text", i), "the config file %q reaches beyond its one file: it imports %q, and the plan places only the config", f.Path, m[1])
		}
	}
	return nil
}
