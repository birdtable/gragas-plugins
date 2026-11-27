#!/bin/sh
# sh gate/release-plants.sh: the release of a bundle (gate/release.sh), proved in a throwaway repository
# with a bare origin of its own, both in a temporary folder. Nothing is pushed to this repository's origin,
# and no ref of this clone changes.
#
# The throwaway tree holds this tree's gate scripts and pins, and the clean control's plugin
# (gate/testdata/plugins/clean-control) as plugins/fixture/. First the control: plan on main, an annotated
# tag with the line plan prints, and tagged, which must rebuild the bundle twice to that digest and copy it
# out. Then each plant, which must be red with its own line:
#   - plan-tagged and plan-origin-tagged: plan of a tag that exists here, or only on origin;
#   - not-pushed: the tag is here and not on origin;
#   - not-origins: the tag here is another object than origin's tag of that name;
#   - two-lines and no-line: the tag's message carries the bundle line twice, or not at all;
#   - gowasm: GOWASM is set, so go would build other bytes;
#   - module: the tag is also the tag of a Go module folder of the plugin's name at the root;
#   - digest: the tag records a digest one digit off the bundle's;
#   - no-folder: the tag names a version whose folder the tree does not hold;
#   - version: the tag names a folder whose manifest says another version;
#   - name: the tag names a plugin folder whose manifest names another plugin;
#   - off-main and plan-off-main: the tag, or the plan, is on a commit origin's main does not hold;
#   - lightweight: the tag is not annotated;
#   - renamed: the tag object under the ref names another tag;
#   - stale-wasm: the tree carries a plugin.wasm that is not the pinned build;
#   - the ledger: with a release landed in RELEASES, a tag deleted and made again on another
#     commit is red at tagged, at plan and in gate/ledger.sh; a ledger line edited to match it, and a change
#     to the released folder, are red in gate/ledger.sh; the ledger of the control passes.
#     a released folder gone from the tree passes with its tag on origin, and is red with the tag away.
# And one that must pass: workspace, a go.work at the root naming a module the tree lacks, which the
# bundle's build must not read, so plan prints the control's line.
# A plant that passes, or is red for another reason, is red here.
set -eu
here="$(pwd -P)"
raw="$(mktemp -d)"; tmp="$(cd "$raw" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "release-plants: $*" >&2; exit 1; }

# The account's state folder (gragas#2361): the caller's XDG_STATE_HOME names a file, so a gragas that takes
# its lock or writes its run log there cannot (a second gragas holding that lock would red it the same way).
# Every run of release.sh below must stay green and leave the file as it is, which it does only by running
# the pinned gragas in a state folder of its own.
printf 'not a folder\n' > "$tmp/account-state"
XDG_STATE_HOME="$tmp/account-state"
export XDG_STATE_HOME

# The throwaway repository is held apart from the caller's git: no global or system config (a signing
# or hook setting there would change what is made), and an identity of its own for its commits and tags.
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
GIT_AUTHOR_NAME=release-plants GIT_AUTHOR_EMAIL=release-plants@example.invalid
GIT_COMMITTER_NAME=release-plants GIT_COMMITTER_EMAIL=release-plants@example.invalid
GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_AUTHOR_DATE GIT_COMMITTER_DATE
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

git init -q --bare "$tmp/origin.git"
git init -q "$tmp/work"
w="$tmp/work"
mkdir -p "$w/gate" "$w/plugins/fixture/0.0.1"
for f in build-wasm.sh export.sh ledger.sh pins.env read-pins.sh release.sh; do cp "$here/gate/$f" "$w/gate/$f"; done
c="$here/gate/testdata/plugins/clean-control/plugins/fixture"
cp -R "$c/0.0.1/." "$w/plugins/fixture/0.0.1/"
cp "$c/go.mod.txt" "$w/plugins/fixture/go.mod"
cp "$c/go.sum.txt" "$w/plugins/fixture/go.sum"
cp "$c/main.go.txt" "$w/plugins/fixture/main.go"
cd "$w"
git remote add origin "$tmp/origin.git"
: > RELEASES
git add -A && git commit -q -m "the control" && git branch -M main && git push -q origin main

# rel <args...>: release.sh as a person runs it, with the caller's git config back (the pinned gragas is
# fetched through it), and the throwaway's only for the plants' own commits and tags. extra holds env
# words for one plant's run (a drifted go setting), and is empty otherwise.
extra=""
# shellcheck disable=SC2086 # extra is env's words
rel() { env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_NOSYSTEM $extra sh gate/release.sh "$@"; }
# run <case> <want> <args...>: release.sh must be red, with the line want.
run() {
  case="$1"; want="$2"; shift 2
  if out="$(rel "$@" 2>&1)"; then
    echo "$out" >&2; fail "$case passed, and it must be red"
  fi
  printf '%s\n' "$out" | grep -F -q -- "$want" || { echo "$out" >&2; fail "$case is red, but not with \"$want\""; }
  echo "release-plants: $case is red as planted: $(printf '%s\n' "$out" | grep -F -- "$want" | head -n 1)"
}
# tag <name> <commit> <message>: an annotated tag, here and on origin.
tag() { printf '%s\n' "$3" > "$tmp/msg" && git tag -a -F "$tmp/msg" "$1" "$2" && git push -q origin "refs/tags/$1"; }
# untag <name>: the throwaway's tag removed here and on origin, so the next plant can use its name.
untag() { git tag -d "$1" >/dev/null && git push -q origin ":refs/tags/$1"; }

# The control.
planned="$(rel plan fixture/v0.0.1)" || fail "the control's plan is red: $planned"
line="$(printf '%s\n' "$planned" | sed -n 's/^release: plan: fixture\/v0\.0\.1 at [0-9a-f]*: //p')"
printf '%s\n' "$line" | grep -q -x -E 'bundle: sha256:[0-9a-f]{64}' || fail "the control's plan printed no bundle line: $planned"
echo "release-plants: the control's plan: $line"
tag fixture/v0.0.1 HEAD "fixture 0.0.1

$line"
done_line="$(rel tagged fixture/v0.0.1 "$tmp/out")" || fail "the control's release is red: $done_line"
[ -f "$tmp/out/plugin.wasm" ] && [ -f "$tmp/out/plugin.yaml" ] || fail "the control's release copied no bundle to its out folder"
echo "release-plants: the control passes: $done_line"
run plan-tagged "plan: the tag fixture/v0.0.1 exists in this clone" plan fixture/v0.0.1

# The origin guard: a release is of the tag origin holds, so a tag only here, and a tag here whose
# object is not origin's, are each red.
there="$(git rev-parse refs/tags/fixture/v0.0.1)"
git push -q origin :refs/tags/fixture/v0.0.1
run not-pushed "is $there in this clone and 'none' on origin" tagged fixture/v0.0.1
git push -q origin refs/tags/fixture/v0.0.1
git tag -d fixture/v0.0.1 >/dev/null
run plan-origin-tagged "plan: origin has the tag fixture/v0.0.1 already" plan fixture/v0.0.1
printf 'fixture 0.0.1, made again\n\n%s\n' "$line" > "$tmp/msg"
git tag -a -F "$tmp/msg" fixture/v0.0.1 HEAD
run not-origins "in this clone and '$there' on origin" tagged fixture/v0.0.1
untag fixture/v0.0.1

# two-lines: a message that carries the bundle line twice.
tag fixture/v0.0.1 HEAD "fixture 0.0.1

$line
$line"
run two-lines "does not carry one line 'bundle: sha256:<64 hex>'" tagged fixture/v0.0.1
untag fixture/v0.0.1
# no-line: a message that carries no bundle line.
tag fixture/v0.0.1 HEAD "fixture 0.0.1"
run no-line "does not carry one line 'bundle: sha256:<64 hex>'" tagged fixture/v0.0.1
untag fixture/v0.0.1

# The build's environment. gowasm: a drifted GOWASM, which changes the .wasm's bytes, is refused by
# name. workspace: a go.work at the root that names a module the tree lacks breaks any build that reads
# it, and the plan must still pass with the control's line, so no go.work is read; it runs with GOWORK
# unset, as a person's shell has it, since the hook sets GOWORK=off.
extra="GOWASM=satconv"
run gowasm "go builds with GOWASM='satconv'" plan fixture/v0.0.1
extra="-u GOWORK"
printf 'go 1.27.1\n\nuse (\n\t./plugins/fixture\n\t./missing\n)\n' > go.work
git add go.work && git commit -q -m "a go.work that breaks a build that reads it" && git push -q origin main
same="$(rel plan fixture/v0.0.1 2>&1)" || { echo "$same" >&2; fail "workspace is red: the build read the tree's go.work"; }
printf '%s\n' "$same" | grep -F -q -- "bundle: ${line#bundle: }" || { echo "$same" >&2; fail "workspace planned another bundle than the control's $line"; }
echo "release-plants: workspace passes with the control's line: the tree's go.work is not read"
extra=""
git rm -q go.work && git commit -q -m "no go.work" && git push -q origin main

# module: a plugin named for a Go module folder at the root, whose tags have the same form.
mkdir fixture && printf 'module example.invalid/fixture\n\ngo 1.27.1\n' > fixture/go.mod
git add fixture && git commit -q -m "a Go module folder named fixture" && git push -q origin main
run module "is also the tag of the Go module fixture/" plan fixture/v0.0.1
git rm -q -r fixture && git commit -q -m "no module folder named fixture" && git push -q origin main

# digest: the recorded digest one digit off.
sum="${line#bundle: sha256:}"
case "$sum" in 0*) off="1${sum#?}" ;; *) off="0${sum#?}" ;; esac
tag fixture/v0.0.1 HEAD "fixture 0.0.1

bundle: sha256:$off"
run digest "and the tag records sha256:$off" tagged fixture/v0.0.1
untag fixture/v0.0.1

# no-folder and version: a tag of a version the tree holds no folder of, and a folder whose manifest says 0.0.1.
tag fixture/v0.0.3 HEAD "fixture 0.0.3

$line"
run no-folder "holds no plugins/fixture/0.0.3/plugin.yaml" tagged fixture/v0.0.3
untag fixture/v0.0.3
mkdir plugins/fixture/0.0.2 && cp -R plugins/fixture/0.0.1/. plugins/fixture/0.0.2/
git add -A && git commit -q -m "a folder of 0.0.2 whose manifest says 0.0.1" && git push -q origin main
tag fixture/v0.0.2 HEAD "fixture 0.0.2

$line"
# gragas's own refusal, so the plant is red for the version and not for another fault of the bundle.
run version "plugin.yaml names fixture 0.0.1, and the lock installs it as fixture 0.0.2" tagged fixture/v0.0.2
untag fixture/v0.0.2

# name: a plugin folder named other whose manifest names fixture, also gragas's own refusal.
mkdir -p plugins/other && cp -R plugins/fixture/. plugins/other/
git add -A && git commit -q -m "a folder named other whose manifest says fixture" && git push -q origin main
tag other/v0.0.1 HEAD "other 0.0.1

$line"
run name "plugin.yaml names fixture 0.0.1, and the lock installs it as other 0.0.1" tagged other/v0.0.1
untag other/v0.0.1

# off-main: the control's tree on a commit of a side branch.
git switch -q -c side
git commit -q --allow-empty -m "a commit main does not hold" && git push -q origin side
run plan-off-main "plan: HEAD is" plan fixture/v0.0.9
tag fixture/v0.0.1 HEAD "fixture 0.0.1

$line"
run off-main "which is not on origin's main" tagged fixture/v0.0.1
untag fixture/v0.0.1
git switch -q main

# lightweight, and renamed: a tag object made under another name, put under this one's ref.
git tag fixture/v0.0.1 HEAD && git push -q origin refs/tags/fixture/v0.0.1
run lightweight "is lightweight: a release tag is annotated" tagged fixture/v0.0.1
untag fixture/v0.0.1
printf 'other 0.0.1\n\n%s\n' "$line" > "$tmp/msg"
git tag -a -F "$tmp/msg" other/v0.0.1 HEAD
git update-ref refs/tags/fixture/v0.0.1 "$(git rev-parse refs/tags/other/v0.0.1)"
git tag -d other/v0.0.1 >/dev/null
git push -q origin refs/tags/fixture/v0.0.1
run renamed "names itself 'other/v0.0.1'" tagged fixture/v0.0.1
untag fixture/v0.0.1

# stale-wasm: a folder of 0.0.4 that carries a plugin.wasm of other bytes.
mkdir plugins/fixture/0.0.4 && cp -R plugins/fixture/0.0.1/. plugins/fixture/0.0.4/
sed 's/^version: 0\.0\.1$/version: 0.0.4/' plugins/fixture/0.0.1/plugin.yaml > plugins/fixture/0.0.4/plugin.yaml
printf 'not the build\n' > plugins/fixture/0.0.4/plugin.wasm
git add -A && git commit -q -m "a folder of 0.0.4 with a stale plugin.wasm" && git push -q origin main
tag fixture/v0.0.4 HEAD "fixture 0.0.4

$line"
run stale-wasm "plugins/fixture/0.0.4 carries is not what" tagged fixture/v0.0.4

# The ledger. A release of 0.0.5 is planned, tagged, released, and its line landed on main;
# the ledger member passes. Then a tag of the name made again on another commit is red at tagged, at plan
# (with the tag away) and in the ledger member; a ledger line edited to match it, and an edit of the
# released folder, are red in the ledger member.
mkdir plugins/fixture/0.0.5 && cp -R plugins/fixture/0.0.1/. plugins/fixture/0.0.5/
sed 's/^version: 0\.0\.1$/version: 0.0.5/' plugins/fixture/0.0.1/plugin.yaml > plugins/fixture/0.0.5/plugin.yaml
git add -A && git commit -q -m "a folder of 0.0.5" && git push -q origin main
planned5="$(rel plan fixture/v0.0.5)" || fail "the plan of 0.0.5 is red: $planned5"
line5="$(printf '%s\n' "$planned5" | sed -n 's/^release: plan: fixture\/v0\.0\.5 at [0-9a-f]*: //p')"
tag fixture/v0.0.5 HEAD "fixture 0.0.5

$line5"
obj5="$(git rev-parse refs/tags/fixture/v0.0.5)"
commit5="$(git rev-parse HEAD)"
released="$(rel tagged fixture/v0.0.5)" || fail "the release of 0.0.5 is red: $released"
want5="fixture/v0.0.5 $obj5 $commit5 sha256:${line5#bundle: sha256:}"
printf '%s\n' "$released" | grep -F -q -- "land this one in RELEASES on main: $want5" || { echo "$released" >&2; fail "tagged did not print the ledger line $want5"; }
printf '%s\n' "$want5" >> RELEASES
git add RELEASES && git commit -q -m "the ledger line of 0.0.5" && git push -q origin main
led() { env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_NOSYSTEM sh gate/ledger.sh; }
ledout="$(led 2>&1)" || { echo "$ledout" >&2; fail "the ledger control is red"; }
echo "release-plants: the ledger control passes: $ledout"
released="$(rel tagged fixture/v0.0.5)" || fail "the release of 0.0.5 with its line landed is red: $released"
# moved: the tag deleted, here and on origin, and made again on another commit (the ledger line has the
# first). The plan is red with the tag away, and tagged and the ledger member with the new one.
untag fixture/v0.0.5
run ledger-plan "plan: the ledger records fixture/v0.0.5 already" plan fixture/v0.0.5
git commit -q --allow-empty -m "another commit of main" && git push -q origin main
tag fixture/v0.0.5 HEAD "fixture 0.0.5, made again

$line5"
moved5="$(git rev-parse refs/tags/fixture/v0.0.5)"
run ledger-moved "and the ledger records $obj5" tagged fixture/v0.0.5
if out="$(led 2>&1)"; then echo "$out" >&2; fail "ledger-member-moved passed, and it must be red"; fi
printf '%s\n' "$out" | grep -F -q -- "the ledger records fixture/v0.0.5 as $obj5, and origin has" || { echo "$out" >&2; fail "ledger-member-moved is red, but not for the moved tag"; }
echo "release-plants: ledger-member-moved is red as planted: $(printf '%s\n' "$out" | head -n 1)"
untag fixture/v0.0.5
git tag fixture/v0.0.5 "$obj5" && git push -q origin refs/tags/fixture/v0.0.5

# The ledger edited to match: a commit, not pushed, whose line names the moved tag's object.
printf "fixture/v0.0.5 %s %s sha256:%s\n" "$moved5" "$commit5" "${line5#bundle: sha256:}" > RELEASES
git add RELEASES && git commit -q -m "a ledger line edited"
if out="$(led 2>&1)"; then echo "$out" >&2; fail "ledger-edited passed, and it must be red"; fi
printf '%s\n' "$out" | grep -F -q -- "a line of the ledger on origin's main is not in this one" || { echo "$out" >&2; fail "ledger-edited is red, but not for the lost line"; }
echo "release-plants: ledger-edited is red as planted: $(printf '%s\n' "$out" | grep -F -- "is not in this one" | head -n 1)"
git reset -q --hard origin/main

# frozen: the released folder changed in a commit, not pushed.
printf 'description: changed after release\n' >> plugins/fixture/0.0.5/plugin.yaml
git add -A && git commit -q -m "a released folder edited"
if out="$(led 2>&1)"; then echo "$out" >&2; fail "ledger-frozen passed, and it must be red"; fi
printf '%s\n' "$out" | grep -F -q -- "a released bundle never changes" || { echo "$out" >&2; fail "ledger-frozen is red, but not for the folder"; }
echo "release-plants: ledger-frozen is red as planted: $(printf '%s\n' "$out" | head -n 1)"
git reset -q --hard origin/main

# gone: the released folder leaves the tree, in a commit not pushed. With its tag on origin and the
# digest of the tag's message the ledger's, it passes; with the tag away it is red.
git rm -q -r plugins/fixture/0.0.5
git commit -q -m "a released folder leaves the tree"
ledout="$(led 2>&1)" || { echo "$ledout" >&2; fail "ledger-gone with its tag and digest is red, and it must pass"; }
echo "release-plants: ledger-gone passes as planted: $ledout"
untag fixture/v0.0.5
if out="$(led 2>&1)"; then echo "$out" >&2; fail "ledger-gone-untagged passed, and it must be red"; fi
printf '%s\n' "$out" | grep -F -q -- "the ledger records fixture/v0.0.5 as $obj5, and origin has 'none'" || { echo "$out" >&2; fail "ledger-gone-untagged is red, but not for the missing tag"; }
echo "release-plants: ledger-gone-untagged is red as planted: $(printf '%s\n' "$out" | head -n 1)"
git tag fixture/v0.0.5 "$obj5" && git push -q origin refs/tags/fixture/v0.0.5
git reset -q --hard origin/main

# emptied and comments-only: a ledger with its lines gone must not read as "no release yet", or the
# moved tag would pass. A commit each, not pushed.
: > RELEASES
git add RELEASES && git commit -q -m "an emptied ledger"
if out="$(led 2>&1)"; then echo "$out" >&2; fail "ledger-emptied passed, and it must be red"; fi
printf '%s\n' "$out" | grep -F -q -- "a line of the ledger on origin's main is not in this one" || { echo "$out" >&2; fail "ledger-emptied is red, but not for the lost line"; }
echo "release-plants: ledger-emptied is red as planted: $(printf '%s\n' "$out" | head -n 1 | cut -c1-120)"
printf '# no releases\n' > RELEASES
git add RELEASES && git commit -q -m "a comments-only ledger"
if out="$(led 2>&1)"; then echo "$out" >&2; fail "ledger-comments passed, and it must be red"; fi
printf '%s\n' "$out" | grep -F -q -- "a line of the ledger on origin's main is not in this one" || { echo "$out" >&2; fail "ledger-comments is red, but not for the lost line"; }
echo "release-plants: ledger-comments is red as planted: $(printf '%s\n' "$out" | head -n 1 | cut -c1-120)"
git reset -q --hard origin/main
cmp -s "$tmp/account-state" - <<EOF || fail "a run of release.sh used the caller's state folder (gragas#2361)"
not a folder
EOF
echo "release-plants: no run took the lock or wrote the run log of the caller's state folder"
