#!/bin/sh
# The one reader of gate/pins.env: the hooks and the `pins` member both go through it, and
# nothing runs that file as shell.
#   sh gate/read-pins.sh            check the file; silent and 0 when it is exactly right
#   sh gate/read-pins.sh NAME       check the file, then print the value of NAME
# Right means: each line is blank, a comment, or one of the four names in its own form, and
# each of the four is there once. Any other line (GOSUMDB=off, a second TASK_PIN) is red, because
# the Taskfile's dotenv hands every line of the file to every member, and the checksum database
# and the toolchain are what make a version a pin.
set -eu
file=gate/pins.env
[ -f "$file" ] || { echo "pins: $file is missing" >&2; exit 1; }
awk '
  /^[[:space:]]*$/ || /^#/ { next }
  /^TASK_PIN=v[0-9]+\.[0-9]+\.[0-9]+$/ { t++; next }
  /^GITLEAKS_PIN=v[0-9]+\.[0-9]+\.[0-9]+$/ { g++; next }
  /^GRAGAS_PIN=[0-9a-f]{40}$/ { r++; next }
  /^GOTOOLCHAIN=go[0-9]+\.[0-9]+\.[0-9]+$/ { c++; next }
  { printf "pins: line %d is not a comment, a blank or a pin in its form: %s\n", NR, "(refused)" > "/dev/stderr"; bad++ }
  END {
    if (t != 1) { print "pins: TASK_PIN is not there once, as one version" > "/dev/stderr"; bad++ }
    if (g != 1) { print "pins: GITLEAKS_PIN is not there once, as one version" > "/dev/stderr"; bad++ }
    if (r != 1) { print "pins: GRAGAS_PIN is not there once, as one full commit" > "/dev/stderr"; bad++ }
    if (c != 1) { print "pins: GOTOOLCHAIN is not there once, as one Go version (go1.27.4)" > "/dev/stderr"; bad++ }
    exit bad > 0
  }
' "$file"
[ $# -eq 0 ] && exit 0
awk -F= -v n="$1" '$1 == n && !/^#/ { print substr($0, length(n) + 2) }' "$file"
