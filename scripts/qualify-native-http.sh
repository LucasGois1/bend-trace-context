#!/bin/sh
# Run the pinned native transport consumer and its real HTTP observer tests.
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
[ "$#" -eq 0 ] || { echo "Usage: $0" >&2; exit 2; }
cd "$repo_dir"
pin=274591f1d1fcca2e4aa39ba65e505b32e2dbff21
dependency_dir="$repo_dir/vendor/bend-net"
result_dir="$repo_dir/build/native-http"

[ -f "$dependency_dir/http.bend" ] || {
  echo "Initialize the pinned HTTP dependency with: git submodule update --init --recursive" >&2
  exit 1
}
actual_pin=$(git -C "$dependency_dir" rev-parse HEAD)
[ "$actual_pin" = "$pin" ] || {
  echo "Unexpected bend-net source: $actual_pin (expected $pin)" >&2
  exit 1
}
mkdir -p "$result_dir"
{
  printf 'Package commit: %s\n' "$(git rev-parse HEAD)"
  printf 'bend-net commit: %s\n' "$actual_pin"
  printf 'Platform: %s %s\n' "$(uname -s)" "$(uname -m)"
  ./bend version
  clang --version
} > "$result_dir/environment.txt" 2>&1
cat "$result_dir/environment.txt"

./bend vendor/bend-net/PROOF.bend --check-only > "$result_dir/dependency-proofs.txt" 2>&1
grep -F 'All terms check.' "$result_dir/dependency-proofs.txt" >/dev/null
cat "$result_dir/dependency-proofs.txt"
./bend vendor/bend-net/json/PROOF.bend --check-only > "$result_dir/json-proofs.txt" 2>&1
grep -F 'All terms check' "$result_dir/json-proofs.txt" >/dev/null
cat "$result_dir/json-proofs.txt"
./bend vendor/bend-net/check.bend > "$result_dir/dependency-check.txt" 2>&1
./bend vendor/bend-net/json/check.bend > "$result_dir/json-check.txt" 2>&1

./bend tests/native/fixtures/transport-service.bend -o "$result_dir/transport-service"
BEND_NATIVE_HTTP_SERVICE="$result_dir/transport-service" \
  node --test --test-reporter=tap tests/native/transport.mjs \
  > "$result_dir/transport-tests.txt" 2>&1 || {
    cat "$result_dir/transport-tests.txt" >&2
    exit 1
  }
cat "$result_dir/transport-tests.txt"
grep -F '# skipped 0' "$result_dir/transport-tests.txt" >/dev/null

printf 'PASS: pinned native HTTP qualification; evidence: %s\n' "$result_dir"
