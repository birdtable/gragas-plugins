package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"path"
	"strconv"
	"strings"

	"github.com/birdtable/gragas-plugin-sdk/declarative"
	"github.com/birdtable/gragas-plugin-sdk/plugin"
	"github.com/birdtable/gragas-plugin-sdk/wire"
)

// noConfig is the config that is the tool's defaults: its version alone. The tool answers the same linter set for it
// as when it reads no file. Given a file by name the tool loads none without its version, so a project with no config
// is asked over this one document, written as JSON, which is YAML too.
const noConfig = "{\"version\": \"2\"}\n"

// presetStem is the name of the config a project has none of: the preset's own file, without its extension.
const presetStem = ".golangci"

// plug is the declarative plugin of the adapter with the knowledge of the tool that is code: the refusals of a config
// that loads code or is not read as the tool reads it, and the entries of the settings blocks of the file.
type plug struct {
	*declarative.Plugin
}

func newPlugin(adapter []byte) (*plug, error) {
	d, err := declarative.New(adapter)
	if err != nil {
		return nil, err
	}
	return &plug{d}, nil
}

// Plan, for the config read, holds the file to the refusals before anything is run, and asks the run over the tool's
// defaults when the project has no file. Every other plan is the declarative one.
func (p *plug) Plan(req wire.PlanRequest) (wire.PlanResponse, error) {
	if req.For != wire.ForConfig {
		return p.Plugin.Plan(req)
	}
	if len(req.Config) == 0 {
		name := presetStem + ".json"
		return wire.PlanResponse{Steps: []wire.Step{{Run: &wire.Run{
			Program: "golangci-lint",
			Argv:    []string{"linters", "--json", "-c", "{scratch}/" + name},
			Place:   []wire.File{{Path: name, Data: wire.Bytes{Data: []byte(noConfig)}}},
		}}}, Final: true}, nil
	}
	c := req.Config[0]
	data, ok := configData(req.Gathered, c)
	if !ok {
		// Over 1 MiB the engine sends no bytes: they are read in round 0, and the file is judged in the next.
		if req.Round == 0 {
			return wire.PlanResponse{Steps: []wire.Step{{Read: &wire.Read{Glob: c.Path}}}}, nil
		}
		return wire.PlanResponse{}, plugin.Unreadablef("/have", "the file %s was asked for and not given", c.Path)
	}
	if _, why := settingsOf(c.Path, data); why != "" {
		// The path is a JSON pointer into the request: the config entry for a format refused by its name, and its data
		// for a refusal by its content (C20).
		at := "/config/0/data"
		if !mappingFormat(path.Ext(c.Path)) {
			at = "/config/0"
		}
		return wire.PlanResponse{}, plugin.Refusedf(at, "%s", why)
	}
	if req.Round != 0 {
		// The declarative plan is one round: the run it plans is the second step of a read, so it is asked for as round 0.
		req.Round = 0
	}
	return p.Plugin.Plan(req)
}

// Preset is the declarative preset, asked with one entry for each rule of an entry, so a linter's comment in the list
// names every rule that binds it: the SDK's writer joins the rules of one key, and takes only the
// first rule of an entry. Each of the copies carries its entry's key, value, options, severity and trial, so the list and
// the settings are what the entry alone writes, and a note of an entry not shipped is one for each of its rules.
// A refusal at a copy points into a request the engine never sent, so its pointer is turned back to the entry the copy
// was made from.
func (p *plug) Preset(req wire.PresetRequest) (wire.PresetResponse, error) {
	each := req
	each.Entries = nil
	var from []int
	for i, e := range req.Entries {
		if len(e.Rules) == 0 {
			return wire.PresetResponse{}, plugin.Refusedf(fmt.Sprintf("/entries/%d/rules", i), "the entry of %s names no rule", e.Key)
		}
		for _, r := range e.Rules {
			one := e
			one.Rules = []string{r}
			each.Entries = append(each.Entries, one)
			from = append(from, i)
		}
	}
	resp, err := p.Plugin.Preset(each)
	var we *wire.Error
	if errors.As(err, &we) {
		we.Path = entryOf(we.Path, from)
	}
	return resp, err
}

// entryOf is a pointer into the copies of Preset as a pointer into the engine's request: /entries/<n> and what is below
// it name the entry copy n was made from. Any other pointer is the same in both.
func entryOf(at string, from []int) string {
	rest, ok := strings.CutPrefix(at, "/entries/")
	if !ok {
		return at
	}
	n, below, deeper := strings.Cut(rest, "/")
	i, err := strconv.Atoi(n)
	if err != nil || i < 0 || i >= len(from) || strconv.Itoa(i) != n {
		return at
	}
	out := "/entries/" + strconv.Itoa(from[i])
	if deeper {
		out += "/" + below
	}
	return out
}

// configData is the bytes of a config: those the engine gave, or those a read step found.
func configData(g wire.Gathered, c wire.Config) ([]byte, bool) {
	if c.Data != nil {
		return c.Data.Raw(), true
	}
	for _, r := range g.Have {
		if r.Kind != wire.KindRead {
			continue
		}
		for _, f := range r.Files {
			if f.Path == c.Path {
				return f.Data.Raw(), true
			}
		}
	}
	return nil, false
}

// settingsOf is the folded view of the config, or the words of why it is not given to the tool: its format, that it is
// no mapping, that two keys of it are one key to the tool or one is outside ASCII, or that it names a custom linter.
func settingsOf(file string, data []byte) (folded, string) {
	if ext := path.Ext(file); !mappingFormat(ext) {
		return nil, fmt.Sprintf("%s is read by golangci-lint as %s, a format this check does not read", file, strings.TrimPrefix(ext, "."))
	}
	root, err := document(data)
	if err != nil {
		return nil, fmt.Sprintf("%s cannot be read as a mapping: %v", file, err)
	}
	f, err := fold(root)
	if err != nil {
		return nil, err.Error()
	}
	return f, customLinters(f)
}

// mappingFormat is whether ext is the extension of a config whose document is parsed as the tool does: YAML, and JSON,
// which the YAML parser reads. The tool reads a file in other formats too (TOML, HCL, INI and more); one of those is
// not given to the tool.
func mappingFormat(ext string) bool { return ext == ".yml" || ext == ".yaml" || ext == ".json" }

// customLinters is the reason a config names a custom linter, "" when it names none. Anything under
// linters.settings.custom but an empty mapping or a null counts, so a shape the tool might still read as a linter is
// never passed to it.
func customLinters(f folded) string {
	const at = "linters.settings.custom"
	if below := f.firstBelow(at); below != "" {
		return "the config loads custom linters (" + below + ")"
	}
	switch f[at] {
	case nullLeaf, emptyLeaf:
		return ""
	}
	if !f.has(at) {
		return ""
	}
	return "the config has a " + at + " that is not an empty mapping"
}

// Entries are one for each linter the tool prints, on or off, and one for each settings block of the file under
// linters.settings, on, by its lower-case name. A linter and a settings block of one name are two entries, and the entries of a config with no run follow the same rule.
func (p *plug) Entries(req wire.EntriesRequest) (wire.EntriesResponse, error) {
	var out wire.EntriesResponse
	var printed []byte
	ran := false
	for _, r := range req.Have {
		if r.Kind == wire.KindRun {
			printed, ran = r.Stdout.Raw(), true
			break
		}
	}
	if !ran && len(req.Config) > 0 {
		return p.staticEntries(req)
	}
	lin, err := lintersOf(printed)
	if err != nil {
		return out, plugin.Unreadablef("/have", "%v", err)
	}
	out.Entries = lin
	if len(req.Config) == 0 {
		return out, nil
	}
	data, ok := configData(req.Gathered, req.Config[0])
	if !ok {
		return out, plugin.Unreadablef("/config/0", "the file %s was not given", req.Config[0].Path)
	}
	f, why := settingsOf(req.Config[0].Path, data)
	if why != "" {
		return out, plugin.Unreadablef("/config/0", "%s", why)
	}
	// A settings block that is a linter's own is that linter's entry already: the key stands once, and the
	// verdict is the linter's (on or off), as today's audit holds a key that is no linter by its block.
	linter := make(map[string]bool, len(lin))
	for _, e := range lin {
		linter[e.Key] = true
	}
	for _, name := range f.under("linters.settings") {
		if !linter[name] {
			out.Entries = append(out.Entries, wire.Entry{Key: name, On: true})
		}
	}
	return out, nil
}

// lintersOf reads what `golangci-lint linters --json` printed: one JSON document with nothing after it, an Enabled
// list, and no linter without a name.
func lintersOf(printed []byte) ([]wire.Entry, error) {
	dec := json.NewDecoder(bytes.NewReader(printed))
	var doc struct {
		Enabled  *[]struct{ Name string }
		Disabled []struct{ Name string }
	}
	if err := dec.Decode(&doc); err != nil {
		return nil, fmt.Errorf("the linters print is not one JSON document: %v", err)
	}
	if _, err := dec.Token(); err != io.EOF {
		return nil, fmt.Errorf("the linters print holds more than one document")
	}
	if doc.Enabled == nil {
		return nil, fmt.Errorf("the linters print has no Enabled list")
	}
	var out []wire.Entry
	for _, l := range *doc.Enabled {
		if l.Name == "" {
			return nil, fmt.Errorf("the linters print names a linter with no name")
		}
		out = append(out, wire.Entry{Key: l.Name, On: true})
	}
	for _, l := range doc.Disabled {
		if l.Name == "" {
			return nil, fmt.Errorf("the linters print names a linter with no name")
		}
		out = append(out, wire.Entry{Key: l.Name, On: false})
	}
	return out, nil
}

// staticEntries answers entries over a config alone, with no run of the tool (the entries of a preset file).
func (p *plug) staticEntries(req wire.EntriesRequest) (wire.EntriesResponse, error) {
	var out wire.EntriesResponse
	c := req.Config[0]
	data, ok := configData(req.Gathered, c)
	if !ok {
		return out, plugin.Unreadablef("/config/0", "the file %s was not given", c.Path)
	}
	f, why := settingsOf(c.Path, data)
	if why != "" {
		return out, plugin.Unreadablef("/config/0", "%s", why)
	}
	root, _ := document(data)
	out.Entries = staticEntries(root, f)
	return out, nil
}
