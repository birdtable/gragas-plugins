#!/bin/sh
# sh gate/clean-env.sh <command> [args...]: run <command> with an allowlisted environment. It is the one place the hooks and `task landing` cut the caller's
# environment, so no task switch, Go switch or git switch of the caller reaches a run: not
# TASK_TEMP_DIR or TASK_X_*, not GOFLAGS, GOENV, GOEXPERIMENT, GOMODCACHE or GOCACHE, not
# GIT_CONFIG_COUNT or GIT_CONFIG_PARAMETERS, and not a later tool's variable, since a list of names to
# drop fails open on the next one and a list of names to keep does not.
#
# What is kept, and why (the README's The gate says the same):
#   PATH                 so the run finds go, git and sh; the caller's own PATH is what it is
#   HOME USER LOGNAME    who runs it: go's caches, git's and the credential helper's config live under HOME
#   SHELL TMPDIR TERM    the shell a child may name, the temporary folder, the terminal's width and colour
#   LANG and LC_*        the locale, which sort and tools read
#   XDG_*                the folders a tool puts its config and caches in, with HOME
#   GOMAXPROCS           the CPUs the heavy-test slot gives a run; it changes only how fast
#   SSH_AUTH_SOCK        a push whose origin is over ssh still reads its agent
#   SSL_CERT_FILE SSL_CERT_DIR HTTPS_PROXY HTTP_PROXY NO_PROXY NO_COLOR
#                        the trust store and the proxy a network has, as gragas keeps them; without them a
#                        pusher behind a proxy cannot fetch the SDK the go members and the plugins need
# Everything else is dropped. A kept name set to nothing is handed on set to nothing.
# The go env file `go env -w` writes under HOME is not an environment variable and is not cut here:
# gate/go-env.sh (the go-env member) asks go what it would build with and refuses by name a
# GOFLAGS, GOEXPERIMENT, GOWASM, GOFIPS140 or GOVERSION that is not the pin's. A fetch of a private
# module names GOPRIVATE itself, so it does not depend on that file.
#
# The command is the last of the arguments and is run by `env -i`, so it needs no shell of its own.
# A caller that wants a variable to reach a member sets it in the Taskfile, where a member names it.
set -eu
[ $# -ge 1 ] || { echo "clean-env: usage: sh gate/clean-env.sh <command> [args...]" >&2; exit 2; }

# The names kept as they are, and the prefixes kept whole.
names="PATH HOME USER LOGNAME SHELL TMPDIR TERM LANG GOMAXPROCS SSH_AUTH_SOCK SSL_CERT_FILE SSL_CERT_DIR HTTPS_PROXY HTTP_PROXY NO_PROXY NO_COLOR"
prefixes="LC_ XDG_"

# The arguments are the command now; each kept variable is added after them and the command is then
# turned to the end, so the list `env -i` reads is the variables and the command.
count=$#
have() { printenv "$1" >/dev/null 2>&1; }
for name in $names; do
  if have "$name"; then set -- "$@" "$name=$(printenv "$name")"; fi
done
for prefix in $prefixes; do
  for name in $(env | sed -n "s/^\\(${prefix}[A-Za-z0-9_]*\\)=.*/\\1/p"); do
    if have "$name"; then set -- "$@" "$name=$(printenv "$name")"; fi
  done
done
i=0
while [ "$i" -lt "$count" ]; do
  first="$1"; shift; set -- "$@" "$first"; i=$((i + 1))
done
exec env -i "$@"
