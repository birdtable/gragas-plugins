package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/birdtable/gragas-plugin-sdk/plugin"
)

// TestPresetGolden: the preset answer of case 11-preset, written as gragas prints a preset, is byte for byte the golden taken
// from gragas on release-1 (internal/core/api/testdata/presets/golangci-lint.golden), less the line gragas adds for the install
// hint, which is not the plugin's.
func TestPresetGolden(t *testing.T) {
	testdata := filepath.Join(bundle, "testdata")
	req, err := os.ReadFile(filepath.Join(testdata, "cases", "11-preset", "request.json"))
	if err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	if code := plugin.ServeIO(bytes.NewReader(req), &out, newTest(t)); code != 0 {
		t.Fatalf("ServeIO %d", code)
	}
	var resp struct {
		Ok struct {
			Files []struct{ Path, Text string }
			Notes []string
		}
	}
	if err := json.Unmarshal(out.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	var got strings.Builder
	for _, f := range resp.Ok.Files {
		got.WriteString("=== " + f.Path + " (golangci-lint, copy-once false)\n" + f.Text)
	}
	for _, n := range resp.Ok.Notes {
		got.WriteString("note: " + n + "\n")
	}
	want, err := os.ReadFile(filepath.Join(testdata, "golden", "preset.golden"))
	if err != nil {
		t.Fatal(err)
	}
	if got.String() != string(want) {
		t.Fatalf("the preset differs from the golden\n got: %q\nwant: %q", got.String(), want)
	}
}
