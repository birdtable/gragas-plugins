#!/bin/sh
# sh gate/plugins-plants.sh: each folder of gate/testdata/plugins is a plant, a plugin that must be
# red in the `plugins` member, with the line it must be red with in its `expect` file. A plant's
# Go sources are kept as go.mod.txt and main.go.txt so no module of the workspace holds them;
# they are copied to a temporary folder without the .txt. A plant that passes, or is red for another
# reason, is red here.
# A folder with a `control` file instead of `expect` is a clean control: it must pass, with that line.
# Then the workspace case: the clean control with a go.work at its root that lists the fixture and a
# module the tree lacks, so a build that reads it fails. It must still pass with the control's line,
# so the member never builds against a workspace. Each case runs with GOWORK unset, as a person's shell
# has it (the hooks set GOWORK=off, which would hide a build that reads go.work).
# Env, from the Taskfile: GO_PIN and GRAGAS_PIN.
# A plant with a `carry` file names a bundle of it (plugins/<name>/<version>) that carries the plugin.wasm the
# pinned Go builds from the clean control's source, as a released bundle carries the bytes it was released with.
# The released-* plants hold a source that has changed since, and a RELEASES file: the
# bundle it names is tested with the bytes it carries (released-control), one it does not name is built from
# today's source and red at C3 (released-unnamed), and one it names that carries no plugin.wasm is red
# (released-no-wasm).
set -eu
raw="$(mktemp -d)"; tmp="$(cd "$raw" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
# The account's state folder (gragas#2361): the caller's XDG_STATE_HOME names a file, so a gragas that takes
# its lock or writes its run log there cannot (a second gragas holding that lock would red it the same way).
# Each case below must come out as it does with the pinned gragas in a state folder of its own, and the
# file must be as it was at the end.
printf 'not a folder\n' > "$tmp/account-state"
XDG_STATE_HOME="$tmp/account-state"
export XDG_STATE_HOME
bad=0
mkdir -p "$tmp/.carry"
cp -R gate/testdata/plugins/clean-control/. "$tmp/.carry/"
find "$tmp/.carry" -name '*.txt' -exec sh -c 'for f; do mv "$f" "${f%.txt}"; done' sh {} +
for p in gate/testdata/plugins/*/; do
  case="$(basename "$p")"
  mkdir -p "$tmp/$case"
  cp -R "$p/." "$tmp/$case/"
  find "$tmp/$case" -name '*.txt' ! -name expect -exec sh -c 'for f; do mv "$f" "${f%.txt}"; done' sh {} +
  if [ -f "$p/carry" ]; then
    into="$(cat "$p/carry")"
    rm -f "$tmp/$case/carry"
    if ! out="$(sh gate/build-wasm.sh "$tmp/.carry/plugins/fixture" "$tmp/$case/$into/plugin.wasm" 2>&1)"; then
      echo "plugins-plants: $case: the clean control's .wasm, which $into carries, does not build:" >&2; echo "$out" >&2; bad=1; continue
    fi
  fi
  if [ -f "$p/control" ]; then
    # A clean control: a bundle whose manifest holds the digest of the pinned build, which the member
    # must pass with the line in `control`. It holds the build flags and the pinned Go to the digest.
    want="$(cat "$p/control")"
    rm -f "$tmp/$case/control"
    if out="$(env -u GOWORK sh gate/plugins.sh "$tmp/$case" 2>&1)" && printf '%s\n' "$out" | grep -F -q -- "$want"; then
      echo "plugins-plants: $case passes as the clean control: $(printf '%s\n' "$out" | grep -F -- "$want" | head -n 1)"
    else
      echo "plugins-plants: $case is the clean control and must pass with \"$want\":" >&2; echo "$out" >&2; bad=1
    fi
    continue
  fi
  want="$(cat "$p/expect")"
  rm -f "$tmp/$case/expect"
  if out="$(env -u GOWORK sh gate/plugins.sh "$tmp/$case" 2>&1)"; then
    echo "plugins-plants: $case passed, and it must be red" >&2; bad=1
  elif printf '%s\n' "$out" | grep -F -q -- "$want"; then
    echo "plugins-plants: $case is red as planted: $(printf '%s\n' "$out" | grep -F -- "$want" | head -n 1)"
  else
    echo "plugins-plants: $case is red, but not with \"$want\":" >&2; echo "$out" >&2; bad=1
  fi
done

# workspace: the clean control under a go.work that a build which reads it cannot load.
w="$tmp/workspace"
mkdir -p "$w"
cp -R gate/testdata/plugins/clean-control/. "$w/"
find "$w" -name '*.txt' -exec sh -c 'for f; do mv "$f" "${f%.txt}"; done' sh {} +
want="$(cat "$w/control")"
rm -f "$w/control"
printf 'go 1.27.1\n\nuse (\n\t./plugins/fixture\n\t./missing\n)\n' > "$w/go.work"
if out="$(env -u GOWORK sh gate/plugins.sh "$w" 2>&1)" && printf '%s\n' "$out" | grep -F -q -- "$want"; then
  echo "plugins-plants: workspace passes as the clean control under a go.work it must not read: $(printf '%s\n' "$out" | grep -F -- "$want" | head -n 1)"
else
  echo "plugins-plants: workspace must pass with \"$want\": the member read the go.work at its root:" >&2; echo "$out" >&2; bad=1
fi
if [ "$(cat "$tmp/account-state")" = "not a folder" ]; then
  echo "plugins-plants: no run took the lock or wrote the run log of the caller's state folder"
else
  echo "plugins-plants: a run of the plugins member used the caller's state folder (gragas#2361)" >&2; bad=1
fi
exit "$bad"
