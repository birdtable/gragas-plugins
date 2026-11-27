package main

import (
	"encoding/json"
	"os"
	"testing"

	"go.yaml.in/yaml/v3"

	"github.com/birdtable/gragas-plugin-sdk/contract"
	"github.com/birdtable/gragas-plugin-sdk/declarative"
	"github.com/birdtable/gragas-plugin-sdk/wire"
)

func newTest(t *testing.T) *declarative.Plugin {
	t.Helper()
	p, err := declarative.New(adapter)
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func file(path, text string) wire.File { return wire.File{Path: path, Data: wire.Bytes{Data: []byte(text)}} }

func read(round, step int, files ...wire.File) wire.Result {
	return wire.Result{Round: round, Step: step, Kind: wire.KindRead, Files: append([]wire.File{}, files...)}
}

func plan(t *testing.T, p *declarative.Plugin, round int, have ...wire.Result) string {
	t.Helper()
	got, err := p.Plan(wire.PlanRequest{Gathered: wire.Gathered{ToolVersion: "0.51.0", Config: []wire.Config{}, Have: have},
		For: wire.ForConfig, Target: "source", Round: round})
	if err != nil {
		t.Fatalf("round %d: %v", round, err)
	}
	b, _ := json.Marshal(got)
	return string(b)
}

// TestTheConfigIsReadInTwoRounds: round 0 asks for sgconfig.yml, not final; round 1, with the config read, asks for the
// rule files of each folder it names, final.
func TestTheConfigIsReadInTwoRounds(t *testing.T) {
	p := newTest(t)
	if got, want := plan(t, p, 0), `{"steps":[{"kind":"read","glob":"sgconfig.yml"}],"final":false}`; got != want {
		t.Errorf("round 0: %s, want %s", got, want)
	}
	cfg := read(0, 0, file("sgconfig.yml", "ruleDirs:\n  - rules\n"))
	want := `{"steps":[{"kind":"read","glob":"rules/**/*.yml"},{"kind":"read","glob":"rules/**/*.yaml"},{"kind":"read","glob":"rules/**/.*ignore"}],"final":true}`
	if got := plan(t, p, 1, cfg); got != want {
		t.Errorf("round 1: %s, want %s", got, want)
	}
}

// TestEachRuleFileIsOneEntry: the id is the key, a rule file with no severity is a hint (info), and off is off.
func TestEachRuleFileIsOneEntry(t *testing.T) {
	p := newTest(t)
	got, err := p.Entries(wire.EntriesRequest{Gathered: wire.Gathered{ToolVersion: "0.51.0", Config: []wire.Config{}, Have: []wire.Result{
		read(0, 0, file("sgconfig.yml", "ruleDirs:\n  - rules\n")),
		read(1, 0, file("rules/a.yml", "id: no-eval\nlanguage: js\nseverity: error\nrule:\n  pattern: eval($A)\n"),
			file("rules/b.yml", "id: quiet\nlanguage: js\nseverity: \"off\"\nrule:\n  pattern: x\n"),
			file("rules/c.yml", "id: no-var\nlanguage: js\nrule:\n  pattern: var $A\n")),
	}}, Target: "source"})
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(got)
	// The language at the top of a rule file is the entry's option (options_top).
	const want = `{"entries":[{"key":"no-eval","on":true,"severity":"error","value":{"pattern":"eval($A)"},"options":{"language":"js"}},{"key":"quiet","on":false,"value":{"pattern":"x"},"options":{"language":"js"}},{"key":"no-var","on":true,"severity":"info","value":{"pattern":"var $A"},"options":{"language":"js"}}]}`
	if string(b) != want {
		t.Errorf("entries\n%s\nwant\n%s", b, want)
	}
}

// TestAnIgnoreFileIsRefused: a folder that holds an .ignore file is read as the tool would skip files by it, which this
// plugin does not follow, so the read is not made.
func TestAnIgnoreFileIsRefused(t *testing.T) {
	p := newTest(t)
	_, err := p.Entries(wire.EntriesRequest{Gathered: wire.Gathered{ToolVersion: "0.51.0", Config: []wire.Config{}, Have: []wire.Result{
		read(0, 0, file("sgconfig.yml", "ruleDirs:\n  - rules\n")),
		read(1, 2, file("rules/.gitignore", "x\n")),
	}}, Target: "source"})
	if err == nil {
		t.Fatal("an .ignore file was read")
	}
}

// TestManifestIsTheSchemasShape holds plugin.yaml to the manifest schema's top level.
func TestManifestIsTheSchemasShape(t *testing.T) {
	data, err := os.ReadFile("1.1.1/plugin.yaml")
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
}
