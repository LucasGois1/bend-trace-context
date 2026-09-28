#!/bin/sh
# Qualify the real Bend package in the selected host, retaining diagnostics.
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
mode=${1:-node}
[ "$#" -le 1 ] || { echo "Usage: $0 [node|browser]" >&2; exit 2; }
case "$mode" in node|browser) ;; *) echo "Usage: $0 [node|browser]" >&2; exit 2 ;; esac
cd "$repo_dir"
output_dir="$repo_dir/build/javascript"
mkdir -p "$output_dir"
export BEND_NO_TELEMETRY=1

run_logged() {
  log_name=$1
  shift
  command_status=0
  "$@" > "$output_dir/$log_name.txt" 2>&1 || command_status=$?
  cat "$output_dir/$log_name.txt"
  return "$command_status"
}

{
  printf 'Package commit: %s\n' "$(git rev-parse HEAD)"
  printf 'Working-tree changes (empty for a clean checkout):\n'
  git status --short
  printf 'Qualification: %s\n' "$mode"
  uname -a
  if [ "$(uname -s)" = Darwin ]; then sw_vers; else cat /etc/os-release; fi
  ./bend version
  node --version
  npm --version
  node -p '"Playwright " + require("@playwright/test/package.json").version'
  node_major=$(node -p 'process.versions.node.split(".")[0]')
  case "$node_major" in 22|24) ;; *) echo "Node 22 or 24 is required." >&2; exit 1 ;; esac
} > "$output_dir/$mode-environment.txt" 2>&1 || {
  cat "$output_dir/$mode-environment.txt" >&2
  exit 1
}
cat "$output_dir/$mode-environment.txt"

# The facade runs the committed ES module of trace_context.bend, which must be
# the pinned compiler's build of the sources under test.
run_logged "$mode-module" ./scripts/build-js.sh --check

if [ "$mode" = node ]; then
  run_logged node-tests npm run test:node
  grep -q '^# skipped 0$' "$output_dir/node-tests.txt"
else
  run_logged browser-tests npm run test:browser
  node tests/browser/check-results.mjs build/javascript/browser-results.json
  # The bundle that the browsers ran must be reproducible: a second build of
  # the same pages gives the same files, byte for byte.
  rm -rf build/browser-rebuild
  run_logged browser-rebuild env BROWSER_OUT=build/browser-rebuild npm run build:browser
  run_logged browser-reproducible diff -r build/browser build/browser-rebuild
  run_logged browser-bundle cksum build/browser/*
  # A copy of the sources at another path gives the same scripts under other
  # names: the bundler names its chunks by a hash of where the sources are.
  relocated=$(mktemp -d "${TMPDIR:-/tmp}/bend-browser.XXXXXXXX")
  mkdir -p "$relocated/examples" "$relocated/packages"
  cp -R examples/javascript "$relocated/examples/"
  cp -R packages/trace-context "$relocated/packages/"
  # shellcheck disable=SC2317,SC2329 # run_logged invokes these functions.
  relocated_build() {
    ./bend "$relocated/examples/javascript/index.html" -o "$relocated/out" &&
      ./bend "$relocated/examples/javascript/fetch.html" -o "$relocated/out"
  }
  # shellcheck disable=SC2317,SC2329
  scripts_of() { for script in "$1"/*.js; do cksum < "$script"; done | sort; }
  run_logged browser-relocated relocated_build
  scripts_of build/browser > "$output_dir/browser-scripts.txt"
  scripts_of "$relocated/out" > "$output_dir/browser-relocated-scripts.txt"
  rm -rf "$relocated"
  run_logged browser-relocatable diff "$output_dir/browser-scripts.txt" "$output_dir/browser-relocated-scripts.txt"
fi
printf 'PASS: %s qualification; evidence: %s\n' "$mode" "$output_dir"
