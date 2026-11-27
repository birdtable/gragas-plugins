#!/bin/sh
# sh gate/secrets-plants.sh (task secrets-plants, with TASK_CMD set): the secret members on the tree the lander
# checks and on a tree that brings its own gitleaks files. The lander stages the pull
# request as a squash on a detached HEAD at the base (git merge --squash), so there HEAD is origin/main and the
# range of `secrets` holds no commit. Each case runs in a throwaway repository with a bare origin of its own, in a
# temporary folder; this clone's git is not touched.
#   - plant: the squash adds a file holding a throwaway private key. secrets-staged must be red and name the file;
#     secrets, the range, is green over it, which is why it is not the landing's only scan;
#   - clean: the same squash with no key. secrets-staged and secrets are both green;
#   - committed: the key is committed past origin/main and nothing is staged. secrets is red and names the file;
#   - root-config: the squash adds a root .gitleaks.toml (title "none") and a key; secrets-staged is red and names
#     the config, and so is the committed form in secrets (the config does not turn the scan off);
#   - ignore: the squash adds a .gitleaksignore and a key; red, naming the ignore file, staged and committed;
#   - what a tree can do to hide a key, each red staged and committed and naming the file: a gitleaks:allow
#     comment, a .gitattributes marking the file -diff, a key in a path holding gitleaks.toml, and a private key in
#     a .bin, a .pdf, go.sum and vendor/ (the paths the default allow-list skips; the second pass reads them);
#   - the allowlist (gate/gitleaks.toml): a lowercase linter name in a testdata/cases JSON file is green (the
#     control); a mixed-case token there, the same lowercase value at another path, the private key at that path
#     (another rule) and a lowercase value with a digit are each red; exhaustruct_v5 is green at its own path and
#     red anywhere else.
# The members are the Taskfile's own, run by task with SECRETS_DIR named: no case holds a copy of their command
# lines. The key is made here from random bytes, written only in the temporary folder, and gitleaks redacts it.
set -eu
here="$(pwd -P)"
raw="$(mktemp -d)"; tmp="$(cd "$raw" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "secrets-plants: $*" >&2; exit 1; }
[ -n "${TASK_CMD:-}" ] || fail "TASK_CMD is not set: run it as task secrets-plants"

GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
GIT_AUTHOR_NAME=secrets-plants GIT_AUTHOR_EMAIL=secrets-plants@example.invalid
GIT_COMMITTER_NAME=secrets-plants GIT_COMMITTER_EMAIL=secrets-plants@example.invalid
GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_AUTHOR_DATE GIT_COMMITTER_DATE
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

# The header and footer are spelled in two parts so this file holds no key of its own.
head='-----BEGIN PRIVATE'' KEY-----'
foot='-----END PRIVATE'' KEY-----'
key() { mkdir -p "$(dirname "$1")"; { echo "$head"; head -c 1200 /dev/urandom | base64 | tr -d '\n' | fold -w 64; echo; echo "$foot"; } > "$1"; }
put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }

cases=plugins/golangci-lint/1.0.2/testdata/cases/1-entries
other=plugins/golangci-lint/1.0.2/testdata/cases/2-other

# member <name> <dir>: a member of the Taskfile over a repository, its output in $out and its status in $rc.
member() {
	rc=0
	out="$(cd "$here" && $TASK_CMD --taskfile "$here/Taskfile.yml" "$1" SECRETS_DIR="$2" 2>&1)" || rc=$?
}

# A repository of one commit on main, pushed to its bare origin, with a branch "pr" that runs $2 (a function that
# writes the files). $3 is squash (the lander's tree: a detached HEAD at the base, the pull request squashed and
# staged) or commit (the pull request's commit is on main, past origin/main, and nothing is staged).
make() {
	d="$tmp/$1"
	git init -q --bare "$d.git"
	git init -q "$d"
	(
		cd "$d"
		git remote add origin "$d.git"
		echo "a clean file" > README
		git add -A && git commit -q -m base && git branch -M main && git push -q origin main
		git fetch -q origin
		git switch -q -c pr
		"$2"
		git add -A && git commit -q -m pr
		if [ "$3" = commit ]; then
			git switch -q main
			git merge -q --ff-only pr
		else
			git switch -q --detach origin/main
			git merge -q --squash pr
		fi
	)
}

# expect <label> <member> <red|green> <dir> [<file the output must name>]
expect() {
	member "$2" "$4"
	if [ "$3" = red ]; then
		[ "$rc" -ne 0 ] || fail "$1: $2 is green, want red"
		[ -z "${5:-}" ] || printf '%s\n' "$out" | grep -F -q -- "$5" || fail "$1: $2 is red, but does not name $5: $out"
	else
		[ "$rc" -eq 0 ] || fail "$1: $2 is red, want green: $out"
	fi
}

# A throwaway AWS access key id: AKIA and 16 random characters of base32.
akia() { printf 'AKIA%s' "$(LC_ALL=C tr -dc 'A-Z2-7' < /dev/urandom | head -c 16)"; }
w_akia() { printf 'aws_access_key_id = %s\n' "$(akia)" > k.txt; }
w_allow() { printf 'aws_access_key_id = %s # gitleaks:''allow\n' "$(akia)" > k.txt; }
w_attr() { printf 'k.txt -diff\n' > .gitattributes; key k.txt; }
w_name() { key docs/gitleaks.toml; }
w_name2() { key k.gitleaks.toml.txt; }
# The default config's global allow-list skips these paths; the second pass, the private-key rule alone, does not.
w_bin() { key k.bin; }
w_pdf() { key docs/k.pdf; }
w_gosum() { key go.sum; }
w_vendor() { key vendor/k.txt; }
w_plant() { key k.txt; }
w_clean() { echo "a clean file" > k.txt; }
w_root_config() { put .gitleaks.toml 'title = "none"'; key k.txt; }
w_ignore() { put .gitleaksignore 'k.txt:private-key:1'; key k.txt; }
# The control and the lowercase value at another path are the recorded entries list itself: gitleaks reads its
# linter names as a generic-api-key only in the list's context, and only the allow-list lets it through at its path.
real="$here/plugins/golangci-lint/1.0.2/testdata/cases/1-entries/response.json"
w_control() { mkdir -p "$cases" && cp "$real" "$cases/response.json"; }
# The name is spelled in two parts, so this file holds no value of its own that gitleaks would read.
v5=exhaustruct'_v5'
w_exhaust() { put "$cases/response.json" "{\"key\":\"$v5\"}"; }
w_exhaust_elsewhere() { put "$other/response.json" "{\"key\":\"$v5\"}"; }
# The next bundle's own case: the allow-list names each bundle's path.
w_exhaust_next() { put plugins/golangci-lint/1.0.0/testdata/cases/1-entries/response.json "{\"key\":\"$v5\"}"; }
w_mixed() { put "$cases/response.json" '{"key":"Xk9vQ2mZpL''4nR8tYw3bH"}'; }
w_elsewhere() { mkdir -p docs && cp "$real" docs/response.json; }
w_other_rule() { key "$cases/response.json"; }
w_digit() { put "$cases/response.json" '{"key":"xkqzvbnmlh''gfdsapwrt7"}'; }

for c in plant clean; do
	make "$c" "w_$c" squash
	expect "$c" secrets green "$tmp/$c"
	if [ "$c" = plant ]; then
		expect plant secrets-staged red "$tmp/$c" k.txt
		echo "secrets-plants: plant is red in secrets-staged, naming k.txt, and green in the range secrets (which reads no commit)"
	else
		expect clean secrets-staged green "$tmp/$c"
		echo "secrets-plants: clean is green in both"
	fi
done

make committed w_plant commit
expect committed secrets red "$tmp/committed" k.txt
echo "secrets-plants: committed is red in secrets, naming k.txt"

# A tree's own gitleaks file is refused, staged and committed, and names the file.
for c in root_config:.gitleaks.toml ignore:.gitleaksignore; do
	name="${c%%:*}"; file="${c#*:}"
	make "$name" "w_$name" squash
	expect "$name" secrets-staged red "$tmp/$name" "$file"
	make "$name-c" "w_$name" commit
	expect "$name-c" secrets red "$tmp/$name-c" "$file"
	echo "secrets-plants: a $file in the tree is red in secrets-staged and in secrets, naming it"
done

# What a tree can do to hide a key (planted by the review): each is red, staged and committed, and names
# the file. The control is the same key with nothing hiding it.
for c in akia:k.txt allow:k.txt attr:k.txt name:docs/gitleaks.toml name2:k.gitleaks.toml.txt bin:k.bin pdf:docs/k.pdf gosum:go.sum vendor:vendor/k.txt; do
	name="${c%%:*}"; file="${c#*:}"
	make "$name" "w_$name" squash
	expect "$name" secrets-staged red "$tmp/$name" "$file"
	make "$name-c" "w_$name" commit
	expect "$name-c" secrets red "$tmp/$name-c" "$file"
done
echo "secrets-plants: a key is red, staged and committed, with nothing hiding it, with a gitleaks:""allow comment, with a .gitattributes marking its file -diff, and in a path that holds gitleaks.toml; a private key is red in a .bin, a .pdf, go.sum and vendor/, which the default allow-list skips"

# A key added only in a merge's own resolution: git log -p prints no patch for a merge, so the scan reads the
# merge against its first parent (--diff-merges=first-parent). The merge is committed past origin/main; neither
# parent holds the key. The control is the same merge with no key (green).
make_merge() {
	d="$tmp/$1"
	git init -q --bare "$d.git"
	git init -q "$d"
	(
		cd "$d"
		git remote add origin "$d.git"
		echo "a clean file" > README
		git add -A && git commit -q -m base && git branch -M main && git push -q origin main
		git fetch -q origin
		git switch -q -c side
		echo side > side.txt
		git add -A && git commit -q -m side
		git switch -q main
		echo pr > pr.txt
		git add -A && git commit -q -m pr
		git merge -q --no-commit --no-ff side
		if [ "$2" = key ]; then key k.txt; else echo "a clean file" > k.txt; fi
		git add -A && git commit -q -m merge
	)
}
make_merge merge-clean clean
expect merge-clean secrets green "$tmp/merge-clean"
make_merge merge-key key
expect merge-key secrets red "$tmp/merge-key" k.txt
printf '%s\n' "$out" | grep -F -q private-key || fail "merge-key: secrets is red, but does not name the rule private-key: $out"
echo "secrets-plants: a key added only in a merge's resolution is red in secrets, naming private-key and k.txt; the same merge with no key is green"

# The allowlist: the control is green, and each way past it is red.
make control w_control squash
expect control secrets-staged green "$tmp/control"
make exhaust w_exhaust squash
expect exhaust secrets-staged green "$tmp/exhaust"
make exhaust_next w_exhaust_next squash
expect exhaust_next secrets-staged green "$tmp/exhaust_next"
echo "secrets-plants: a lowercase linter name and exhaustruct_v5 at either bundle's path are green in secrets-staged"
for c in mixed elsewhere other_rule digit exhaust_elsewhere; do
	make "$c" "w_$c" squash
	expect "$c" secrets-staged red "$tmp/$c" ".json"
done
echo "secrets-plants: a mixed-case token, the lowercase value at another path, another rule at the allowed path, a value with a digit and exhaustruct_v5 at another path are each red"
