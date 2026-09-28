#!/bin/sh
# Exercise a fresh pinned dependency checkout from an independent application.
# In node mode, the application also installs the JavaScript facade from the
# checkout and runs it on the checkout's own Bend module loader. In browser
# mode, it installs the facade into a page, bundles the page twice with the
# checkout's official bundler, requires identical bundles, and runs the page
# in Chromium, Firefox and WebKit.
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
mode=${1:-native}
source_repo=${2:-$repo_dir}
revision=${3:-$(git -C "$repo_dir" rev-parse HEAD)}
usage="Usage: $0 [native|node|browser] [repository] [full-commit-sha]"
[ "$#" -le 3 ] || { echo "$usage" >&2; exit 2; }
case "$mode" in native|node|browser) ;; *) echo "$usage" >&2; exit 2 ;; esac
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
# The README programs come from the exact dependency revision being exercised.
# A missing, duplicate or malformed marked fence must fail, not skip the check.
extract_example() {
  marker=$1
  fence=$2
  # shellcheck disable=SC2016 # $0 belongs to awk, not the shell.
  run_logged "$marker-extract" awk -v marker="$marker" -v fence="$fence" '
    $0 == "<!-- test:" marker ":start -->" {
      if (state != 0) { invalid = 1; exit 1 }
      state = 1
      next
    }
    $0 == "<!-- test:" marker ":end -->" {
      if (state != 3) { invalid = 1; exit 1 }
      state = 4
      next
    }
    state == 1 {
      if ($0 != "```" fence) { invalid = 1; exit 1 }
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
        print "Expected exactly one marked " marker " example in README.md." > "/dev/stderr"
        exit 1
      }
    }
  ' "$dependency/README.md"
}
extract_example readme-consumer bend
cp "$evidence_dir/readme-consumer-extract.stdout" "$test_dir/readme.bend"
# Independent fixtures and expectations are test inputs, never package internals.
cp "$repo_dir/tests/consumer/main.bend" "$test_dir/consumer.bend"
cp "$repo_dir/tests/consumer/expected.txt" "$evidence_dir/consumer.expected"
cp "$repo_dir/tests/readme/expected.txt" "$evidence_dir/readme.expected"
if [ "$mode" = node ]; then
  extract_example readme-javascript js
  cp "$evidence_dir/readme-javascript-extract.stdout" "$test_dir/readme-javascript.mjs"
  cp "$repo_dir/tests/consumer/facade.mjs" "$test_dir/facade.mjs"
  cp "$repo_dir/tests/consumer/facade-expected.txt" "$evidence_dir/facade.expected"
  cp "$repo_dir/tests/readme/javascript-expected.txt" "$evidence_dir/readme-javascript.expected"
fi
if [ "$mode" = browser ]; then
  mkdir -p "$test_dir/page"
  cp "$repo_dir/tests/consumer/browser/index.html" "$repo_dir/tests/consumer/browser/page.mjs" "$test_dir/page/"
fi
[ ! -e "$dependency/.tools" ] || { echo "Fresh checkout inherited ignored tools." >&2; exit 1; }
export BEND_LIB="$test_dir/package-cache"
export BEND_NO_TELEMETRY=1
{
  echo "Dependency commit: $revision"
  echo "Consumer platform: $(uname -s) $(uname -m)"
  uname -a
  if [ "$(uname -s)" = Darwin ]; then sw_vers; else cat /etc/os-release; fi
  if [ "$mode" = node ] || [ "$mode" = browser ]; then
    node_major=$(node -p 'process.versions.node.split(".")[0]')
    case "$node_major" in 22|24) ;; *) echo "Node 22 or 24 is required." >&2; exit 1 ;; esac
    node --version
    if [ "$mode" = browser ]; then
      (cd "$repo_dir" && node -p '"Playwright " + require("@playwright/test/package.json").version')
    fi
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
if [ "$mode" = browser ]; then
  # The page installs the facade from the checkout as a package and is
  # bundled by the checkout's own bundler. A second bundle of the same page
  # must be byte-identical to the one the browsers run.
  # shellcheck disable=SC2329 # run_logged invokes these functions.
  page_install() { (cd page && npm install --offline --ignore-scripts --no-audit --no-fund "$dependency/packages/trace-context"); }
  # shellcheck disable=SC2329
  page_hashes() { (cd page/dist && for file in *; do cksum "$file"; done); }
  # shellcheck disable=SC2329
  page_tests() {
    (cd "$repo_dir" && BEND_BROWSER_CONSUMER="$test_dir/page/dist" BEND_BROWSER_EVIDENCE="$evidence_dir" \
      npx --no-install playwright test --config tests/consumer/playwright.config.mjs)
  }
  printf '{"name": "bend-browser-consumer", "private": true, "type": "module"}\n' > page/package.json
  run_logged facade-install page_install
  run_logged bundle "$dependency/bend" page/index.html -o page/dist
  run_logged rebundle "$dependency/bend" page/index.html -o page/rebuilt
  run_logged bundle-reproducible diff -r page/dist page/rebuilt
  run_logged bundle-hashes page_hashes
  echo "PASS: independent pinned page bundle is reproducible"
  run_logged browser-tests page_tests
  node "$repo_dir/tests/browser/check-results.mjs" "$evidence_dir/browser-results.json" 3
  echo "PASS: independent pinned page (Chromium, Firefox and WebKit)"
  exit 0
fi
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
if [ "$mode" = node ]; then
  # The application installs the facade from the checkout as a package, as
  # the root README shows, and runs on the checkout's own module loader.
  run_logged loader "$dependency/scripts/setup-bend-source.sh"
  printf '{"name": "bend-consumer", "private": true, "type": "module"}\n' > package.json
  run_logged facade-install npm install --offline --ignore-scripts --no-audit --no-fund \
    "$dependency/packages/trace-context"
  run_logged loader-commit git -C "$dependency/.tools/bend-source-2.0.27" rev-parse HEAD
  for program in facade readme-javascript; do
    run_logged "$program" node --import "$dependency/.tools/bend-source-2.0.27/bend2/main.ts" "$program.mjs"
    run_logged "$program-diff" diff -u "$evidence_dir/$program.expected" "$evidence_dir/$program.stdout"
    echo "PASS: independent pinned $program (JavaScript facade on Node)"
  done
fi
