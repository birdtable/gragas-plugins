package main

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/birdtable/gragas-plugin-sdk/wire"
)

const presetSettings = "version: \"2\"\nlinters:\n  default: standard\n  enable:\n    # generated:linters:begin\n    # generated:linters:end\n"

func preset(t *testing.T, entries ...wire.PresetEntry) (wire.PresetResponse, error) {
	t.Helper()
	return newTest(t).Preset(wire.PresetRequest{ToolVersion: "2.15.0", Mark: "gragas:generated", Inputs: []wire.File{settings(presetSettings)}, Entries: entries})
}

// listOf is the lines of the preset's generated list, between the markers.
func listOf(t *testing.T, r wire.PresetResponse) []string {
	t.Helper()
	if len(r.Files) != 1 {
		t.Fatalf("files %d, want 1", len(r.Files))
	}
	_, after, _ := strings.Cut(r.Files[0].Text, "# generated:linters:begin\n")
	list, _, _ := strings.Cut(after, "    # generated:linters:end")
	var out []string
	for _, l := range strings.Split(strings.TrimSpace(list), "\n") {
		out = append(out, strings.TrimSpace(l))
	}
	return out
}

// A linter bound by several rules names every one of them, in the SDK's order, whether they come in one entry or in
// two. The six are depguard's in gragas's committed .golangci.yml. Risk: the trace comment of
// depguard naming one rule of six, so a reader of the preset, and the file it is held to, lose the other five.
func TestALinterNamesEveryRuleThatBindsIt(t *testing.T) {
	r, err := preset(t,
		wire.PresetEntry{Key: "depguard", Target: "source", Severity: wire.SeverityError, Rules: []string{"tests.doubles.2", "arch.shared.7", "go.style.5", "arch.ports.11"}},
		wire.PresetEntry{Key: "errcheck", Target: "source", Severity: wire.SeverityError, Rules: []string{"go.err.1"}},
		wire.PresetEntry{Key: "depguard", Target: "source", Severity: wire.SeverityError, Rules: []string{"cli.look.1", "arch.ports.24"}},
	)
	if err != nil {
		t.Fatal(err)
	}
	got := strings.Join(listOf(t, r), "\n")
	want := "- depguard # arch.ports.11, arch.ports.24, arch.shared.7, cli.look.1, go.style.5, tests.doubles.2\n- errcheck # go.err.1"
	if got != want {
		t.Errorf("list\n%s\nwant\n%s", got, want)
	}
}

// An entry not shipped is noted once for each of its rules: each rule is told it is not written.
func TestAnEntryNotShippedIsNotedForEachRule(t *testing.T) {
	r, err := preset(t,
		wire.PresetEntry{Key: "errcheck", Target: "source", Severity: wire.SeverityError, Rules: []string{"go.err.1"}},
		wire.PresetEntry{Key: "lychee", Target: "docs", Severity: wire.SeverityError, Rules: []string{"docs.links.2", "docs.links.1"}},
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(r.Notes) != 2 || !strings.HasPrefix(r.Notes[0], "docs.links.1: ") || !strings.HasPrefix(r.Notes[1], "docs.links.2: ") {
		t.Errorf("notes %q, want one for docs.links.1 and one for docs.links.2", r.Notes)
	}
}

// A refusal points at the entry as the engine sent it, though the SDK was asked with one copy of it for each rule.
// Risk: a refusal at /entries/3 for a request of two entries, which the engine cannot show the person.
func TestARefusalPointsAtTheEnginesEntry(t *testing.T) {
	_, err := preset(t,
		wire.PresetEntry{Key: "depguard", Target: "source", Severity: wire.SeverityError, Rules: []string{"arch.ports.11", "arch.ports.24", "arch.shared.7"}},
		wire.PresetEntry{Key: "errcheck", Target: "source", Severity: wire.SeverityError, Options: json.RawMessage(`[1]`), Rules: []string{"go.err.1", "go.err.3"}},
	)
	var we *wire.Error
	if !errors.As(err, &we) || we.Code != wire.CodeRefused || we.Path != "/entries/1/options" {
		t.Fatalf("want a refusal at /entries/1/options, got %v", err)
	}
}

// An entry that names no rule is refused at its rules: no copy of it can be made, and the SDK takes an entry's first.
func TestAnEntryWithNoRuleIsRefused(t *testing.T) {
	_, err := preset(t,
		wire.PresetEntry{Key: "errcheck", Target: "source", Severity: wire.SeverityError, Rules: []string{"go.err.1"}},
		wire.PresetEntry{Key: "govet", Target: "source", Severity: wire.SeverityError},
	)
	var we *wire.Error
	if !errors.As(err, &we) || we.Code != wire.CodeRefused || we.Path != "/entries/1/rules" {
		t.Fatalf("want a refusal at /entries/1/rules, got %v", err)
	}
}

func TestEntryOfTurnsACopysPointerBack(t *testing.T) {
	from := []int{0, 0, 0, 1, 1}
	for at, want := range map[string]string{
		"/entries/0":          "/entries/0",
		"/entries/2/options":  "/entries/0/options",
		"/entries/3":          "/entries/1",
		"/entries/4/value/a":  "/entries/1/value/a",
		"/entries/4/":         "/entries/1/",
		"/entries/5/options":  "/entries/5/options",
		"/entries/04/options": "/entries/04/options",
		"/entries/x":          "/entries/x",
		"/inputs/0":           "/inputs/0",
		"/mark":               "/mark",
		"":                    "",
	} {
		if got := entryOf(at, from); got != want {
			t.Errorf("entryOf(%q) = %q, want %q", at, got, want)
		}
	}
}
