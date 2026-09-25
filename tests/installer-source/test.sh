#!/bin/sh
# Test the public installer with the immutable official source checkout.
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
[ "$#" -eq 0 ] || { echo "Usage: $0" >&2; exit 2; }
result_dir="$repo_dir/build/installer-source"
mkdir -p "$result_dir"
: > "$result_dir/summary.txt"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/bend-source-tests.XXXXXXXX")
trap 'rm -rf "$work_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

fail() {
  printf 'FAIL: %s: %s\n' "$case_name" "$*" | tee -a "$result_dir/summary.txt" >&2
  cat "$result_dir/$case_name.log" >&2
  exit 1
}

run_installer() {
  case_name=$1
  expectation=$2
  destination=$3
  status=0
  "$repo_dir/scripts/setup-bend-source.sh" "$destination" \
    > "$result_dir/$case_name.log" 2>&1 || status=$?
  printf '%s\n' "$status" > "$result_dir/$case_name.status"
  case "$expectation" in
    success) [ "$status" -eq 0 ] || fail "installation failed with status $status" ;;
    failure) [ "$status" -ne 0 ] || fail "divergent installation was accepted" ;;
  esac
}

pass() {
  printf 'PASS: %s\n' "$case_name" | tee -a "$result_dir/summary.txt"
}

run_installer fresh-install success "$work_dir/source with spaces"
[ "$(git -C "$work_dir/source with spaces" rev-parse HEAD)" = \
  63bee70b55a71024d6bdcb49a745111bc54b114e ] || fail "incorrect release commit"
[ -f "$work_dir/source with spaces/bend2/main.ts" ] || fail "loader missing"
[ -f "$work_dir/source with spaces/bend2/base.bend" ] || fail "Base missing"
pass

run_installer repeated-install success "$work_dir/source with spaces"
[ "$(git -C "$work_dir/source with spaces" rev-parse HEAD)" = \
  63bee70b55a71024d6bdcb49a745111bc54b114e ] || fail "existing release commit changed"
pass

source_dir="$work_dir/source with spaces"
cp "$source_dir/bend2/main.ts" "$work_dir/main.ts.original"
printf '\n// Existing local edit.\n' >> "$source_dir/bend2/main.ts"
cp "$source_dir/bend2/main.ts" "$work_dir/main.ts.modified"
run_installer modified-source failure "$source_dir"
cmp "$source_dir/bend2/main.ts" "$work_dir/main.ts.modified" || fail "local edit was overwritten"
pass

git -C "$source_dir" update-index --assume-unchanged bend2/main.ts
run_installer hidden-modified-source failure "$source_dir"
cmp "$source_dir/bend2/main.ts" "$work_dir/main.ts.modified" || fail "hidden local edit was overwritten"
pass
git -C "$source_dir" update-index --no-assume-unchanged bend2/main.ts
cp "$work_dir/main.ts.original" "$source_dir/bend2/main.ts"

printf 'existing untracked content\n' > "$source_dir/local-note.txt"
cp "$source_dir/local-note.txt" "$work_dir/local-note.original"
run_installer untracked-source failure "$source_dir"
cmp "$source_dir/local-note.txt" "$work_dir/local-note.original" || fail "untracked content was overwritten"
pass
rm "$source_dir/local-note.txt"

mkdir "$source_dir/.tmp"
printf 'existing ignored content\n' > "$source_dir/.tmp/local-note.txt"
cp "$source_dir/.tmp/local-note.txt" "$work_dir/ignored-note.original"
run_installer ignored-source failure "$source_dir"
cmp "$source_dir/.tmp/local-note.txt" "$work_dir/ignored-note.original" || fail "ignored content was overwritten"
pass
rm "$source_dir/.tmp/local-note.txt"
rmdir "$source_dir/.tmp"

ln -s "$source_dir" "$work_dir/symlink"
run_installer existing-symlink failure "$work_dir/symlink"
[ -L "$work_dir/symlink" ] || fail "symlink replaced"
[ "$(readlink "$work_dir/symlink")" = "$source_dir" ] || fail "symlink retargeted"
pass

ln -s "$work_dir/absent" "$work_dir/dangling"
run_installer dangling-symlink failure "$work_dir/dangling"
[ -L "$work_dir/dangling" ] || fail "dangling symlink replaced"
[ ! -e "$work_dir/absent" ] || fail "dangling target created"
pass

git -C "$source_dir" -c user.name='Installer test' -c user.email='installer@example.invalid' \
  -c commit.gpgsign=false commit --quiet --allow-empty -m 'Different source revision'
different_commit=$(git -C "$source_dir" rev-parse HEAD)
run_installer different-revision failure "$source_dir"
[ "$(git -C "$source_dir" rev-parse HEAD)" = "$different_commit" ] || fail "existing revision changed"
pass

printf 'Source installer evidence: %s\n' "$result_dir"
