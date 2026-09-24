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

evidence_dir="$repo_dir/build/consumer-$mode"
rm -rf "$evidence_dir"
mkdir -p "$evidence_dir"
printf 'Dependency commit: %s\nConsumer backend: %s\n' "$revision" "$mode" > "$evidence_dir/revision.txt"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bend-consumer.XXXXXXXX")
cleanup() {
  echo "Consumer evidence: $evidence_dir"
  if [ "${KEEP_TEST_OUTPUT:-0}" = 1 ]; then
    echo "Consumer files retained at: $test_dir"
  else
    rm -rf "$test_dir"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

# Keep diagnostics even when a command fails, without retaining downloaded tools.
run_logged() {
  log_name=$1
  shift
  command_status=0
  "$@" > "$evidence_dir/$log_name.stdout" 2> "$evidence_dir/$log_name.stderr" || command_status=$?
  cat "$evidence_dir/$log_name.stdout"
  cat "$evidence_dir/$log_name.stderr" >&2
  return "$command_status"
}

dependency="$test_dir/deps/bend-trace-context"
mkdir -p "$test_dir/deps" "$test_dir/package-cache" "$test_dir/build"
run_logged clone git clone --quiet --no-local --no-checkout "$source_repo" "$dependency"
run_logged checkout git -C "$dependency" checkout --quiet --detach "$revision"
[ "$(git -C "$dependency" rev-parse HEAD)" = "$revision" ]
# The README program comes from the exact dependency revision being exercised.
# A missing, duplicate or malformed marked fence must fail, not skip the check.
# shellcheck disable=SC2016 # $0 belongs to awk, not the shell.
run_logged readme-extract awk '
  /^<!-- test:readme-consumer:start -->$/ {
    if (state != 0) { invalid = 1; exit 1 }
    state = 1
    next
  }
  /^<!-- test:readme-consumer:end -->$/ {
    if (state != 3) { invalid = 1; exit 1 }
    state = 4
    next
  }
  state == 1 {
    if ($0 != "```bend") { invalid = 1; exit 1 }
    state = 2
    next
  }
  state == 2 {
    if ($0 == "```") { state = 3; next }
    print
    lines++
    next
  }
  state == 3 { invalid = 1; exit 1 }
  END {
    if (invalid || state != 4 || !lines) {
      print "Expected exactly one marked Bend consumer example in README.md." > "/dev/stderr"
      exit 1
    }
  }
' "$dependency/README.md"
cp "$evidence_dir/readme-extract.stdout" "$test_dir/readme.bend"
# Independent fixtures and expectations are test inputs, never package internals.
cp "$repo_dir/tests/consumer/main.bend" "$test_dir/consumer.bend"
cp "$repo_dir/tests/consumer/expected.txt" "$evidence_dir/consumer.expected"
cp "$repo_dir/tests/readme/expected.txt" "$evidence_dir/readme.expected"
[ ! -e "$dependency/.tools" ] || { echo "Fresh checkout inherited ignored tools." >&2; exit 1; }
export BEND_LIB="$test_dir/package-cache"
export BEND_NO_TELEMETRY=1
{
  echo "Dependency commit: $revision"
  echo "Consumer platform: $(uname -s) $(uname -m)"
  uname -a
  if [ "$(uname -s)" = Darwin ]; then sw_vers; else cat /etc/os-release; fi
  if [ "$mode" = node ]; then
    node_major=$(node -p 'process.versions.node.split(".")[0]')
    case "$node_major" in 22|24) ;; *) echo "Node 22 or 24 is required." >&2; exit 1 ;; esac
    node --version
  else
    CC=${CC:-clang}
    export CC
    "$CC" --version
  fi
} > "$evidence_dir/environment.txt" 2>&1
cat "$evidence_dir/environment.txt"
run_logged setup "$dependency/scripts/setup-bend.sh"
run_logged compiler "$dependency/bend" version
cd "$test_dir"
for program in consumer readme; do
  run_logged "$program-direct" "$dependency/bend" "$program.bend"
  run_logged "$program-direct-diff" diff -u "$evidence_dir/$program.expected" "$evidence_dir/$program-direct.stdout"
  if [ "$mode" = node ]; then
    run_logged "$program-compile" "$dependency/bend" "$program.bend" -o "build/$program.js"
    run_logged "$program-compiled" node "build/$program.js"
  else
    run_logged "$program-compile" "$dependency/bend" "$program.bend" -o "build/$program"
    run_logged "$program-compiled" "./build/$program"
  fi
  run_logged "$program-compiled-diff" diff -u "$evidence_dir/$program.expected" "$evidence_dir/$program-compiled.stdout"
  echo "PASS: independent pinned $program ($mode)"
done
