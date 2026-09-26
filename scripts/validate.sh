#!/bin/sh
# Run the codec, generation and tracestate evidence gates on one explicitly
# selected backend.
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
mode=${1:-native}
[ "$#" -le 1 ] || { echo "Usage: $0 [native|node]" >&2; exit 2; }
case "$mode" in native|node) ;; *) echo "Usage: $0 [native|node]" >&2; exit 2 ;; esac
cd "$repo_dir"
build_dir="$repo_dir/build/validation-$mode"
mkdir -p "$build_dir"
cp tests/expected-codec.txt tests/expected-demo.txt tests/expected-generation.txt tests/expected-smoke.txt \
  tests/expected-tracestate.txt tests/expected-tracestate-example.txt "$build_dir/"
{
echo "Package commit: $(git rev-parse HEAD)"
echo "Platform: $(uname -s) $(uname -m)"
uname -a
if [ "$(uname -s)" = Darwin ]; then sw_vers; else cat /etc/os-release; fi
./bend version
if [ "$mode" = node ]; then
  node_major=$(node -p 'process.versions.node.split(".")[0]')
  case "$node_major" in 22|24) ;; *) echo "Node 22 or 24 is required." >&2; exit 1 ;; esac
  node --version
else
  CC=${CC:-clang}
  export CC
  "$CC" --version
fi
} > "$build_dir/environment.txt" 2>&1
cat "$build_dir/environment.txt"

run_logged() {
  log_name=$1
  shift
  command_status=0
  "$@" > "$build_dir/$log_name.txt" 2> "$build_dir/$log_name.stderr.txt" || command_status=$?
  cat "$build_dir/$log_name.txt"
  cat "$build_dir/$log_name.stderr.txt" >&2
  return "$command_status"
}

compare_output() {
  if ! diff -u "$1" "$2" > "$2.diff.txt"; then
    cat "$2.diff.txt"
    return 1
  fi
}

# The generation example prints new IDs on every run: check a root and its
# child by shape, a shared trace ID and distinct span IDs.
check_generated_example() {
  lines=$(wc -l < "$1" | tr -d ' ')
  if [ "$lines" -ne 2 ] ||
    grep -Ev '^00-[0-9a-f]{32}-[0-9a-f]{16}-02$' "$1" >/dev/null ||
    ! awk -F- 'NR == 1 { trace = $2; span = $3 } NR == 2 { exit !($2 == trace && $3 != span) }' "$1"; then
    echo "Unexpected generation example output:" >&2
    cat "$1" >&2
    return 1
  fi
}

./bend packages/trace-context/PROOF.bend --check-only > "$build_dir/proofs.txt" 2>&1 || {
  cat "$build_dir/proofs.txt"; exit 1;
}
cat "$build_dir/proofs.txt"
grep -F 'All terms check.' "$build_dir/proofs.txt" >/dev/null
if grep -F '@unsafe' "$build_dir/proofs.txt" >/dev/null; then
  echo "The proof gate must not rely on @unsafe." >&2
  exit 1
fi

for fixture in zero_id wrong_length remote_as_local invalid_state_key; do
  status=0
  ./bend "packages/trace-context/tests/reject/$fixture.bend" --check-only > "$build_dir/$fixture.txt" 2>&1 || status=$?
  [ "$status" -eq 1 ] || { cat "$build_dir/$fixture.txt"; echo "Expected checker rejection (exit 1): $fixture" >&2; exit 1; }
  grep -F 'Location: invalid' "$build_dir/$fixture.txt" >/dev/null
  if [ "$fixture" = zero_id ]; then
    grep -F 'expected : True{}' "$build_dir/$fixture.txt" >/dev/null
    grep -F 'observed : False{}' "$build_dir/$fixture.txt" >/dev/null
  elif [ "$fixture" = invalid_state_key ]; then
    grep -F 'expected : False{}' "$build_dir/$fixture.txt" >/dev/null
    grep -F 'observed : True{}' "$build_dir/$fixture.txt" >/dev/null
  elif [ "$fixture" = wrong_length ]; then
    grep -E 'expected : .*Digits.Con<0n>' "$build_dir/$fixture.txt" >/dev/null
    grep -E 'observed : .*Digits.Nil' "$build_dir/$fixture.txt" >/dev/null
  else
    grep -E 'expected : .*trace_context\.LocalContext$' "$build_dir/$fixture.txt" >/dev/null
    grep -E 'observed : .*trace_context\.RemoteContext$' "$build_dir/$fixture.txt" >/dev/null
  fi
  echo "PASS: compile-time rejection of $fixture"
done

run_logged direct-codec ./bend packages/trace-context/tests/TEST.bend
compare_output tests/expected-codec.txt "$build_dir/direct-codec.txt"
echo "PASS: direct Bend protocol corpus"
run_logged direct-generation ./bend packages/trace-context/tests/GENERATION.bend
compare_output tests/expected-generation.txt "$build_dir/direct-generation.txt"
echo "PASS: direct deterministic generation"
run_logged direct-tracestate ./bend packages/trace-context/tests/TRACESTATE.bend
compare_output tests/expected-tracestate.txt "$build_dir/direct-tracestate.txt"
echo "PASS: direct tracestate corpus"

if [ "$mode" = node ]; then
  run_logged codec-compile ./bend packages/trace-context/tests/TEST.bend -o "$build_dir/codec.js"
  run_logged codec node "$build_dir/codec.js"
  run_logged demo-compile ./bend packages/trace-context/examples/demo.bend -o "$build_dir/demo.js"
  run_logged demo node "$build_dir/demo.js"
  run_logged generation-compile ./bend packages/trace-context/tests/GENERATION.bend -o "$build_dir/generation.js"
  run_logged generation node "$build_dir/generation.js"
  run_logged smoke-compile ./bend packages/trace-context/tests/SMOKE.bend -o "$build_dir/smoke.js"
  run_logged smoke node "$build_dir/smoke.js"
  run_logged generate-compile ./bend packages/trace-context/examples/generate.bend -o "$build_dir/generate.js"
  run_logged generate node "$build_dir/generate.js"
  run_logged tracestate-compile ./bend packages/trace-context/tests/TRACESTATE.bend -o "$build_dir/tracestate.js"
  run_logged tracestate node "$build_dir/tracestate.js"
  run_logged tracestate-example-compile ./bend packages/trace-context/examples/tracestate.bend \
    -o "$build_dir/tracestate-example.js"
  run_logged tracestate-example node "$build_dir/tracestate-example.js"
else
  run_logged codec-compile ./bend packages/trace-context/tests/TEST.bend -o "$build_dir/codec"
  run_logged codec "$build_dir/codec"
  run_logged demo-compile ./bend packages/trace-context/examples/demo.bend -o "$build_dir/demo"
  run_logged demo "$build_dir/demo"
  run_logged generation-compile ./bend packages/trace-context/tests/GENERATION.bend -o "$build_dir/generation"
  run_logged generation "$build_dir/generation"
  run_logged smoke-compile ./bend packages/trace-context/tests/SMOKE.bend -o "$build_dir/smoke"
  run_logged smoke "$build_dir/smoke"
  run_logged generate-compile ./bend packages/trace-context/examples/generate.bend -o "$build_dir/generate"
  run_logged generate "$build_dir/generate"
  run_logged tracestate-compile ./bend packages/trace-context/tests/TRACESTATE.bend -o "$build_dir/tracestate"
  run_logged tracestate "$build_dir/tracestate"
  run_logged tracestate-example-compile ./bend packages/trace-context/examples/tracestate.bend \
    -o "$build_dir/tracestate-example"
  run_logged tracestate-example "$build_dir/tracestate-example"
fi
compare_output tests/expected-codec.txt "$build_dir/codec.txt"
compare_output tests/expected-demo.txt "$build_dir/demo.txt"
compare_output tests/expected-generation.txt "$build_dir/generation.txt"
compare_output tests/expected-smoke.txt "$build_dir/smoke.txt"
compare_output tests/expected-tracestate.txt "$build_dir/tracestate.txt"
compare_output tests/expected-tracestate-example.txt "$build_dir/tracestate-example.txt"
check_generated_example "$build_dir/generate.txt"
echo "PASS: proofs, protocol and tracestate corpora, generation, construction rejections and examples ($mode)"
