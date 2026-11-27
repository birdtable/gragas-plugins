#!/bin/sh
# sh gate/plugins.sh <root>: the `plugins` member. <root> holds a plugins/ folder; each plugin is
# plugins/<name>/, a Go module whose main package builds for wasip1, and each bundle is
# plugins/<name>/<version>/, holding plugin.yaml and testdata/ (the layout `gragas plugin test` reads).
# For each bundle it copies the folder to a temporary one, builds plugin.wasm into the copy with the
# pinned Go from the module's main package, and runs `gragas plugin test` on the copy with the
# pinned gragas. A committed plugin.wasm is replaced by that build, so the bytes tested are the ones
# the pinned tools make from the source. With no plugin folder it passes and says so.
# A bundle <root>/RELEASES records (<name>/v<version> as a line's first word) is released, and is not built
# here: the module's source is the next version's, and the released folder, its manifest's wasm digest
# included, never changes (gate/ledger.sh holds it to the commit it was released from, and `task release`
# rebuilds it from its tag with that commit's pins), so a build of it from today's source is red at C3
# for every change to the plugin. It is tested with the plugin.wasm it carries, which
# C3 holds to that digest, and red when it carries none. A line that names no tag on origin is red in the
# ledger member, so a line cannot spare a bundle that was never released its build.
# Env, from the Taskfile: GO_PIN (the Go toolchain) and GRAGAS_PIN (the gragas commit).
set -eu
[ $# -eq 1 ] || { echo "plugins: usage: sh gate/plugins.sh <root>" >&2; exit 2; }
: "${GO_PIN:?plugins: GO_PIN is not set (run through the Taskfile)}"
: "${GRAGAS_PIN:?plugins: GRAGAS_PIN is not set (run through the Taskfile)}"
root="$(cd "$1" && pwd -P)"
found=0
for d in "$root"/plugins/*/; do
  [ -d "$d" ] || continue
  found=1
done
if [ "$found" = 0 ]; then
  echo "plugins: no plugin folder yet (plugins/<name>/), so nothing is built or tested"
  exit 0
fi
raw="$(mktemp -d)"; tmp="$(cd "$raw" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
# The tags the ledger records, one to a line, as gate/ledger.sh reads them: a blank line or a comment is none.
: > "$tmp/released"
if [ -f "$root/RELEASES" ]; then
  grep -v -E '^(#|$)' "$root/RELEASES" | awk '{ print $1 }' > "$tmp/released" || true
fi
# go run turns every exit of the program into 1, and plugin test's "not ready" (4) must be told from red,
# so the pinned gragas is built once, by the pinned Go, and run as a program.
mkdir -p "$tmp/bin"
env GOTOOLCHAIN="$GO_PIN" GOFLAGS=-mod=mod GOWORK=off GOPRIVATE=github.com/birdtable GOBIN="$tmp/bin" go install "github.com/birdtable/gragas/cmd/gragas@$GRAGAS_PIN" || { echo "plugins: the pinned gragas could not be built" >&2; exit 1; }
# The pinned gragas runs in a state folder of its own: its lock is the machine's, and a run in the account's
# state folder would red another agent's gragas, and write the account's run log (gragas#2361).
mkdir -m 700 "$tmp/state"
bad=0
for d in "$root"/plugins/*/; do
  name="$(basename "$d")"
  if [ ! -f "$d/go.mod" ]; then
    echo "plugins: plugins/$name has no go.mod: a plugin folder is a Go module" >&2; bad=1; continue
  fi
  n=0
  for b in "$d"*/; do
    [ -f "$b/plugin.yaml" ] || continue
    n=$((n+1))
    v="$(basename "$b")"
    ref="plugins/$name/$v"
    mkdir -p "$tmp/$ref"
    cp -R "$b/." "$tmp/$ref/"
    if grep -q -x -F -- "$name/v$v" "$tmp/released"; then
      # Released: tested as released, with the plugin.wasm the folder carries, which C3 holds to the
      # manifest's digest; every other check runs at today's GRAGAS_PIN.
      if [ ! -f "$tmp/$ref/plugin.wasm" ]; then
        echo "plugins: $ref: released as $name/v$v (RELEASES), and the folder carries no plugin.wasm: a released bundle is tested with the bytes it was released with" >&2; bad=1; continue
      fi
      echo "plugins: $ref: released as $name/v$v (RELEASES): tested with the plugin.wasm it carries, not built from today's source"
    else
      rm -f "$tmp/$ref/plugin.wasm"
      # build-wasm.sh builds with GOWORK=off: the bundle is built against the tags its go.mod requires, as
      # a user builds it, never against the workspace's local modules, which go.work lists and which may
      # hold other bytes. It names GOPRIVATE itself, since gate/clean-env.sh drops the
      # caller's, and it refuses a go env that changes the bytes.
      if ! out="$(sh gate/build-wasm.sh "$d" "$tmp/$ref/plugin.wasm" 2>&1)"; then
        echo "plugins: $ref: the .wasm does not build:" >&2; echo "$out" >&2; bad=1; continue
      fi
    fi
    rc=0
    out="$(cd "$tmp" && XDG_STATE_HOME="$tmp/state" "$tmp/bin/gragas" plugin test "$ref" 2>&1)" || rc=$?
    case "$rc" in
      0) echo "plugins: $ref: plugin test passed" ;;
      4) echo "plugins: $ref: plugin test: no check failed, and one of C1 to C17 was not run or not asked (not ready, as the pinned gragas ends it)" ;;
      *) echo "plugins: $ref: plugin test is red (exit $rc):" >&2; echo "$out" >&2; bad=1 ;;
    esac
  done
  [ "$n" -gt 0 ] || { echo "plugins: plugins/$name holds no bundle (plugins/$name/<version>/plugin.yaml)" >&2; bad=1; }
done
exit "$bad"
