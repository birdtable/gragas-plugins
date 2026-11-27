package main

import (
	"fmt"
	"sort"
	"strings"

	"go.yaml.in/yaml/v3"
)

// maxDepth is how deep a config may nest before it is refused, as the reader of the engine's own documents does.
const maxDepth = 64

// kind is what a folded path holds: a mapping with entries is a node only, and anything else is a leaf.
type kind int

const (
	node      kind = iota // a mapping with entries
	nullLeaf              // a null
	emptyLeaf             // an empty mapping
	otherLeaf             // a scalar or a list
)

// folded is a config read the way golangci-lint reads it: its keys go through a reader that ignores the case of a key
// and splits it on a dot, so `Linters: {Settings: {Custom: ...}}` and `linters.settings.custom:` are one key to the
// tool. Each path is the lower-cased segments joined by a dot.
type folded map[string]kind

// document is the root mapping of a config, or the reason it is not read: the text is no YAML or JSON, is not one
// document, is not a mapping, or uses a form that makes one place stand for another (an anchor, an alias, a merge
// key, a tag) or writes a key twice.
func document(data []byte) (*yaml.Node, error) {
	var doc yaml.Node
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("%s", firstLine(err.Error()))
	}
	if doc.Kind != yaml.DocumentNode || len(doc.Content) != 1 {
		return nil, fmt.Errorf("the file holds no document")
	}
	root := doc.Content[0]
	if err := plain(root, 0); err != nil {
		return nil, err
	}
	if root.Kind != yaml.MappingNode {
		return nil, fmt.Errorf("the document is not a mapping")
	}
	return root, nil
}

func firstLine(s string) string {
	s, _, _ = strings.Cut(s, "\n")
	return s
}

// plain refuses, below n, each node that names or reuses another, a tag, and each key written twice in one mapping.
func plain(n *yaml.Node, depth int) error {
	if depth > maxDepth {
		return fmt.Errorf("line %d: nesting deeper than %d", n.Line, maxDepth)
	}
	switch {
	case n.Kind == yaml.AliasNode:
		return fmt.Errorf("line %d: the alias *%s stands for a value written elsewhere", n.Line, n.Value)
	case n.Anchor != "":
		return fmt.Errorf("line %d: the anchor &%s lets another place stand for a value", n.Line, n.Anchor)
	case n.Tag == "!!merge":
		return fmt.Errorf("line %d: merge keys (<<) are not supported", n.Line)
	case n.Style&yaml.TaggedStyle != 0:
		return fmt.Errorf("line %d: the tag %s is not read", n.Line, n.Tag)
	}
	seen := map[string]int{}
	for i, c := range n.Content {
		if err := plain(c, depth+1); err != nil {
			return err
		}
		if n.Kind != yaml.MappingNode || i%2 != 0 || c.Kind != yaml.ScalarNode {
			continue
		}
		if first, again := seen[c.Value]; again {
			return fmt.Errorf("line %d: the key %s is written again, first at line %d", c.Line, c.Value, first)
		}
		seen[c.Value] = c.Line
	}
	return nil
}

// fold is the folded view of a root mapping. The error is the plugin's refusal words: two keys fold to one path, or a
// key is outside ASCII.
func fold(root *yaml.Node) (folded, error) {
	out := folded{}
	return out, foldInto(out, root, nil, map[string]bool{})
}

func foldInto(out folded, m *yaml.Node, prefix []string, written map[string]bool) error {
	for i := 0; i+1 < len(m.Content); i += 2 {
		k, v := m.Content[i], m.Content[i+1]
		if k.Kind != yaml.ScalarNode {
			return fmt.Errorf("line %d: a key is not a scalar", k.Line)
		}
		ks, err := keySegments(k.Value)
		if err != nil {
			return err
		}
		segs := append(append([]string{}, prefix...), ks...)
		p := strings.Join(segs, ".")
		if written[p] {
			return fmt.Errorf("two keys of the file are one key to the tool (%s)", p)
		}
		written[p] = true
		switch {
		case v.Kind == yaml.MappingNode && len(v.Content) > 0:
			out[p] = node
			if err := foldInto(out, v, segs, written); err != nil {
				return err
			}
		case v.Kind == yaml.MappingNode:
			out[p] = emptyLeaf
		case v.Kind == yaml.ScalarNode && v.Tag == "!!null":
			out[p] = nullLeaf
		default:
			out[p] = otherLeaf
		}
	}
	return nil
}

// keySegments is a key as the tool reads it: lower-cased and split on a dot. A key outside ASCII is refused: how
// each version of the tool folds one is not a table kept here, so the file is not checked.
func keySegments(k string) ([]string, error) {
	for i := 0; i < len(k); i++ {
		if k[i] >= 0x80 {
			return nil, fmt.Errorf("the key %q is not ASCII, and the tool's fold of it is not known", k)
		}
	}
	return strings.Split(strings.ToLower(k), "."), nil
}

// has is whether the path is a key of the file, as a leaf or as a mapping with entries.
func (f folded) has(path string) bool {
	_, ok := f[path]
	return ok
}

// firstBelow is the first, in order, of the paths under a path, "" for none.
func (f folded) firstBelow(path string) string {
	var below []string
	for p := range f {
		if strings.HasPrefix(p, path+".") {
			below = append(below, p)
		}
	}
	if len(below) == 0 {
		return ""
	}
	sort.Strings(below)
	return below[0]
}

// under is the names directly below a path, in order: the one segment each path has after it.
func (f folded) under(path string) []string {
	seen := map[string]bool{}
	var out []string
	for p := range f {
		rest, ok := strings.CutPrefix(p, path+".")
		if !ok {
			continue
		}
		name, _, _ := strings.Cut(rest, ".")
		if !seen[name] {
			seen[name] = true
			out = append(out, name)
		}
	}
	sort.Strings(out)
	return out
}

// valueAt is the node a folded path names below a mapping, nil for none: a key is matched as the tool reads it, lower-cased
// and split on a dot, so `linters.default` is also `Linters: {Default: ...}`.
func valueAt(m *yaml.Node, path []string) *yaml.Node {
	if len(path) == 0 {
		return m
	}
	if m.Kind != yaml.MappingNode {
		return nil
	}
	for i := 0; i+1 < len(m.Content); i += 2 {
		ks, err := keySegments(m.Content[i].Value)
		if err != nil || len(ks) > len(path) {
			continue
		}
		match := true
		for j, s := range ks {
			if s != path[j] {
				match = false
				break
			}
		}
		if match {
			if n := valueAt(m.Content[i+1], path[len(ks):]); n != nil {
				return n
			}
		}
	}
	return nil
}
