#!/bin/sh
# The release of a plugin bundle, run from the root of a clone:
#
#   sh gate/release.sh plan <name>/v<version>
#   sh gate/release.sh tagged <name>/v<version> [<out folder>]
#
# A bundle is plugins/<name>/<version>/ (plugin.yaml, plugin.wasm, testdata/), and its tag is
# <name>/v<version>, annotated, on a commit of main. The tag's message carries the bundle's digest as
# one line, `bundle: sha256:<64 hex>`. The digest is gragas's own (pluginbundle.Digest, every file of
# the folder): the pinned gragas writes it into a lock with `plugin add --apply` in a throwaway root,
# judging the bundle as it does (the manifest strict, its name and version those of the folder, its
# `wasm:` the module's), and the digest is read from that lock. Nothing here sums a bundle.
#
# plan runs on the landed commit, before the tag: HEAD is origin's main, and the tag is neither here nor
# on origin. It builds the bundle and prints the line the tag's message carries. The releaser tags with it.
# tagged runs from the tag: the tag is annotated, its object names itself <name>/v<version>, it tags a
# commit, origin's tag is the same object, and that commit is on origin's main. It builds the bundle and
# holds it to the tag's line, so anyone with the clone rebuilds it byte for byte from the tag. With an
# out folder, which must not exist, it copies the bundle there. It publishes nothing, pushes nothing and
# changes no ref.
#
# Both build from the commit's tree with the commit's pins, never from the working tree: gate/export.sh
# writes the tree twice, into two folders, and the commit's gate/build-wasm.sh builds plugin.wasm in each,
# with the commit's GOTOOLCHAIN, the second with an empty build cache. build-wasm.sh reads no go.work and
# refuses a go setting that would change the bytes (GOFLAGS, GOEXPERIMENT, GOWASM, GOFIPS140 or another
# Go), from the environment or the caller's go env file. A plugin.wasm the tree carries must be the
# build's bytes. Both bundles must sum to one digest, and `gragas plugin test` from the commit's
# GRAGAS_PIN must pass the first (exit 0, or 4, not ready, as the `plugins` member reads it). The pinned
# gragas runs with a settings file of the release's own and a state folder of its own (XDG_STATE_HOME,
# set here), so the machine-wide lock of the caller's state folder is never taken (gragas#2361).
# Signing waits for gragas's own release to sign (cmd/gragas-release signs nothing yet); a signature,
# when there is one, stays outside the bundle folder, whose every file the digest covers.
#
# tagged also holds the tag to the ledger, RELEASES on origin's main (gate/ledger.sh): a released tag that
# is another object, on another commit or with another digest is red, and plan refuses a tag the ledger
# records, though neither the clone nor origin has it. A tag not in the ledger yet prints the line to land.
#
# Each refusal is one line on stderr that begins "release:" and exits 1; usage is exit 2.
set -eu
GIT_NO_REPLACE_OBJECTS=1
export GIT_NO_REPLACE_OBJECTS
red() { echo "release: $*" >&2; exit 1; }
usage() { echo "release: usage: sh gate/release.sh plan <name>/v<version> | sh gate/release.sh tagged <name>/v<version> [<out folder>]" >&2; exit 2; }

[ $# -ge 2 ] || usage
mode="$1"; tag="$2"; out="${3:-}"
case "$mode" in
  plan) [ $# -eq 2 ] || usage ;;
  tagged) [ $# -le 3 ] || usage ;;
  *) usage ;;
esac
# The tag's form, before git is asked. A character outside the set is refused first, so a newline cannot
# hand grep a second line to match.
case "$tag" in *[!a-z0-9A-Z./-]*|"") red "the tag '$tag' is not <name>/v<version>" ;; esac
# No pre-release part: the lock gragas writes refuses one, so a tag with it could never be released.
printf '%s\n' "$tag" | grep -q -x -E '[a-z0-9][a-z0-9-]*/v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)' ||
  red "the tag '$tag' is not <name>/v<version>: a plugin's folder name, /v, and a version major.minor.patch with no pre-release part"
name="${tag%%/*}"; version="${tag#*/v}"
bundle="plugins/$name/$version"
if [ -n "$out" ]; then
  case "$out" in /*) ;; *) out="$(pwd -P)/$out" ;; esac
  [ ! -e "$out" ] && [ ! -L "$out" ] || red "the out folder $out exists: the bundle is copied only into a new one"
fi

# Origin: its main and its tag, by their whole ref names (ls-remote's pattern matches a ref's tail).
seen="$(git ls-remote origin refs/heads/main "refs/tags/$tag" </dev/null)" || red "not ready: origin could not be read"
main="$(printf '%s\n' "$seen" | awk '$2 == "refs/heads/main" { print $1 }')"
there="$(printf '%s\n' "$seen" | awk -v r="refs/tags/$tag" '$2 == r { print $1 }')"
[ -n "$main" ] || red "origin has no main"

if [ "$mode" = plan ]; then
  commit="$(git rev-parse --verify --quiet 'HEAD^{commit}')" || red "HEAD is not a commit"
  [ "$commit" = "$main" ] || red "plan: HEAD is $commit and origin's main is $main: a bundle is planned on the landed commit"
  if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
    red "plan: the tag $tag exists in this clone: a tag never moves, and a wrong one is answered by the next version"
  fi
  [ -z "$there" ] || red "plan: origin has the tag $tag already: a tag never moves, and a wrong one is answered by the next version"
else
  obj="$(git rev-parse --verify --quiet "refs/tags/$tag")" || red "there is no tag $tag in this clone"
  [ "$(git cat-file -t "$obj")" = tag ] || red "the tag $tag is lightweight: a release tag is annotated"
  head="$(git cat-file tag "$obj" | sed '/^$/q')"
  [ "$(printf '%s\n' "$head" | sed -n 's/^type //p')" = commit ] || red "the tag $tag does not tag a commit"
  named="$(printf '%s\n' "$head" | sed -n 's/^tag //p')"
  [ "$named" = "$tag" ] || red "the tag object under refs/tags/$tag names itself '$named': a tag is released under its own name"
  commit="$(git rev-parse --verify "$obj^{commit}")"
  [ "$there" = "$obj" ] || red "the tag $tag is $obj in this clone and '${there:-none}' on origin: a release is of the tag origin holds"
  git cat-file -e "$main^{commit}" 2>/dev/null || red "not ready: origin's main $main is not in this clone: fetch it"
  git merge-base --is-ancestor "$commit" "$main" || red "the tag $tag is on $commit, which is not on origin's main ($main): a bundle is released only from main"
  lines="$(git cat-file tag "$obj" | sed '1,/^$/d' | grep -E '^bundle:' || true)"
  printf '%s\n' "$lines" | grep -q -x -E 'bundle: sha256:[0-9a-f]{64}' && [ "$(printf '%s\n' "$lines" | wc -l | tr -d ' ')" = 1 ] ||
    red "the tag $tag's message does not carry one line 'bundle: sha256:<64 hex>': the line plan prints"
  recorded="${lines#bundle: }"
fi
# The ledger (RELEASES on origin's main): a tag released is recorded there with its object,
# its commit and its digest, so a tag deleted and made again on another commit is caught, though origin
# holds the new one. A tag not yet in the ledger is one whose line has not landed yet.
ledgered=""
if git cat-file -e "$main:RELEASES" 2>/dev/null; then
  ledgered="$(git show "$main:RELEASES" | awk -v t="$tag" '$1 == t')"
fi
if [ -n "$ledgered" ]; then
  [ "$(printf '%s\n' "$ledgered" | wc -l | tr -d ' ')" = 1 ] || red "the ledger records $tag more than once"
  if [ "$mode" = plan ]; then
    red "plan: the ledger records $tag already: a tag never moves, and a wrong one is answered by the next version"
  fi
  set -- $ledgered
  [ "$2" = "$obj" ] || red "the tag $tag is $obj and the ledger records $2: a tag never moves, and a wrong one is answered by the next version"
  [ "$3" = "$commit" ] || red "the tag $tag is on $commit and the ledger records $3: a tag never moves"
  [ "$4" = "$recorded" ] || red "the tag $tag records $recorded and the ledger records $4: a tag never moves"
fi
# <name>/v<version> is also the form of a Go module's tag for the folder <name>/ at the root: a plugin
# named for a module folder would tag that module too.
if git cat-file -e "$commit:$name/go.mod" 2>/dev/null; then
  red "the tag $tag is also the tag of the Go module $name/ at the root of $commit: a plugin is never named for a module folder"
fi

raw="$(mktemp -d)"; tmp="$(cd "$raw" && pwd -P)"
top="$(pwd -P)"
cleanup() {
  for side in a b; do
    [ -d "$tmp/$side" ] && git -C "$top" worktree remove --force "$tmp/$side" >/dev/null 2>&1 || true
  done
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

for side in a b; do
  sh gate/export.sh "$commit" "$tmp/$side" || red "the tree of $commit could not be exported"
done
[ -f "$tmp/a/$bundle/plugin.yaml" ] || red "the tag $tag names $bundle/, and the tree of $commit holds no $bundle/plugin.yaml"
[ -f "$tmp/a/plugins/$name/go.mod" ] || red "the tree of $commit holds no plugins/$name/go.mod: a plugin is a Go module"
[ -f "$tmp/a/gate/build-wasm.sh" ] || red "the tree of $commit has no gate/build-wasm.sh: it predates the release of a bundle"
go_pin="$(cd "$tmp/a" && sh gate/read-pins.sh GOTOOLCHAIN)" || red "the pins of $commit are refused"
gragas_pin="$(cd "$tmp/a" && sh gate/read-pins.sh GRAGAS_PIN)" || red "the pins of $commit are refused"

# The pinned gragas, built once by the pinned Go, as the plugins member builds it.
mkdir -p "$tmp/bin"
env GOTOOLCHAIN="$go_pin" GOFLAGS=-mod=mod GOWORK=off GOPRIVATE=github.com/birdtable GOBIN="$tmp/bin" go install "github.com/birdtable/gragas/cmd/gragas@$gragas_pin" ||
  red "not ready: the pinned gragas $gragas_pin could not be built"
git_path="$(command -v git)" || red "git is not on PATH"
mkdir -m 700 "$tmp/cfg"
printf 'version: 1\nprograms:\n  git: %s\n' "$git_path" > "$tmp/cfg/settings.yaml"
chmod 600 "$tmp/cfg/settings.yaml"
# The pinned gragas keeps its lock and run log under $XDG_STATE_HOME/gragas, and the lock is the machine's:
# a run of this member would red another agent's gragas ("another gragas run is writing", gragas#2361) and
# write the account's own run log. It runs in a state folder of its own, made here and removed with $tmp.
mkdir -m 700 "$tmp/state"

# digest_of <label> <folder>: the bundle in that folder, judged and summed by the pinned gragas.
digest_of() {
  root="$tmp/book-$1"
  git init -q "$root" || red "a throwaway root could not be made"
  if ! said="$(cd "$root" && XDG_STATE_HOME="$tmp/state" GRAGAS_CONFIG="$tmp/cfg/settings.yaml" "$tmp/bin/gragas" plugin add "$2" --apply 2>&1)"; then
    echo "$said" >&2; red "the pinned gragas refused the bundle $bundle of $commit (above)"
  fi
  # The lock alone: `plugin list` would read the caller's approvals record too, and a record a newer
  # gragas wrote is one the pinned gragas refuses, so the release would hang on who runs it.
  [ -f "$root/plugins/lock.yaml" ] || red "the pinned gragas wrote no lock for $bundle"
  locked="$(sed -n -E 's/^[[:space:]]*digest: "(sha256:[0-9a-f]{64})"$/\1/p' "$root/plugins/lock.yaml")"
  [ -n "$locked" ] && [ "$(printf '%s\n' "$locked" | wc -l | tr -d ' ')" = 1 ] ||
    red "the lock the pinned gragas wrote for $bundle does not hold one digest"
  printf '%s\n' "$locked"
}

# The first build, with the caller's build cache.
(cd "$tmp/a" && GO_PIN="$go_pin" sh gate/build-wasm.sh "plugins/$name" "$tmp/wasm-a") || red "the .wasm of $bundle does not build from the tree of $commit"
if [ -f "$tmp/a/$bundle/plugin.wasm" ]; then
  cmp -s "$tmp/wasm-a" "$tmp/a/$bundle/plugin.wasm" || red "the plugin.wasm $bundle carries is not what $go_pin builds from the tree of $commit: rebuild it with the pin and commit it"
fi
cp "$tmp/wasm-a" "$tmp/a/$bundle/plugin.wasm"
sum_a="$(digest_of a "$tmp/a/$bundle")"
if [ "$mode" = tagged ] && [ "$sum_a" != "$recorded" ]; then
  red "the bundle rebuilt from $tag is $sum_a, and the tag records $recorded"
fi

# The second build, from the second export with an empty build cache.
mkdir "$tmp/gocache-b"
(cd "$tmp/b" && GOCACHE="$tmp/gocache-b" GO_PIN="$go_pin" sh gate/build-wasm.sh "plugins/$name" "$tmp/wasm-b") || red "the second build of $bundle failed"
cmp -s "$tmp/wasm-a" "$tmp/wasm-b" || red "two builds of $bundle from the tree of $commit differ: the build does not repeat"
cp "$tmp/wasm-b" "$tmp/b/$bundle/plugin.wasm"
sum_b="$(digest_of b "$tmp/b/$bundle")"
[ "$sum_a" = "$sum_b" ] || red "the two bundles of $bundle sum apart: $sum_a and $sum_b"

# plugin test takes the same settings file as the digest, so the caller's settings never reach it.
rc=0
said="$(cd "$tmp/a" && XDG_STATE_HOME="$tmp/state" GRAGAS_CONFIG="$tmp/cfg/settings.yaml" "$tmp/bin/gragas" plugin test "$bundle" 2>&1)" || rc=$?
# Exit 4, not ready, passes, as the plugins member reads it: at this GRAGAS_PIN, C5, C7 to C17 and C23
# cannot run (gate/pins.env). When the pin moves to one that runs them, a release wants exit 0 alone.
case "$rc" in
  0|4) ;;
  *) echo "$said" >&2; red "gragas plugin test is red on $bundle (exit $rc)" ;;
esac

if [ "$mode" = plan ]; then
  echo "release: plan: $tag at $commit: bundle: $sum_a"
  echo "release: tag it, annotated, with that line in its message: bundle: $sum_a"
  exit 0
fi
if [ -n "$out" ]; then
  mkdir -p "$(dirname "$out")" && mkdir "$out" || red "the out folder $out could not be made"
  cp -R "$tmp/a/$bundle/." "$out/"
  # The copy is held to the bundle summed, file by file and byte for byte, so the folder handed on is
  # the one the tag records. (plugin add takes the name and version from the folder's path, so it cannot
  # sum an out folder of another name.)
  diff -r -q "$tmp/a/$bundle" "$out" >/dev/null || red "the bundle copied to $out is not the bundle summed in $tmp/a/$bundle"
  echo "release: $tag at $commit: bundle: $sum_a, rebuilt twice and as the tag records it, copied to $out"
else
  echo "release: $tag at $commit: bundle: $sum_a, rebuilt twice and as the tag records it"
fi
if [ -z "$ledgered" ]; then
  echo "release: the ledger has no line for $tag: land this one in RELEASES on main: $tag $obj $commit $sum_a"
fi
