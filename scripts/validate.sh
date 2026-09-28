#!/bin/sh
# Run the codec, generation, tracestate, extraction, injection,
# continue-or-start and native HTTP header evidence gates on one explicitly
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
  tests/expected-tracestate.txt tests/expected-tracestate-example.txt tests/expected-outgoing.txt \
  tests/expected-outgoing-example.txt tests/expected-extract.txt tests/expected-extract-example.txt \
  tests/expected-inject.txt tests/expected-inject-example.txt tests/expected-continue.txt \
  tests/expected-continue-example.txt tests/expected-native-http.txt tests/expected-host-defs.txt "$build_dir/"
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

# The continue example prints new IDs on every run too. Name each generated
# ID by its order of appearance, T1, T2 ... for trace IDs and S1, S2 ... for
# span IDs, keep the received IDs as they are, and compare: the same name is
# the same ID, a new name is a new ID, and a received ID printed where a new
# one belongs fails the comparison.
check_continue_example() {
  awk '
    function named(id, kind) {
      if (id == "0af7651916cd43dd8448eb211c80319c" || id == "4bf92f3577b34da6a3ce929d0e0e4736" ||
        id == "b7ad6b7169203331" || id == "00f067aa0ba902b7") return id
      if (!((kind, id) in seen)) seen[kind, id] = kind (++count[kind])
      return seen[kind, id]
    }
    BEGIN {
      span = "[0-9a-f]"
      for (i = 1; i < 16; i++) span = span "[0-9a-f]"
      pattern = "-" span span "-" span "-"
    }
    {
      rest = $0
      line = ""
      while (match(rest, pattern)) {
        line = line substr(rest, 1, RSTART) named(substr(rest, RSTART + 1, 32), "T") "-" \
          named(substr(rest, RSTART + 34, 16), "S") "-"
        rest = substr(rest, RSTART + RLENGTH)
      }
      print line rest
    }
  ' "$1" > "$1.named.txt"
  compare_output tests/expected-continue-example.txt "$1.named.txt"
}

# Bend's verdict on the laws: ALL PROOFS CHECK when its checker accepts a
# proof of every law and no def that PROOF.bend imports relies on @unsafe or
# foreign code.
./bend packages/trace-context/PROOF.bend --check-only > "$build_dir/proofs.txt" 2>&1 || {
  cat "$build_dir/proofs.txt"; exit 1;
}
cat "$build_dir/proofs.txt"
[ "$(head -n 1 "$build_dir/proofs.txt")" = 'ALL PROOFS CHECK' ]
# generation.bend is the package's only module on the host's entropy: its
# operations, and only those, rely on the foreign effect of entropy.bend.
status=0
./bend packages/trace-context/generation.bend --check-only > "$build_dir/host-defs.txt" 2>&1 || status=$?
[ "$status" -eq 1 ] || { cat "$build_dir/host-defs.txt"; echo "Expected the host operations' verdict." >&2; exit 1; }
compare_output tests/expected-host-defs.txt "$build_dir/host-defs.txt"
echo "PASS: only the host operations of generation.bend rely on foreign code"

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
    grep -Fx -- '- expected : TC.LocalContext' "$build_dir/$fixture.txt" >/dev/null
    grep -Fx -- '- observed : TC.RemoteContext' "$build_dir/$fixture.txt" >/dev/null
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
run_logged direct-outgoing ./bend packages/trace-context/tests/OUTGOING.bend
compare_output tests/expected-outgoing.txt "$build_dir/direct-outgoing.txt"
echo "PASS: direct outgoing tracestate corpus"
run_logged direct-extract ./bend packages/trace-context/tests/EXTRACT.bend
compare_output tests/expected-extract.txt "$build_dir/direct-extract.txt"
echo "PASS: direct extraction corpus"
run_logged direct-inject ./bend packages/trace-context/tests/INJECT.bend
compare_output tests/expected-inject.txt "$build_dir/direct-inject.txt"
echo "PASS: direct injection and forwarding corpus"
run_logged direct-continue ./bend packages/trace-context/tests/CONTINUE.bend
compare_output tests/expected-continue.txt "$build_dir/direct-continue.txt"
echo "PASS: direct continue-or-start and sending corpus"
run_logged direct-native-http ./bend packages/trace-context/tests/NATIVE-HTTP.bend
compare_output tests/expected-native-http.txt "$build_dir/direct-native-http.txt"
echo "PASS: direct native HTTP header corpus"

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
  run_logged outgoing-compile ./bend packages/trace-context/tests/OUTGOING.bend -o "$build_dir/outgoing.js"
  run_logged outgoing node "$build_dir/outgoing.js"
  run_logged outgoing-example-compile ./bend packages/trace-context/examples/outgoing.bend \
    -o "$build_dir/outgoing-example.js"
  run_logged outgoing-example node "$build_dir/outgoing-example.js"
  run_logged extract-compile ./bend packages/trace-context/tests/EXTRACT.bend -o "$build_dir/extract.js"
  run_logged extract node "$build_dir/extract.js"
  run_logged extract-example-compile ./bend packages/trace-context/examples/extract.bend \
    -o "$build_dir/extract-example.js"
  run_logged extract-example node "$build_dir/extract-example.js"
  run_logged inject-compile ./bend packages/trace-context/tests/INJECT.bend -o "$build_dir/inject.js"
  run_logged inject node "$build_dir/inject.js"
  run_logged inject-example-compile ./bend packages/trace-context/examples/inject.bend \
    -o "$build_dir/inject-example.js"
  run_logged inject-example node "$build_dir/inject-example.js"
  run_logged continue-compile ./bend packages/trace-context/tests/CONTINUE.bend -o "$build_dir/continue.js"
  run_logged continue node "$build_dir/continue.js"
  run_logged continue-example-compile ./bend packages/trace-context/examples/continue.bend \
    -o "$build_dir/continue-example.js"
  run_logged continue-example node "$build_dir/continue-example.js"
  run_logged native-http-compile ./bend packages/trace-context/tests/NATIVE-HTTP.bend -o "$build_dir/native-http.js"
  run_logged native-http node "$build_dir/native-http.js"
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
  run_logged outgoing-compile ./bend packages/trace-context/tests/OUTGOING.bend -o "$build_dir/outgoing"
  run_logged outgoing "$build_dir/outgoing"
  run_logged outgoing-example-compile ./bend packages/trace-context/examples/outgoing.bend \
    -o "$build_dir/outgoing-example"
  run_logged outgoing-example "$build_dir/outgoing-example"
  run_logged extract-compile ./bend packages/trace-context/tests/EXTRACT.bend -o "$build_dir/extract"
  run_logged extract "$build_dir/extract"
  run_logged extract-example-compile ./bend packages/trace-context/examples/extract.bend \
    -o "$build_dir/extract-example"
  run_logged extract-example "$build_dir/extract-example"
  run_logged inject-compile ./bend packages/trace-context/tests/INJECT.bend -o "$build_dir/inject"
  run_logged inject "$build_dir/inject"
  run_logged inject-example-compile ./bend packages/trace-context/examples/inject.bend \
    -o "$build_dir/inject-example"
  run_logged inject-example "$build_dir/inject-example"
  run_logged continue-compile ./bend packages/trace-context/tests/CONTINUE.bend -o "$build_dir/continue"
  run_logged continue "$build_dir/continue"
  run_logged continue-example-compile ./bend packages/trace-context/examples/continue.bend \
    -o "$build_dir/continue-example"
  run_logged continue-example "$build_dir/continue-example"
  run_logged native-http-compile ./bend packages/trace-context/tests/NATIVE-HTTP.bend -o "$build_dir/native-http"
  run_logged native-http "$build_dir/native-http"
fi
compare_output tests/expected-codec.txt "$build_dir/codec.txt"
compare_output tests/expected-demo.txt "$build_dir/demo.txt"
compare_output tests/expected-generation.txt "$build_dir/generation.txt"
compare_output tests/expected-smoke.txt "$build_dir/smoke.txt"
compare_output tests/expected-tracestate.txt "$build_dir/tracestate.txt"
compare_output tests/expected-tracestate-example.txt "$build_dir/tracestate-example.txt"
compare_output tests/expected-outgoing.txt "$build_dir/outgoing.txt"
compare_output tests/expected-outgoing-example.txt "$build_dir/outgoing-example.txt"
compare_output tests/expected-extract.txt "$build_dir/extract.txt"
compare_output tests/expected-extract-example.txt "$build_dir/extract-example.txt"
compare_output tests/expected-inject.txt "$build_dir/inject.txt"
compare_output tests/expected-inject-example.txt "$build_dir/inject-example.txt"
compare_output tests/expected-continue.txt "$build_dir/continue.txt"
compare_output tests/expected-native-http.txt "$build_dir/native-http.txt"
check_generated_example "$build_dir/generate.txt"
check_continue_example "$build_dir/continue-example.txt"
echo "PASS: proofs, protocol, tracestate, outgoing, extraction, injection, continue-or-start and native HTTP header corpora, generation, construction rejections and examples ($mode)"
