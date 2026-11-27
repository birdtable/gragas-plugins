#!/bin/sh
# sh gate/export.sh <commit> <folder>: the push's export of a commit, for the members to read.
#
# It makes <folder> a detached worktree of <commit> with no checkout, writes every file of the
# commit's tree from its blob as git ls-tree -r and git cat-file give it, and reads the tree into
# the worktree's own index. A checkout would not do: it applies a smudge filter, an eol, ident or
# working-tree-encoding attribute and sparse checkout, so the members would read bytes the commit
# does not hold. export-ignore does not apply here, since nothing is archived. Then it proves the
# folder against the tree, every file byte for byte and nothing more, and is red on a difference.
#
# The members keep git in the folder: its HEAD is the commit, and its index holds the commit's
# tree with no mark on any file. The caller removes the folder with git worktree remove.
#
# A push never reads replace refs, so neither does the export: with them read, ls-tree, cat-file
# and the proof would all see another commit's tree than the one pushed. A grafts file and a
# shallow clone change a commit's parents and have no switch, so they are refused.
set -eu
GIT_NO_REPLACE_OBJECTS=1
export GIT_NO_REPLACE_OBJECTS
bad() { echo "export: $*: nothing is pushed" >&2; exit 1; }
[ $# -eq 2 ] || { echo "export: usage: sh gate/export.sh <commit> <folder>" >&2; exit 2; }
[ -z "${GIT_GRAFT_FILE:-}" ] || bad "GIT_GRAFT_FILE is set, which changes a commit's parents"
grafts="$(git rev-parse --git-path info/grafts)"
[ ! -e "$grafts" ] && [ ! -L "$grafts" ] || bad "$grafts exists, which changes a commit's parents"
[ "$(git rev-parse --is-shallow-repository)" = false ] || bad "the clone is shallow, which hides a commit's parents"
commit="$(git rev-parse --verify --quiet "$1^{commit}")" || bad "$1 is not a commit"
dest="$2"
list="$(mktemp "${TMPDIR:-/tmp}/gragas-plugins-tree.XXXXXX")"
trap 'rm -f "$list"' EXIT
git -c core.quotePath=false ls-tree -r --full-tree "$commit" > "$list"
git worktree add --quiet --detach --no-checkout "$dest" "$commit"

cd "$dest"
# The caller's git variables would point git back at its own working tree and index.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_PREFIX \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
umask 022

# A path is written only inside the folder, and never as git's own.
safe() {
  case "$1" in ""|/*|\"*) bad "the path '$1' is empty, absolute or one git quotes" ;; esac
  case "/$1/" in */./*|*/../*|*//*) bad "the path '$1' has a . or .. part" ;; esac
  case "/$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')/" in */.git/*) bad "the path '$1' has a .git part" ;; esac
}

# Every folder first, then the files, then the links last, so no file is written through a link.
# A path met twice (two paths that differ only in case, on this file system) is red.
while IFS= read -r line; do
  meta="${line%%	*}"; path="${line#*	}"; mode="${meta%% *}"; sha="${meta##* }"
  safe "$path"
  mkdir -p -- "$(dirname -- "$path")"
  case "$mode" in
    100644|100755)
      [ ! -e "$path" ] && [ ! -L "$path" ] || bad "$path is written twice"
      git cat-file blob "$sha" > "$path"
      # BSD chmod takes no --; safe() has made the path relative, so ./ keeps it from an option.
      if [ "$mode" = 100755 ]; then chmod 755 "./$path"; else chmod 644 "./$path"; fi ;;
    120000) ;;
    160000) mkdir -p -- "$path" ;;
    *) bad "$path has the mode $mode, which the export does not know" ;;
  esac
done < "$list"
while IFS= read -r line; do
  meta="${line%%	*}"; path="${line#*	}"; mode="${meta%% *}"; sha="${meta##* }"
  [ "$mode" = 120000 ] || continue
  [ ! -e "$path" ] && [ ! -L "$path" ] || bad "$path is written twice"
  target="$(git cat-file blob "$sha"; echo x)"
  ln -s -- "${target%x}" "$path"
done < "$list"

# The index: the commit's tree, read with sparse checkout off, so no file is marked.
git read-tree --no-sparse-checkout "$commit"
marked="$(git ls-files -v | awk '$1 != "H"')"
[ -z "$marked" ] || bad "the export's index marks a file: $marked"

# The proof: each file is its blob, with its mode, and the folder holds no other file.
want=0
while IFS= read -r line; do
  meta="${line%%	*}"; path="${line#*	}"; mode="${meta%% *}"; sha="${meta##* }"
  case "$mode" in
    100644|100755)
      want=$((want + 1))
      [ -f "$path" ] && [ ! -L "$path" ] || bad "$path is not a file in the export"
      [ "$(git hash-object --no-filters -- "$path")" = "$sha" ] || bad "$path is not its blob $sha"
      if [ "$mode" = 100755 ]; then [ -x "$path" ] || bad "$path lost its x bit"; else [ ! -x "$path" ] || bad "$path gained an x bit"; fi ;;
    120000)
      want=$((want + 1))
      [ -L "$path" ] || bad "$path is not a link in the export"
      [ "$(printf '%s' "$(readlink -- "$path")" | git hash-object --stdin)" = "$sha" ] || bad "$path does not point where its blob says" ;;
    160000) [ -d "$path" ] || bad "$path is not a folder in the export" ;;
  esac
done < "$list"
have="$(find . -path ./.git -prune -o \( -type f -o -type l \) -print | wc -l | tr -d ' ')"
[ "$have" -eq "$want" ] || bad "the export holds $have files and the tree $want"
