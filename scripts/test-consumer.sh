#!/bin/sh
# Exercise a fresh pinned dependency checkout from an independent application.
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
mode=${1:-native}
source_repo=${2:-$repo_dir}
revision=${3:-$(git -C "$repo_dir" rev-parse HEAD)}
[ "$#" -le 3 ] || { echo "Usage: $0 [native|node] [repository] [full-commit-sha]" >&2; exit 2; }
case "$mode" in native|node) ;; *) echo "Usage: $0 [native|node] [repository] [full-commit-sha]" >&2; exit 2 ;; esac
case "$revision" in *[!0-9a-f]*|'') echo "Use a full lowercase Git commit SHA." >&2; exit 2 ;; esac
[ "${#revision}" -eq 40 ] || { echo "Use a full 40-character Git commit SHA." >&2; exit 2; }

test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bend-consumer.XXXXXXXX")
cleanup() {
  if [ "${KEEP_TEST_OUTPUT:-0}" = 1 ]; then
    echo "Consumer files retained at: $test_dir"
  else
    rm -rf "$test_dir"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
dependency="$test_dir/deps/bend-trace-context"
mkdir -p "$test_dir/deps" "$test_dir/package-cache" "$test_dir/build"
git clone --quiet --no-local --no-checkout "$source_repo" "$dependency"
git -C "$dependency" checkout --quiet --detach "$revision"
[ "$(git -C "$dependency" rev-parse HEAD)" = "$revision" ]
# Only the consumer fixture is copied; implementation comes from the clone.
cp "$repo_dir/tests/consumer/main.bend" "$test_dir/main.bend"
[ ! -e "$dependency/.tools" ] || { echo "Fresh checkout inherited ignored tools." >&2; exit 1; }
export BEND_LIB="$test_dir/package-cache"
export BEND_NO_TELEMETRY=1
echo "Dependency commit: $revision"
echo "Consumer platform: $(uname -s) $(uname -m)"
uname -a
if [ "$(uname -s)" = Darwin ]; then sw_vers; else cat /etc/os-release; fi
"$dependency/scripts/setup-bend.sh"
"$dependency/bend" version
cd "$test_dir"
"$dependency/bend" main.bend > build/direct.txt
diff -u "$repo_dir/tests/consumer/expected.txt" build/direct.txt
if [ "$mode" = node ]; then
  node_major=$(node -p 'process.versions.node.split(".")[0]')
  case "$node_major" in 22|24) ;; *) echo "Node 22 or 24 is required." >&2; exit 1 ;; esac
  node --version
  "$dependency/bend" main.bend -o build/consumer.js
  node build/consumer.js > build/actual.txt
else
  CC=${CC:-clang}
  export CC
  "$CC" --version
  "$dependency/bend" main.bend -o build/consumer
  ./build/consumer > build/actual.txt
fi
diff -u "$repo_dir/tests/consumer/expected.txt" build/actual.txt
cat build/actual.txt
echo "PASS: independent pinned consumer ($mode)"
