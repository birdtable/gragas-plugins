package main

import (
	"errors"
	"strings"
	"testing"

	"github.com/birdtable/gragas-plugin-sdk/wire"
)

func newTest(t *testing.T) *plug {
	t.Helper()
	p, err := newPlugin(adapter)
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func cfg(path, text string) wire.Config {
	return wire.Config{Path: path, Data: &wire.Bytes{Data: []byte(text)}}
}

func planConfig(p *plug, c ...wire.Config) (wire.PlanResponse, error) {
	return p.Plan(wire.PlanRequest{Gathered: wire.Gathered{ToolVersion: "2.15.0", Config: c}, For: wire.ForConfig, Target: "source"})
}

// TestRefusals holds the words of the refusals, each as the contract gives it, in their order.
func TestRefusals(t *testing.T) {
	for _, tc := range []struct{ name, file, text, want string }{
		{"toml", ".golangci.toml", "a = 1\n", ".golangci.toml is read by golangci-lint as toml, a format this check does not read"},
		{"not a mapping", ".golangci.yml", "- a\n- b\n", ".golangci.yml cannot be read as a mapping: the document is not a mapping"},
		{"fold", ".golangci.yml", "linters:\n  x: 1\nLinters:\n  y: 2\n", "two keys of the file are one key to the tool (linters)"},
		{"dotted fold", ".golangci.yml", "linters.a: 1\nlinters:\n  A: 2\n", "two keys of the file are one key to the tool (linters.a)"},
		{"not ascii", ".golangci.yml", "linters:\n  ſettings: {}\n", "the key \"ſettings\" is not ASCII, and the tool's fold of it is not known"},
		{"custom", ".golangci.yml", "linters:\n  settings:\n    custom:\n      mine:\n        type: module\n", "the config loads custom linters (linters.settings.custom.mine)"},
		{"custom folded", ".golangci.yml", "Linters:\n  Settings:\n    CUSTOM:\n      mine: {}\n", "the config loads custom linters (linters.settings.custom.mine)"},
		{"custom scalar", ".golangci.yml", "linters:\n  settings:\n    custom: yes\n", "the config has a linters.settings.custom that is not an empty mapping"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := planConfig(newTest(t), cfg(tc.file, tc.text))
			var we *wire.Error
			// A format refused by its name is at the entry; one refused by its content is at its data (C20).
			at := "/config/0/data"
			if tc.file == ".golangci.toml" {
				at = "/config/0"
			}
			if !errors.As(err, &we) || we.Code != wire.CodeRefused || we.Path != at {
				t.Fatalf("want a refusal at %s, got %v", at, err)
			}
			if !strings.Contains(we.Message, tc.want) {
				t.Errorf("message %q, want %q", we.Message, tc.want)
			}
		})
	}
}

func TestCustomEmptyOrNullIsRead(t *testing.T) {
	for _, text := range []string{"linters:\n  settings:\n    custom:\n", "linters:\n  settings:\n    custom: {}\n", "{\"linters\": {\"settings\": {\"custom\": null}}}\n"} {
		r, err := planConfig(newTest(t), cfg(".golangci.yml", text))
		if err != nil || len(r.Steps) != 1 || r.Steps[0].Run == nil {
			t.Errorf("%q: %v %v", text, r, err)
		}
	}
}

func TestNoConfigRunsOverTheDefaults(t *testing.T) {
	r, err := planConfig(newTest(t))
	if err != nil || len(r.Steps) != 1 || !r.Final {
		t.Fatalf("%v %v", r, err)
	}
	run := r.Steps[0].Run
	if got := strings.Join(run.Argv, " "); got != "linters --json -c {scratch}/.golangci.json" {
		t.Errorf("argv %q", got)
	}
	if len(run.Place) != 1 || run.Place[0].Path != ".golangci.json" || string(run.Place[0].Data.Data) != "{\"version\": \"2\"}\n" {
		t.Errorf("place %+v", run.Place)
	}
}

func TestBigConfigIsReadFirst(t *testing.T) {
	p := newTest(t)
	c := wire.Config{Path: ".golangci.yml"}
	r, err := p.Plan(wire.PlanRequest{Gathered: wire.Gathered{Config: []wire.Config{c}}, For: wire.ForConfig, Target: "source"})
	if err != nil || len(r.Steps) != 1 || r.Steps[0].Read == nil || r.Final {
		t.Fatalf("round 0: %v %v", r, err)
	}
	have := []wire.Result{{Round: 0, Step: 0, Kind: wire.KindRead, Files: []wire.File{{Path: ".golangci.yml", Data: wire.Bytes{Data: []byte("linters:\n  settings:\n    custom:\n      a: {}\n")}}}}}
	_, err = p.Plan(wire.PlanRequest{Gathered: wire.Gathered{Config: []wire.Config{c}, Have: have}, For: wire.ForConfig, Target: "source", Round: 1})
	var we *wire.Error
	if !errors.As(err, &we) || we.Code != wire.CodeRefused {
		t.Fatalf("round 1: %v", err)
	}
}

func TestEntries(t *testing.T) {
	out := wire.Bytes{Data: []byte(`{"Enabled":[{"Name":"govet"},{"Name":"errcheck"}],"Disabled":[{"Name":"revive"}]}`)}
	req := wire.EntriesRequest{Gathered: wire.Gathered{
		Config: []wire.Config{cfg(".golangci.yml", "linters:\n  settings:\n    Revive:\n      rules: []\n    errcheck:\n      check-blank: true\n")},
		Have:   []wire.Result{{Kind: wire.KindRun, Stdout: &out}},
	}, Target: "source"}
	r, err := newTest(t).Entries(req)
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, e := range r.Entries {
		got = append(got, e.Key+"="+map[bool]string{true: "on", false: "off"}[e.On])
	}
	// The blocks of errcheck and Revive are those linters' own keys, so each key stands once, as the linter's entry.
	if want := "govet=on errcheck=on revive=off"; strings.Join(got, " ") != want {
		t.Errorf("entries %q, want %q", strings.Join(got, " "), want)
	}
}

func TestLintersPrintRefusals(t *testing.T) {
	for name, printed := range map[string]string{
		"two documents": `{"Enabled":[]} {"Enabled":[]}`,
		"no Enabled":    `{"Disabled":[]}`,
		"no name":       `{"Enabled":[{"Name":""}]}`,
		"not json":      `golangci-lint has no config`,
	} {
		if _, err := lintersOf([]byte(printed)); err == nil {
			t.Errorf("%s: read", name)
		}
	}
}

func TestStandardIsTheToolsFive(t *testing.T) {
	if got, want := strings.Join(standardLinters(), " "), "errcheck govet ineffassign staticcheck unused"; got != want {
		t.Errorf("standard %q, want %q", got, want)
	}
}

// TestAPresetIsReadWithNoRun: with no run in have, default: standard stands for the five, the enable list adds its own,
// and a settings block is on, as gragas's resolve read a preset.
func TestAPresetIsReadWithNoRun(t *testing.T) {
	text := "version: \"2\"\nlinters:\n  default: standard\n  enable:\n    - revive\n    - govet\n  settings:\n    revive:\n      rules: []\n"
	r, err := newTest(t).Entries(wire.EntriesRequest{Gathered: wire.Gathered{Config: []wire.Config{cfg(".golangci.yml", text)}}, Target: "source"})
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, e := range r.Entries {
		got = append(got, e.Key)
	}
	if want := "errcheck govet ineffassign staticcheck unused revive revive"; strings.Join(got, " ") != want {
		t.Errorf("entries %q, want %q", strings.Join(got, " "), want)
	}
}

func staticKeys(t *testing.T, text string) string {
	t.Helper()
	r, err := newTest(t).Entries(wire.EntriesRequest{Gathered: wire.Gathered{Config: []wire.Config{cfg(".golangci.yml", text)}}, Target: "source"})
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, e := range r.Entries {
		got = append(got, e.Key)
	}
	return strings.Join(got, " ")
}

// TestDisableTakesALinterOut: linters.disable removes a linter the default or the enable list gave, by its exact name.
func TestDisableTakesALinterOut(t *testing.T) {
	got := staticKeys(t, "linters:\n  default: standard\n  enable: [revive]\n  disable: [errcheck, revive]\n")
	if want := "govet ineffassign staticcheck unused"; got != want {
		t.Errorf("entries %q, want %q", got, want)
	}
}

// TestOtherDefaultsGiveNoList: all, none and fast name no list here, so only the enable list stands.
func TestOtherDefaultsGiveNoList(t *testing.T) {
	for _, d := range []string{"all", "none", "fast"} {
		if got := staticKeys(t, "linters:\n  default: "+d+"\n  enable: [revive]\n"); got != "revive" {
			t.Errorf("default %s: entries %q, want revive", d, got)
		}
	}
}

// TestALinterAndItsSettingsAreTwoEntries: in both forms of entries.
func TestALinterAndItsSettingsAreTwoEntries(t *testing.T) {
	if got, want := staticKeys(t, "linters:\n  enable: [gosec]\n  settings:\n    gosec:\n      severity: low\n"), "gosec gosec"; got != want {
		t.Errorf("entries %q, want %q", got, want)
	}
}
