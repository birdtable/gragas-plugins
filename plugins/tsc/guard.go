package main

import (
	"fmt"
	"strings"

	"github.com/birdtable/gragas-plugin-sdk/plugin"
	"github.com/birdtable/gragas-plugin-sdk/wire"
)

// refuseUnsafeConfig refuses a request whose config names a path the plan would place a file at outside its scratch
// folder: an absolute path, a backslash, an empty segment, or a segment that is . or .. . The refusal names the path's
// pointer, so gragas can say which file of the project it was.
func refuseUnsafeConfig(config []wire.Config) error {
	for i, f := range config {
		bad := f.Path == "" || strings.HasPrefix(f.Path, "/") || strings.ContainsAny(f.Path, "\\\x00")
		for _, seg := range strings.Split(f.Path, "/") {
			bad = bad || seg == "" || seg == "." || seg == ".."
		}
		if bad {
			return plugin.Refusedf(fmt.Sprintf("/config/%d/path", i), "the config path %q is not a plain relative path inside the project", f.Path)
		}
		// tsc reads a project from a JSON file: a config file of another kind is not one it can read.
		if !strings.HasSuffix(f.Path, ".json") {
			return plugin.Refusedf(fmt.Sprintf("/config/%d/path", i), "the config file %q is not JSON: tsc reads a tsconfig.json", f.Path)
		}
	}
	return nil
}
