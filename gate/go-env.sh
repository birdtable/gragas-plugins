#!/bin/sh
# sh gate/go-env.sh: asks the pinned go what it would build with, and refuses by name a setting that
# changes what a member builds and is not go's default (the method of
# gate/build-wasm.sh). The environment allowlist (gate/clean-env.sh) cuts the variables a caller set;
# the file `go env -w` writes under HOME is not a variable, so go is asked, under the environment a
# member has, and the answer is held: GOFLAGS, GOEXPERIMENT, GOWASM or GOFIPS140 set there is refused,
# and so is a GOVERSION that is not the pin. A setting is refused, never overridden, so a person who
# set one on purpose learns that the gate does not build with it.
# Env: GO_PIN (the Go toolchain, from gate/pins.env). GOFLAGS of the environment is the hooks' own
# -mod=mod and is unset here, as the members do, so only a file's GOFLAGS is read.
set -eu
: "${GO_PIN:?go-env: GO_PIN is not set (run through the Taskfile)}"
keys="GOVERSION GOFLAGS GOEXPERIMENT GOWASM GOFIPS140"
# shellcheck disable=SC2086 # the keys are words
said="$(env -u GOFLAGS GOTOOLCHAIN="$GO_PIN" go env $keys)" || { echo "go-env: not ready: go env could not be read with $GO_PIN" >&2; exit 1; }
i=0
for key in $keys; do
  i=$((i + 1))
  got="$(printf '%s\n' "$said" | sed -n "${i}p")"
  case "$key" in
    GOVERSION) want="$GO_PIN" ;;
    GOFIPS140) want=off ;;
    *) want= ;;
  esac
  [ "$got" = "$want" ] || {
    echo "go-env: go builds with $key='$got', and the gate wants '$want': unset it, in the environment or with go env -u $key, so a member is built as anyone builds it" >&2
    exit 1
  }
done
echo "go-env: go $GO_PIN builds with no GOFLAGS, GOEXPERIMENT, GOWASM or GOFIPS140 of its own"
