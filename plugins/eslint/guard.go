package main

import (
	"fmt"
	"path"
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
		// ESLint 10 reads flat config only: a legacy .eslintrc file is not a config it would load.
		if strings.HasPrefix(path.Base(f.Path), ".eslintrc") {
			return plugin.Refusedf(fmt.Sprintf("/config/%d/path", i), "the config file %q is a legacy eslintrc, which ESLint 10 does not read: use eslint.config.js", f.Path)
		}
	}
	return nil
}
