package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"go.yaml.in/yaml/v3"

	"github.com/birdtable/gragas-plugin-sdk/contract"
)

// bundle is the version of the bundle this source builds, plugins/golangci-lint/<bundle>/: the newest folder. A
// released folder never changes (gate/ledger.sh), so a change to the plugin is the next version's folder, and the
// tests of the module read that one.
const bundle = "1.0.2"

// TestTheAdapterAndTheManifestAreTheBundlesVersion: the adapter the plugin embeds and the manifest beside the .wasm both
// say the version of the folder. Risk: a folder whose plugin calls itself another version.
func TestTheAdapterAndTheManifestAreTheBundlesVersion(t *testing.T) {
	for _, f := range []string{"adapter.yaml", filepath.Join(bundle, "plugin.yaml")} {
		data, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		var m struct {
			Version string `yaml:"version"`
		}
		if err := yaml.Unmarshal(data, &m); err != nil {
			t.Fatal(err)
		}
		if m.Version != bundle {
			t.Errorf("%s says version %q, and the bundle is %s", f, m.Version, bundle)
		}
	}
}

// TestManifestIsTheSchemasShape holds plugin.yaml to the manifest schema's own top level: every required key is there
// and no other key is (the schema is strict). The full check of the file is `gragas plugin test`'s.
func TestManifestIsTheSchemasShape(t *testing.T) {
	data, err := os.ReadFile(filepath.Join(bundle, "plugin.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	if err := yaml.Unmarshal(data, &m); err != nil {
		t.Fatal(err)
	}
	var schema struct {
		Required   []string       `json:"required"`
		Properties map[string]any `json:"properties"`
	}
	if err := json.Unmarshal(contract.Manifest(), &schema); err != nil {
		t.Fatal(err)
	}
	for _, k := range schema.Required {
		if _, ok := m[k]; !ok {
			t.Errorf("plugin.yaml has no %s", k)
		}
	}
	for k := range m {
		if _, ok := schema.Properties[k]; !ok {
			t.Errorf("plugin.yaml has the key %s, which the manifest schema does not know", k)
		}
	}
	if m["tool"] != "golangci-lint" || !slices.Equal(toStrings(m["provides"]), []string{"plan", "entries", "findings", "rank", "preset"}) {
		t.Errorf("tool or provides: %v %v", m["tool"], m["provides"])
	}
}

func toStrings(v any) []string {
	var out []string
	for _, e := range v.([]any) {
		out = append(out, e.(string))
	}
	return out
}
