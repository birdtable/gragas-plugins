package main

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"

	"go.yaml.in/yaml/v3"
)

// TestManifestDigest holds plugin.yaml's wasm to the plugin.wasm beside it. The module is rebuilt, from this folder (the module root), with
//
//	GOTOOLCHAIN=go1.27.4 GOOS=wasip1 GOARCH=wasm go build -trimpath -buildvcs=false -ldflags=-buildid= -o 1.0.2/plugin.wasm .
//
// and the digest of the new file is written to plugin.yaml. -buildvcs=false is needed: without it the build stamps the
// commit and its dirty flag into the module, so the digest changes with the tree it was built in. The folder is the
// bundle's (manifest_test.go); a released folder keeps the .wasm and the digest it was released with.
func TestManifestDigest(t *testing.T) {
	data, err := os.ReadFile(filepath.Join(bundle, "plugin.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	var m struct {
		Wasm string `yaml:"wasm"`
	}
	if err := yaml.Unmarshal(data, &m); err != nil {
		t.Fatal(err)
	}
	wasm, err := os.ReadFile(filepath.Join(bundle, "plugin.wasm"))
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(wasm)
	if want := "sha256:" + hex.EncodeToString(sum[:]); m.Wasm != want {
		t.Errorf("plugin.yaml names wasm %s, plugin.wasm is %s", m.Wasm, want)
	}
}
