#!/bin/sh
# sh gate/build-wasm.sh <module folder> <out file>: builds a plugin's main package for wasip1 with the
# pinned Go and the flags that define the digest in a manifest's `wasm:` line. The `plugins` member and
# the release both build through it, so the flags are written once. <out file> is an absolute path.
# Env: GO_PIN (the Go toolchain, from gate/pins.env). A GOCACHE the caller sets is kept: the release's
# second build gives it an empty one.
#
# The build is a function of the module's tree and the pin alone, so anyone rebuilds it byte for byte:
# - GOFLAGS is dropped from the environment (the hooks set -mod=mod, which a module build never needs).
# - GOWORK=off: a go.work above the module, the repository's own or one a tree carries, is never read.
#   The bundle is built from the module's go.mod and go.sum as anyone who fetches the tag builds it.
# - go itself is then asked what it would build with, under that same environment, and any setting
#   that changes the bytes and is not go's default is refused, by name: GOFLAGS, GOEXPERIMENT, GOWASM
#   or GOFIPS140 set in the environment or in the caller's go env file (`go env -w`), and a GOVERSION
#   that is not the pin. Each is refused rather than overridden, so a person who set one on purpose
#   learns that a bundle is not built with it.
set -eu
[ $# -eq 2 ] || { echo "build-wasm: usage: sh gate/build-wasm.sh <module folder> <out file>" >&2; exit 2; }
: "${GO_PIN:?build-wasm: GO_PIN is not set (run through the Taskfile or a gate script)}"
case "$2" in /*) ;; *) echo "build-wasm: the out file '$2' is not an absolute path" >&2; exit 2 ;; esac
dir="$1"; out="$2"
# GOPRIVATE names the private modules a plugin may require, for the fetch alone; it never changes the
# bytes. gate/clean-env.sh drops the caller's, so the build names it.
build_env() { env -u GOFLAGS GOWORK=off GOTOOLCHAIN="$GO_PIN" GOPRIVATE=github.com/birdtable GOOS=wasip1 GOARCH=wasm CGO_ENABLED=0 "$@"; }
cd "$dir"
keys="GOVERSION GOFLAGS GOEXPERIMENT GOWASM GOFIPS140 GOWORK"
# shellcheck disable=SC2086 # the keys are words
said="$(build_env go env $keys)" || { echo "build-wasm: not ready: go env could not be read with $GO_PIN" >&2; exit 1; }
i=0
for key in $keys; do
  i=$((i + 1))
  got="$(printf '%s\n' "$said" | sed -n "${i}p")"
  case "$key" in
    GOVERSION) want="$GO_PIN" ;;
    GOFIPS140|GOWORK) want=off ;;
    *) want= ;;
  esac
  [ "$got" = "$want" ] || {
    echo "build-wasm: go builds with $key='$got', and a bundle's build wants '$want': unset it, in the environment or with go env -u $key, so the bundle is the one anyone rebuilds" >&2
    exit 1
  }
done
build_env go build -trimpath -buildvcs=false -ldflags=-buildid= -o "$out" .
