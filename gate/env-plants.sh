#!/bin/sh
# sh gate/env-plants.sh: the plants of the environment allowlist. Each plants variables in this script's own
# environment, as a caller could, and runs `env` to print what a child would read.
#   1. Without the cleaner the child reads every planted name: the plant is live, and it is what
#      the hooks and `task landing` would hand the run without the allowlist. This is the red.
#   2. Through gate/clean-env.sh the child reads none of the dropped names and each kept name
#      with its value: this is the green.
# A plant that did not reach the child without the cleaner proves nothing, so that is red too.
set -eu

dropped="GOFLAGS GOENV GOEXPERIMENT GOMODCACHE GOCACHE GOTOOLCHAIN GOWORK GOPROXY GOPRIVATE CGO_ENABLED
  TASK_TEMP_DIR TASK_X_ENV_PRECEDENCE TASK_X_REMOTE_TASKFILES TASK_COLOR_RESET
  GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_CONFIG_PARAMETERS GIT_CONFIG_GLOBAL GIT_DIR GIT_EXEC_PATH
  GITLEAKS_PIN GRAGAS_PIN TASK_PIN LATER_TOOLS_SWITCH EMPTY_PLANT"
kept="HOME USER LOGNAME SHELL TMPDIR TERM LANG LC_ALL XDG_CACHE_HOME XDG_DATA_HOME GOMAXPROCS SSH_AUTH_SOCK SSL_CERT_FILE SSL_CERT_DIR HTTPS_PROXY HTTP_PROXY NO_PROXY NO_COLOR PATH"

GOFLAGS=-tags=planted; GOENV=/planted/env; GOEXPERIMENT=planted; GOMODCACHE=/planted/mod; GOCACHE=/planted/cache
GOTOOLCHAIN=planted; GOWORK=/planted/go.work; GOPROXY=planted; GOPRIVATE=planted; CGO_ENABLED=7
TASK_TEMP_DIR=/planted/task; TASK_X_ENV_PRECEDENCE=1; TASK_X_REMOTE_TASKFILES=1; TASK_COLOR_RESET=0
GIT_CONFIG_COUNT=1; GIT_CONFIG_KEY_0=core.hooksPath; GIT_CONFIG_VALUE_0=/planted/hooks
GIT_CONFIG_PARAMETERS="'core.hooksPath=/planted/hooks'"; GIT_CONFIG_GLOBAL=/planted/gitconfig
GIT_DIR=/planted/git; GIT_EXEC_PATH=/planted/exec
GITLEAKS_PIN=--exit-code=0; GRAGAS_PIN=planted; TASK_PIN=planted; LATER_TOOLS_SWITCH=1; EMPTY_PLANT=
export $dropped
LC_ALL=C; XDG_CACHE_HOME="/planted cache/x"; XDG_DATA_HOME=/planted/data; GOMAXPROCS=3; TERM=planted-term
SSH_AUTH_SOCK=/planted/agent; SSL_CERT_FILE=/planted/ca.pem; SSL_CERT_DIR=/planted/certs; HTTPS_PROXY=http://planted:1
HTTP_PROXY=http://planted:2; NO_PROXY=planted; NO_COLOR=
export LC_ALL XDG_CACHE_HOME XDG_DATA_HOME GOMAXPROCS TERM SSH_AUTH_SOCK SSL_CERT_FILE SSL_CERT_DIR HTTPS_PROXY HTTP_PROXY NO_PROXY NO_COLOR

here="$(dirname "$0")"
fail=0
red() { echo "env-plants: $*" >&2; fail=1; }

# 1. Without the cleaner: every planted name reaches the child.
raw="$(env)"
for n in $dropped; do
  printf '%s\n' "$raw" | grep -q "^$n=" || red "the plant $n did not reach a child without the cleaner, so it proves nothing"
done

# 2. Through the cleaner: none of them does, and each kept name does, with its value.
clean="$(sh "$here/clean-env.sh" env)"
for n in $dropped; do
  if printf '%s\n' "$clean" | grep -q "^$n="; then
    red "$n reaches the run through gate/clean-env.sh: $(printf '%s\n' "$clean" | grep "^$n=")"
  fi
done
for n in $kept; do
  want="$(printenv "$n" || true)"
  got="$(printf '%s\n' "$clean" | grep "^$n=" | head -n 1 | cut -d= -f2-)" || true
  [ "$(printenv "$n" >/dev/null 2>&1; echo $?)" != 0 ] || [ "$got" = "$want" ] || red "$n is \"$got\" in the run, and the caller's is \"$want\""
done
# Nothing else: every name the run reads is a kept one or begins with a kept prefix.
allowed() {
  case " $kept " in *" $1 "*) return 0 ;; esac
  case "$1" in LC_*|XDG_*) return 0 ;; esac
  return 1
}
extra=""
for n in $(printf '%s\n' "$clean" | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p'); do
  allowed "$n" || extra="$extra$n
"
done
# `env` itself may set _ and SHLVL's kin in some shells; those two are the shell's, not the caller's.
extra="$(printf '%s\n' "$extra" | grep -v -x -e _ -e PWD -e SHLVL -e OLDPWD || true)"
[ -z "$extra" ] || red "the run reads names that are not on the allowlist: $(printf '%s' "$extra" | tr '\n' ' ')"

# 3. The go env file: go-env refuses what go says it would build with. A stub go stands in for the
# file a person's `go env -w` wrote (a plant of the file itself would need a variable that names it),
# printing one value per key in the order go-env asks: GOVERSION GOFLAGS GOEXPERIMENT GOWASM GOFIPS140.
stubdir="$(mktemp -d)"
trap 'rm -rf "$stubdir"' EXIT
cat > "$stubdir/go" <<'EOF'
#!/bin/sh
printf '%s\n' "$STUB_GOVERSION" "$STUB_GOFLAGS" "$STUB_GOEXPERIMENT" "$STUB_GOWASM" "$STUB_GOFIPS140"
EOF
chmod +x "$stubdir/go"
GO_PIN=go1.27.4
export GO_PIN
plant_go() { # <the key planted> <GOVERSION> <GOFLAGS> <GOEXPERIMENT> <GOWASM> <GOFIPS140>
  out="$(STUB_GOVERSION="$2" STUB_GOFLAGS="$3" STUB_GOEXPERIMENT="$4" STUB_GOWASM="$5" STUB_GOFIPS140="$6" PATH="$stubdir:$PATH" sh "$here/go-env.sh" 2>&1)" && code=0 || code=$?
  if [ "$1" = none ]; then
    [ "$code" = 0 ] || red "go-env is red on go's defaults: $out"
  else
    [ "$code" != 0 ] || red "go-env passed with $1 planted in go's env file, and it must be red"
    printf '%s\n' "$out" | grep -F -q -- "go builds with $1=" || red "go-env is red for $1, but not by name: $out"
  fi
}
plant_go none go1.27.4 "" "" "" off
plant_go GOFLAGS go1.27.4 -tags=planted "" "" off
plant_go GOEXPERIMENT go1.27.4 "" planted "" off
plant_go GOWASM go1.27.4 "" "" satconv off
plant_go GOFIPS140 go1.27.4 "" "" "" latest
plant_go GOVERSION go1.0 "" "" "" off

[ "$fail" = 0 ] || exit 1
echo "env-plants: every planted switch reaches a child without the cleaner and none reaches the run through it; the kept names keep their values; go-env refuses each planted go env setting by name"
