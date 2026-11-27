package main

import (
	"testing"

	"github.com/birdtable/gragas-plugin-sdk/wire"
)

// TestASettingsBlockOfALinterIsNotASecondEntry: the key of a linter and the block of its settings are one key, and the
// entry is the linter's, on or off. A block that is no linter's keeps its own entry, in lower case.
// Risk: the plugin answers each twice, the SDK refuses the answer as a bug ("the key is given twice"), and the audit of
// any config that tunes a linter it names (revive, say) ends in an error in place of a verdict.
func TestASettingsBlockOfALinterIsNotASecondEntry(t *testing.T) {
	run := wire.Result{Kind: wire.KindRun, Stdout: &wire.Bytes{Data: []byte(linters)}, Exit: new(int), Files: []wire.File{}}
	cfgText := "linters:\n  settings:\n    Revive:\n      rules: []\n    Mine:\n      a: 1\n"
	got, err := newTest(t).Entries(wire.EntriesRequest{Gathered: gathered([]wire.Result{run}, cfg(".golangci.yml", cfgText)), Target: "source"})
	if err != nil {
		t.Fatal(err)
	}
	seen := map[string]bool{}
	for _, e := range got.Entries {
		if seen[e.Key] {
			t.Errorf("the key %q is given twice", e.Key)
		}
		seen[e.Key] = e.On
	}
	if on, ok := seen["revive"]; !ok || on {
		t.Errorf("revive is the disabled linter's entry (on false), got on=%v present=%v", on, ok)
	}
	if on, ok := seen["mine"]; !ok || !on {
		t.Errorf("mine is a settings block of no linter, and holds on, got on=%v present=%v", on, ok)
	}
}
