#!/bin/sh
# Run the established codec evidence gates on one explicitly selected backend.
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
mode=${1:-native}
[ "$#" -le 1 ] || { echo "Usage: $0 [native|node]" >&2; exit 2; }
case "$mode" in native|node) ;; *) echo "Usage: $0 [native|node]" >&2; exit 2 ;; esac
cd "$repo_dir"
build_dir="$repo_dir/build/validation-$mode"
mkdir -p "$build_dir"
cp tests/expected-codec.txt tests/expected-demo.txt "$build_dir/"
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

./bend packages/trace-context/PROOF.bend --check-only > "$build_dir/proofs.txt" 2>&1 || {
  cat "$build_dir/proofs.txt"; exit 1;
}
cat "$build_dir/proofs.txt"
grep -F 'All terms check.' "$build_dir/proofs.txt" >/dev/null
if grep -F '@unsafe' "$build_dir/proofs.txt" >/dev/null; then
  echo "The proof gate must not rely on @unsafe." >&2
  exit 1
fi

for fixture in zero_id wrong_length remote_as_local; do
  status=0
  ./bend "packages/trace-context/tests/reject/$fixture.bend" --check-only > "$build_dir/$fixture.txt" 2>&1 || status=$?
  [ "$status" -eq 1 ] || { cat "$build_dir/$fixture.txt"; echo "Expected checker rejection (exit 1): $fixture" >&2; exit 1; }
  grep -F 'Location: invalid' "$build_dir/$fixture.txt" >/dev/null
  if [ "$fixture" = zero_id ]; then
    grep -F 'expected : True{}' "$build_dir/$fixture.txt" >/dev/null
    grep -F 'observed : False{}' "$build_dir/$fixture.txt" >/dev/null
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

if [ "$mode" = node ]; then
  run_logged codec-compile ./bend packages/trace-context/tests/TEST.bend -o "$build_dir/codec.js"
  run_logged codec node "$build_dir/codec.js"
  run_logged demo-compile ./bend packages/trace-context/examples/demo.bend -o "$build_dir/demo.js"
  run_logged demo node "$build_dir/demo.js"
else
  run_logged codec-compile ./bend packages/trace-context/tests/TEST.bend -o "$build_dir/codec"
  run_logged codec "$build_dir/codec"
  run_logged demo-compile ./bend packages/trace-context/examples/demo.bend -o "$build_dir/demo"
  run_logged demo "$build_dir/demo"
fi
compare_output tests/expected-codec.txt "$build_dir/codec.txt"
compare_output tests/expected-demo.txt "$build_dir/demo.txt"
echo "PASS: proofs, protocol corpus, construction rejections and example ($mode)"
