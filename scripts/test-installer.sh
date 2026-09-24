#!/bin/sh
# Exercise the installer's public CLI with real release bytes and controlled downloads.
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
[ "$#" -eq 0 ] || { echo "Usage: $0" >&2; exit 2; }
result_dir="$repo_dir/build/installer-tests"
mkdir -p "$result_dir"
: > "$result_dir/summary.txt"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/bend-installer-tests.XXXXXXXX")
trap 'rm -rf "$work_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

version=2.0.27
case "$(uname -s)/$(uname -m)" in
  Darwin/arm64) platform=darwin-arm64 ;;
  Linux/x86_64) platform=linux-x64 ;;
  *) echo "Supported test hosts: macOS ARM64 and Linux x86_64." >&2; exit 1 ;;
esac
{
  printf 'Revision: %s\n' "$(git -C "$repo_dir" rev-parse HEAD)"
  printf 'Platform: %s\n' "$(uname -sm)"
  printf 'Expected compiler: bend %s\n' "$version"
} > "$result_dir/environment.txt"
export BEND_NO_TELEMETRY=1
export INSTALLER_TEST_ARCHIVE="$work_dir/release.tar.gz"
# Fetch once from upstream. The fixture serves these unmodified official bytes
# for successful installs; it never substitutes the compiler or its verification.
curl --fail --silent --show-error --location --retry 3 --proto '=https' --tlsv1.2 \
  "https://github.com/bendlang/bend/releases/download/v$version/bend-$version-$platform.tar.gz" \
  -o "$INSTALLER_TEST_ARCHIVE" > "$result_dir/download.log" 2>&1 || {
    printf 'FAIL: could not fetch the official test archive\n' | tee -a "$result_dir/summary.txt" >&2
    cat "$result_dir/download.log" >&2
    exit 1
  }
export PATH="$repo_dir/tests/installer:$PATH"

fail() {
  printf 'FAIL: %s: %s\n' "$case_name" "$*" | tee -a "$result_dir/summary.txt" >&2
  cat "$result_dir/$case_name.log" >&2
  exit 1
}

run_installer() {
  case_name=$1
  response=$2
  expectation=$3
  destination=$4
  status=0
  INSTALLER_TEST_RESPONSE=$response "$repo_dir/scripts/setup-bend.sh" "$destination" \
    > "$result_dir/$case_name.log" 2>&1 || status=$?
  printf '%s\n' "$status" > "$result_dir/$case_name.status"
  case "$expectation" in
    success) [ "$status" -eq 0 ] || fail "installation failed with status $status" ;;
    failure) [ "$status" -ne 0 ] || fail "unsafe installation succeeded" ;;
  esac
}

pass() {
  printf 'PASS: %s\n' "$case_name" | tee -a "$result_dir/summary.txt"
}

assert_empty() {
  [ -z "$(find "$1" -mindepth 1 -print)" ] || fail "failed install left files behind"
}

assert_preserved() {
  diff -qr "$1" "$2" > "$result_dir/$case_name.diff" 2>&1 || fail "existing files were changed"
}

mkdir "$work_dir/valid"
run_installer fresh-install release success "$work_dir/valid/compiler"
[ "$("$work_dir/valid/compiler/bin/bend" version)" = "bend $version" ] || fail "wrong compiler version"
[ -f "$work_dir/valid/compiler/bend2/base.bend" ] || fail "missing compiler base library"
[ -d "$work_dir/valid/compiler/bend2/effs" ] || fail "missing compiler effect libraries"
pass

cp -R "$work_dir/valid/compiler" "$work_dir/original-compiler"
run_installer repeated-install release success "$work_dir/valid/compiler"
assert_preserved "$work_dir/original-compiler" "$work_dir/valid/compiler"
pass

mkdir "$work_dir/corrupt"
run_installer corrupt-download corrupt failure "$work_dir/corrupt/compiler"
assert_empty "$work_dir/corrupt"
pass

mkdir "$work_dir/failed-download"
run_installer failed-download failure failure "$work_dir/failed-download/compiler"
assert_empty "$work_dir/failed-download"
pass

run_installer failed-download-existing failure failure "$work_dir/valid/compiler"
assert_preserved "$work_dir/original-compiler" "$work_dir/valid/compiler"
pass

mkdir -p "$work_dir/divergent/compiler/nested"
printf 'user-owned content\n' > "$work_dir/divergent/compiler/nested/keep.txt"
printf 'hidden user-owned content\n' > "$work_dir/divergent/compiler/.keep"
cp -R "$work_dir/divergent" "$work_dir/original-divergent"
run_installer divergent-directory release failure "$work_dir/divergent/compiler"
assert_preserved "$work_dir/original-divergent" "$work_dir/divergent"
pass

mkdir "$work_dir/file"
printf 'user-owned file\n' > "$work_dir/file/compiler"
cp -R "$work_dir/file" "$work_dir/original-file"
run_installer existing-file release failure "$work_dir/file/compiler"
assert_preserved "$work_dir/original-file" "$work_dir/file"
pass

mkdir "$work_dir/symlink"
ln -s "$work_dir/valid/compiler" "$work_dir/symlink/compiler"
run_installer existing-symlink release failure "$work_dir/symlink/compiler"
[ -L "$work_dir/symlink/compiler" ] || fail "symlink was replaced"
[ "$(readlink "$work_dir/symlink/compiler")" = "$work_dir/valid/compiler" ] || fail "symlink was retargeted"
assert_preserved "$work_dir/original-compiler" "$work_dir/valid/compiler"
pass

mkdir "$work_dir/dangling"
ln -s "$work_dir/absent-target" "$work_dir/dangling/compiler"
run_installer dangling-symlink release failure "$work_dir/dangling/compiler"
[ -L "$work_dir/dangling/compiler" ] || fail "dangling symlink was replaced"
[ "$(readlink "$work_dir/dangling/compiler")" = "$work_dir/absent-target" ] || fail "dangling symlink was retargeted"
[ ! -e "$work_dir/absent-target" ] || fail "dangling symlink target was created"
pass

printf 'Installer evidence: %s\n' "$result_dir"
