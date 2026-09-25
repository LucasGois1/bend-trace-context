#!/bin/sh
# The binary release omits the TypeScript loader used by Node --import.
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
[ "$#" -le 1 ] || { echo "Usage: $0 [destination]" >&2; exit 2; }
destination=${1:-$repo_dir/.tools/bend-source-2.0.27}
release_commit=63bee70b55a71024d6bdcb49a745111bc54b114e
source_url=https://github.com/bendlang/bend.git
command -v git >/dev/null || { echo "Required command: git" >&2; exit 1; }

mkdir -p "$(dirname -- "$destination")"
parent_dir=$(CDPATH='' cd -- "$(dirname -- "$destination")" && pwd)
destination="$parent_dir/$(basename -- "$destination")"
work_dir=$(mktemp -d "$parent_dir/.bend-source-setup.XXXXXXXX")
trap 'rm -rf "$work_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

matches_source() {
  [ -d "$destination" ] && [ ! -L "$destination" ] || return 1
  [ -d "$destination/.git" ] && [ ! -L "$destination/.git" ] || return 1
  [ "$(git --no-replace-objects -C "$destination" rev-parse HEAD)" = "$release_commit" ] || return 1
  # Use a fresh index so an existing checkout cannot hide edits with staged
  # changes, assume-unchanged, skip-worktree, or cached file metadata.
  GIT_INDEX_FILE="$work_dir/verification-index"
  export GIT_INDEX_FILE
  git --no-replace-objects -C "$destination" read-tree "$release_commit" || return 1
  git --no-replace-objects -C "$destination" update-index --refresh >/dev/null || return 1
  git --no-replace-objects -C "$destination" diff-files --quiet --no-ext-diff || return 1
  extra_files=$(git --no-replace-objects -C "$destination" ls-files --others) || return 1
  [ -z "$extra_files" ]
}

if [ -e "$destination" ] || [ -L "$destination" ]; then
  if ! matches_source; then
    echo "Existing destination differs from the verified source: $destination" >&2
    echo "Choose an empty destination or inspect the existing checkout." >&2
    exit 1
  fi
  printf 'Existing Bend source matches release: %s (%s)\n' "$destination" "$release_commit"
  exit 0
fi

git init --quiet "$work_dir/source"
git -C "$work_dir/source" fetch --quiet --depth 1 "$source_url" "$release_commit"
git -C "$work_dir/source" checkout --quiet --detach FETCH_HEAD
[ "$(git -C "$work_dir/source" rev-parse HEAD)" = "$release_commit" ] || {
  echo "Source commit mismatch; nothing was installed." >&2
  exit 1
}
[ -f "$work_dir/source/bend2/main.ts" ]
[ -f "$work_dir/source/bend2/base.bend" ]
mv "$work_dir/source" "$destination"
printf 'Installed Bend 2.0.27 source: %s (%s)\n' "$destination" "$release_commit"
