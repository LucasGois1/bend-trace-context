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
  if [ "$mode" = node ]; then
    ./scripts/setup-bend-source.sh
  fi
} > "$output_dir/$mode-environment.txt" 2>&1 || {
  cat "$output_dir/$mode-environment.txt" >&2
  exit 1
}
cat "$output_dir/$mode-environment.txt"

if [ "$mode" = node ]; then
  run_logged node-tests npm run test:node
  grep -q '^# skipped 0$' "$output_dir/node-tests.txt"
else
  run_logged browser-tests npm run test:browser
  node --input-type=module -e '
    import { readFileSync } from "node:fs";
    const { stats } = JSON.parse(readFileSync("build/javascript/browser-results.json", "utf8"));
    if (stats.expected === 0 || stats.skipped || stats.unexpected || stats.flaky) {
      throw new Error("Browser qualification requires passing tests without skips or retries.");
    }
  '
fi
printf 'PASS: %s qualification; evidence: %s\n' "$mode" "$output_dir"
