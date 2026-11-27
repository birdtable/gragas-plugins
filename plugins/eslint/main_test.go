package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/birdtable/gragas-plugin-sdk/plugin"
)

const bundle = "1.0.1"

// answer is what the plugin says to one request: the same ServeIO the wasm module runs on its stdin and stdout.
func answer(t *testing.T, request []byte) []byte {
	t.Helper()
	p, err := New()
	if err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	plugin.ServeIO(bytes.NewReader(request), &out, p)
	return out.Bytes()
}

func decode(t *testing.T, b []byte) any {
	t.Helper()
	var v any
	if err := json.Unmarshal(b, &v); err != nil {
		t.Fatalf("not JSON: %v: %s", err, b)
	}
	return v
}

// TestCases replays each testdata case: the response is the one committed, a second run gives the same bytes, and a
// field the contract does not know in the request changes nothing.
func TestCases(t *testing.T) {
	dirs, err := filepath.Glob(filepath.Join(bundle, "testdata", "cases", "*"))
	if err != nil || len(dirs) == 0 {
		t.Fatalf("no cases (%v)", err)
	}
	for _, d := range dirs {
		t.Run(filepath.Base(d), func(t *testing.T) {
			req, err := os.ReadFile(filepath.Join(d, "request.json"))
			if err != nil {
				t.Fatal(err)
			}
			want, err := os.ReadFile(filepath.Join(d, "response.json"))
			if err != nil {
				t.Fatal(err)
			}
			got := answer(t, req)
			if !reflect.DeepEqual(decode(t, got), decode(t, want)) {
				t.Fatalf("response differs\n got: %s\nwant: %s", got, want)
			}
			if again := answer(t, req); !bytes.Equal(got, again) {
				t.Fatalf("a second run gave other bytes\n first: %s\nsecond: %s", got, again)
			}
			var env map[string]any
			if err := json.Unmarshal(req, &env); err != nil {
				t.Fatal(err)
			}
			env["unknown_extra"] = true
			if body, ok := env["body"].(map[string]any); ok {
				body["unknown_extra"] = true
			}
			extra, _ := json.Marshal(env)
			if more := answer(t, extra); !bytes.Equal(got, more) {
				t.Fatalf("an unknown field changed the answer\n plain: %s\n extra: %s", got, more)
			}
		})
	}
}

// TestManifestDigest: the manifest's wasm digest is the one of the plugin.wasm beside it.
func TestManifestDigest(t *testing.T) {
	wasm, err := os.ReadFile(filepath.Join(bundle, "plugin.wasm"))
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(wasm)
	want := "wasm: sha256:" + hex.EncodeToString(sum[:])
	man, err := os.ReadFile(filepath.Join(bundle, "plugin.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(man), "\n"+want+"\n") {
		t.Fatalf("plugin.yaml does not carry %q: rebuild plugin.wasm (see README.md) and write its digest", want)
	}
}

// TestPresetGolden: the preset answer of case 8, written as gragas prints a preset, is byte for byte the golden taken
// from gragas on release-1 (internal/core/api/testdata/presets/eslint.golden), less the line gragas adds for the install
// hint, which is not the plugin's.
func TestPresetGolden(t *testing.T) {
	req, err := os.ReadFile(filepath.Join(bundle, "testdata", "cases", "8-preset", "request.json"))
	if err != nil {
		t.Fatal(err)
	}
	var resp struct {
		Ok struct {
			Files []struct{ Path, Text string }
			Notes []string
		}
	}
	if err := json.Unmarshal(answer(t, req), &resp); err != nil {
		t.Fatal(err)
	}
	var got strings.Builder
	for _, f := range resp.Ok.Files {
		got.WriteString("=== " + f.Path + " (eslint, copy-once false)\n" + f.Text)
	}
	for _, n := range resp.Ok.Notes {
		got.WriteString("note: " + n + "\n")
	}
	want, err := os.ReadFile(filepath.Join(bundle, "testdata", "golden", "preset.golden"))
	if err != nil {
		t.Fatal(err)
	}
	if got.String() != string(want) {
		t.Fatalf("the preset differs from the golden\n got: %q\nwant: %q", got.String(), want)
	}
}
