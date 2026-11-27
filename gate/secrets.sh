#!/bin/sh
# sh gate/secrets.sh <staged|range> <folder> <config> <private-key config> (task secrets-staged and secrets, with GITLEAKS set to the
# pinned gitleaks command): one pass of the secret scan, and the only place the command line is
# written. What a pull request's own tree can do to turn the scan off is closed here, as gragas closes it:
#   - a gitleaks config or ignore file, or any path holding gitleaks.toml (the default config's global allow-list
#     skips them unanchored), is refused by gate/secrets-refuse.sh;
#   - the config is named by absolute path, so a root .gitleaks.toml is never read;
#   - --ignore-gitleaks-allow, so a "gitleaks:allow" comment on the line hides nothing;
#   - the patch is read with --text --no-textconv, so a .gitattributes that marks a file -diff or binary, or names
#     a textconv, hides nothing. gitleaks's --staged takes no such option, so the stage is made a commit (git
#     write-tree, then git commit-tree with HEAD as the parent, no ref naming it) and scanned as one.
#   - two passes: the config, then gate/gitleaks-private-key.toml (the private-key rule alone, extending nothing),
#     because gitleaks appends the default config's global allow-list (.bin, .pdf, images, fonts, go.sum, go.work,
#     vendor/, any gitleaks.toml path) to every config that extends the defaults, with no key to drop it.
# --verbose names the file of a finding (the key stays redacted); gitleaks also prints the commit's Author and
# Email, and those two lines are dropped from the output, which is a person's, not a finding.
set -eu
mode="${1:?usage: sh gate/secrets.sh <staged|range> <folder> <config>}"
dir="${2:?folder}"
config="${3:?config}"
private="${4:?the private-key config}"
for f in "$config" "$private"; do
	case "$f" in /*) ;; *) echo "secrets: the config $f is not an absolute path" >&2; exit 2 ;; esac
	[ -f "$f" ] || { echo "secrets: the config $f is not a file" >&2; exit 2; }
done
[ -n "${GITLEAKS:-}" ] || { echo "secrets: GITLEAKS is not set: run it as a task member" >&2; exit 2; }
case "$mode" in staged|range) ;; *) echo "secrets: the mode is staged or range, not $mode" >&2; exit 2 ;; esac

range=""
if [ "$mode" = range ]; then
	if git -C "$dir" rev-parse -q --verify refs/remotes/origin/main >/dev/null; then range=origin/main..HEAD; else range=HEAD; fi
fi
sh gate/secrets-refuse.sh "$dir" "$range"

out="$(mktemp "${TMPDIR:-/tmp}/gragas-plugins-secrets.XXXXXX")"
trap 'rm -f "$out"' EXIT
rc=0
opts="--text --no-textconv --diff-merges=first-parent"
if [ "$mode" = staged ]; then
	# The stage as a commit on HEAD: its patch is what --staged reads, with the options above.
	tree="$(git -C "$dir" write-tree)"
	GIT_AUTHOR_NAME=secrets GIT_AUTHOR_EMAIL=secrets@example.invalid GIT_COMMITTER_NAME=secrets GIT_COMMITTER_EMAIL=secrets@example.invalid
	export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
	if head="$(git -C "$dir" rev-parse -q --verify HEAD)"; then
		commit="$(git -C "$dir" commit-tree "$tree" -p "$head" -m stage)"
	else
		commit="$(git -C "$dir" commit-tree "$tree" -m stage)"
	fi
	range="-1 $commit"
fi
for cfg in "$config" "$private"; do
	prc=0
	$GITLEAKS git --no-banner --redact --verbose --ignore-gitleaks-allow --config "$cfg" --log-opts="$opts $range" "$dir" >"$out" 2>&1 || prc=$?
	grep -v -E '^(Author|Email):' "$out" || true
	[ "$prc" -eq 0 ] || rc=$prc
done
exit "$rc"
