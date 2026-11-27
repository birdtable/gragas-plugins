package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"os"
	"path/filepath"
	"testing"

	"github.com/birdtable/gragas-plugin-sdk/plugin"
	"github.com/birdtable/gragas-plugin-sdk/wire"
)

var update = flag.Bool("update", false, "write testdata/cases from the plugin's answers; a person reads the diff")

// kase is one case of testdata/cases: a request, and the response the plugin gives to it. Its role is read from the
// response: an ok is a case the plugin serves, an error is one it refuses.
type kase struct {
	name, op string
	body     any
}

// copyOnce is the mark gragas hands an adapter with no extends: it writes the file once and leaves it to the project.
const copyOnce = "Written once by gragas from the rulebook. It is yours to edit: gragas does not write it again."

func gathered(have ...wire.Result) wire.Gathered {
	return wire.Gathered{ToolVersion: "0.51.0", Config: []wire.Config{}, Have: append([]wire.Result{}, have...)}
}

func cases() []kase {
	sg := read(0, 0, file("sgconfig.yml", "ruleDirs:\n  - rules\n"))
	rules := read(1, 0,
		file("rules/a.yml", "id: no-eval\nlanguage: js\nseverity: error\nrule:\n  pattern: eval($A)\n"),
		file("rules/b.yml", "id: quiet\nlanguage: js\nseverity: \"off\"\nrule:\n  pattern: x\n"),
		file("rules/c.yml", "id: no-var\nlanguage: js\nrule:\n  pattern: var $A\n"))
	pl := func(round int, g wire.Gathered) wire.PlanRequest {
		return wire.PlanRequest{Gathered: g, For: wire.ForConfig, Target: "source", Round: round}
	}
	return []kase{
		{"5-plan", "plan", pl(0, gathered())},
		{"6-plan", "plan", pl(1, gathered(sg))},
		{"9-entries", "entries", wire.EntriesRequest{Gathered: gathered(sg, rules), Target: "source"}},
		{"7-plan", "plan", wire.PlanRequest{Gathered: gathered(sg, rules), For: wire.ForRun, Target: "source", Round: 0, Fixtures: []string{"src/app.js"}}},
		{"8-plan", "plan", pl(0, wire.Gathered{ToolVersion: "0.51.0", Config: []wire.Config{{Path: "sgconfig.yml", Data: &wire.Bytes{Data: []byte("ruleDirs:\n  - ../outside\n")}}}, Have: []wire.Result{}})},
		{"11-preset", "preset", wire.PresetRequest{ToolVersion: "0.51.0", Mark: copyOnce, Inputs: []wire.File{}, Entries: []wire.PresetEntry{
			{Key: "no-console", Target: "source", Severity: wire.SeverityError, Value: json.RawMessage(`{"pattern":"console.log($A)"}`), Rules: []string{"arch.pat.1"}},
			{Key: "no-eval", Target: "source", Severity: wire.SeverityWarning, Value: json.RawMessage(`{"pattern":"eval($A)"}`), Trial: true, Rules: []string{"arch.pat.2"}}}}},
		{"12-preset", "preset", wire.PresetRequest{ToolVersion: "0.51.0", Mark: "gragas:generated", Inputs: []wire.File{}, Entries: []wire.PresetEntry{
			{Key: "no-eval", Target: "source", Severity: wire.SeverityError, Value: json.RawMessage(`{"pattern":"eval($A)"}`), Options: json.RawMessage(`[1]`), Rules: []string{"js.eval.1"}}}}},
		{"10-entries", "entries", wire.EntriesRequest{Gathered: gathered(sg, read(1, 2, file("rules/.gitignore", "x\n"))), Target: "source"}},
	}
}

func envelope(t *testing.T, k kase) []byte {
	t.Helper()
	body, err := json.Marshal(k.body)
	if err != nil {
		t.Fatal(err)
	}
	b, err := json.MarshalIndent(wire.Request{Contract: 1, Features: []string{}, Op: k.op, Body: body}, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	return append(b, '\n')
}

// TestCases serves each request of testdata/cases and holds the plugin's answer to the response beside it.
func TestCases(t *testing.T) {
	for _, k := range cases() {
		t.Run(k.name, func(t *testing.T) {
			req := envelope(t, k)
			var out bytes.Buffer
			if code := plugin.ServeIO(bytes.NewReader(req), &out, newTest(t)); code != 0 {
				t.Fatalf("ServeIO %d", code)
			}
			var pretty bytes.Buffer
			if err := json.Indent(&pretty, bytes.TrimSpace(out.Bytes()), "", "  "); err != nil {
				t.Fatal(err)
			}
			pretty.WriteByte('\n')
			dir := filepath.Join("1.1.1", "testdata", "cases", k.name)
			if *update {
				if err := os.MkdirAll(dir, 0o755); err != nil {
					t.Fatal(err)
				}
				for f, b := range map[string][]byte{"request.json": req, "response.json": pretty.Bytes()} {
					if err := os.WriteFile(filepath.Join(dir, f), b, 0o644); err != nil {
						t.Fatal(err)
					}
				}
				return
			}
			for f, b := range map[string][]byte{"request.json": req, "response.json": pretty.Bytes()} {
				want, err := os.ReadFile(filepath.Join(dir, f))
				if err != nil {
					t.Fatal(err)
				}
				if !bytes.Equal(want, b) {
					t.Errorf("%s/%s differs:\n%s\nwant\n%s", k.name, f, b, want)
				}
			}
		})
	}
}
