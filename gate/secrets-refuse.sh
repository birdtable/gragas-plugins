#!/bin/sh
# sh gate/secrets-refuse.sh <folder> [<range>] (the first command of gate/secrets.sh): a tree that
# brings its own gitleaks config or ignore file, or a path the scan would skip, is not scanned. gitleaks reads
# <source>/.gitleaks.toml when it is given no --config (the members always give one, gate/gitleaks.toml, by absolute
# path), and a .gitleaksignore from the folder it runs in; and its default config's global allow-list exempts every
# path that holds the text gitleaks.toml, unanchored (config/gitleaks.toml of 8.30.1, kept by useDefault). So a
# tracked path that matches gitleaks\.toml (any depth, any case) other than gate/gitleaks.toml itself, and a
# .gitleaksignore at any depth, is red, and so is a .gitleaksignore in the folder or in the folder the member runs
# in. Git's index holds the commit's tree on a push (the export) and the lander's squash at landing; a range's
# commits are read too, so a file added and removed past origin/main is red as well.
set -eu
dir="${1:?usage: sh gate/secrets-refuse.sh <folder> [<range>]}"
range="${2:-}"
bad=0
pattern='gitleaks\.toml|(^|/)\.gitleaksignore$'
found="$(git -C "$dir" -c core.quotePath=false ls-files --cached -- | grep -i -E "$pattern" | grep -v -x 'gate/gitleaks.toml' || true)"
if [ -n "$range" ]; then
	past="$(git -C "$dir" -c core.quotePath=false log --format= --name-only --no-renames --diff-merges=first-parent --diff-filter=d $range -- | grep -i -E "$pattern" | grep -v -x 'gate/gitleaks.toml' || true)"
	found="$(printf '%s\n%s\n' "$found" "$past" | grep -v '^$' | sort -u || true)"
fi
if [ -n "$found" ]; then
	printf '%s\n' "$found" | while IFS= read -r f; do
		echo "secrets: $f is a gitleaks config or ignore file, or a path the scan would skip: the scan reads only gate/gitleaks.toml" >&2
	done
	bad=1
fi
for f in "$dir/.gitleaksignore" ./.gitleaksignore; do
	if [ -e "$f" ] || [ -L "$f" ]; then
		echo "secrets: $f exists: the scan reads no ignore file" >&2
		bad=1
	fi
done
[ "$bad" -eq 0 ]
