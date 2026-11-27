#!/bin/sh
# The release ledger, run from the root of a clone or of the push's export:
#
#   sh gate/ledger.sh
#
# RELEASES holds one line for each release, added by the releaser, in a one-line pull request once the tag is pushed (README.md), and landed like any other:
#
#   <name>/v<version> <the tag object's sha> <the commit it tags> sha256:<the bundle's digest>
#
# (a blank line or a line that starts with # is skipped). A tag never moves, but a tag ruleset is not on
# this repository's plan, so a delete and re-push of a tag passes alone. The ledger makes it caught:
#   - origin holds each ledger tag at the recorded object, and the object here is that tag, on that commit;
#   - that commit is an ancestor of the commit checked, and the released folder plugins/<name>/<version>/
#     is as that commit has it (plugin.wasm apart, which the digest's build writes);
#     A released folder may leave the tree, and then its tag stays on origin and carries the ledger's digest
#     in its message, as release.sh wrote it; a folder that is present never changes;
#   - the ledger only grows: every line of the ledger on origin's main is a line of this one, so a line
#     cannot be edited to match a moved tag.
# gate/release.sh holds a plan and a release to the same line. A signature, when there is one, attaches to
# a line and stays outside the bundle folder.
#
# Each refusal is one line on stderr that begins "ledger:"; the run exits 1 after all of them. With no
# network the run is not ready, and red.
set -eu
GIT_NO_REPLACE_OBJECTS=1
export GIT_NO_REPLACE_OBJECTS
bad=0
red() { echo "ledger: $*" >&2; bad=1; }
[ -f RELEASES ] || { echo "ledger: RELEASES is missing: the file holds one line for each release, and is empty before the first" >&2; exit 1; }
raw="$(mktemp -d)"; tmp="$(cd "$raw" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
grep -v -E '^(#|$)' RELEASES > "$tmp/entries" || true

form='[a-z0-9][a-z0-9-]*/v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*) [0-9a-f]{40} [0-9a-f]{40} sha256:[0-9a-f]{64}'
if grep -v -x -E "$form" "$tmp/entries" > "$tmp/odd"; then
  red "RELEASES holds a line that is not '<name>/v<version> <tag object> <commit> sha256:<digest>': $(head -n 1 "$tmp/odd")"
  exit 1
fi
dups="$(cut -d' ' -f1 "$tmp/entries" | sort | uniq -d)"
[ -z "$dups" ] || { red "RELEASES records $(echo "$dups" | head -n 1) twice: a tag is released once"; exit 1; }

seen="$(git ls-remote origin refs/heads/main 'refs/tags/*' </dev/null)" || { echo "ledger: not ready: origin could not be read, so the tags are not held to the ledger (no network?)" >&2; exit 1; }
main="$(printf '%s\n' "$seen" | awk '$2 == "refs/heads/main" { print $1 }')"
head="$(git rev-parse --verify HEAD)"

while read -r tag obj commit digest; do
  name="${tag%%/*}"; version="${tag#*/v}"; folder="plugins/$name/$version"
  there="$(printf '%s\n' "$seen" | awk -v r="refs/tags/$tag" '$2 == r { print $1 }')"
  if [ "$there" != "$obj" ]; then
    red "the ledger records $tag as $obj, and origin has '${there:-none}': a tag never moves, and a wrong one is answered by the next version"
    continue
  fi
  if [ "$(git cat-file -t "$obj" 2>/dev/null || true)" != tag ]; then
    red "not ready: the tag object $obj of $tag is not in this clone: fetch the tags"
    continue
  fi
  header="$(git cat-file tag "$obj" | sed '/^$/q')"
  [ "$(printf '%s\n' "$header" | sed -n 's/^tag //p')" = "$tag" ] && [ "$(printf '%s\n' "$header" | sed -n 's/^object //p')" = "$commit" ] ||
    { red "the tag object $obj does not name $tag on $commit, as the ledger records"; continue; }
  if ! git cat-file -e "$commit^{commit}" 2>/dev/null; then
    red "not ready: the commit $commit of $tag is not in this clone: fetch it"
    continue
  fi
  git merge-base --is-ancestor "$commit" "$head" || { red "the commit $commit of $tag is not an ancestor of $head: merge main"; continue; }
  git cat-file -e "$commit:$folder/plugin.yaml" 2>/dev/null || { red "the ledger records $tag, and $commit holds no $folder/plugin.yaml"; continue; }
  if git cat-file -e "$head:$folder" 2>/dev/null; then
    git diff --quiet "$commit" "$head" -- "$folder" ":(exclude)$folder/plugin.wasm" ||
      red "$folder is not as $commit, which the ledger records for $tag, has it: a released bundle never changes, and a change is the next version"
  else
    # A released folder may leave the tree but never change in place: its tag is on origin (checked above),
    # and the digest that tag's message carries is the line's.
    said="$(git cat-file tag "$obj" | sed -n 's/^bundle: //p')"
    [ "$said" = "$digest" ] ||
      red "$folder has left the tree, and the tag $tag carries '${said:-no digest}', not the ledger's $digest: a released bundle never changes"
  fi
done < "$tmp/entries"

# The ledger only grows, an empty or comments-only ledger included: it is checked before anything may be
# taken as "no release is recorded yet", or emptying it would free every moved tag.
[ -n "$main" ] || { echo "ledger: origin has no main" >&2; exit 1; }
if ! git cat-file -e "$main^{commit}" 2>/dev/null; then
  red "not ready: origin's main $main is not in this clone: fetch it"
elif git cat-file -e "$main:RELEASES" 2>/dev/null; then
  git show "$main:RELEASES" | grep -v -E '^(#|$)' > "$tmp/old" || true
  lost="$(grep -v -x -F -f "$tmp/entries" "$tmp/old" || true)"
  [ -z "$lost" ] || red "a line of the ledger on origin's main is not in this one (merge main, and never edit a line): $(echo "$lost" | head -n 1)"
fi

[ "$bad" = 0 ] || exit 1
n="$(wc -l < "$tmp/entries" | tr -d ' ')"
echo "ledger: $n release(s) held to origin, the tree and main's ledger"
