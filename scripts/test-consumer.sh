#!/bin/sh
# Exercise a fresh pinned dependency checkout from an independent application.
# In node mode, the application also installs the JavaScript facade from the
# checkout and runs it on Node alone, with no Bend at run time. In browser
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
# The code of the README and the guides comes from the exact dependency
# revision being exercised: each block is marked in its document, and a block
# marked NAME-output holds what NAME prints. A missing, duplicate or
# malformed marked fence must fail, not skip the check. A document shows the
# span IDs of one run in `span_id=` log fields, and every run prints new
# ones, so the comparison masks them.
extract_example() {
  run_logged "$1-extract" "$dependency/scripts/doc-block.sh" "$1" "$2" "$dependency/${3:-README.md}"
}
# A program in a FENCE block of DOCUMENT and the output that the document
# shows for it, into the test directory as NAME.EXTENSION and into the
# evidence as NAME.expected.
extract_program() {
  name=$1
  fence=$2
  document=$3
  extension=$4
  extract_example "$name" "$fence" "$document"
  cp "$evidence_dir/$name-extract.stdout" "$test_dir/$name.$extension"
  extract_example "$name-output" text "$document"
  cp "$evidence_dir/$name-output-extract.stdout" "$evidence_dir/$name.expected"
}
# Compare what a program printed with what its document shows.
compare_output() { run_logged "$1" "$dependency/scripts/same-output.sh" "$2" "$3"; }
guide=packages/trace-context/GUIDE.md
javascript_guide=packages/trace-context/JAVASCRIPT.md
# The Bend programs of the README and the guide, the JavaScript programs of
# the JavaScript guide that print, as the documents mark them, and its
# recipes that serve requests.
bend_programs="readme-bend $("$dependency/scripts/doc-block.sh" --programs "$dependency/$guide")"
javascript_programs=$("$dependency/scripts/doc-block.sh" --programs "$dependency/$javascript_guide")
recipes="javascript-http javascript-express javascript-fastify javascript-context"
if [ "$mode" != browser ]; then
  extract_program readme-bend bend README.md bend
  for program in $bend_programs; do
    [ "$program" = readme-bend ] || extract_program "$program" bend "$guide" bend
  done
  # Independent fixtures and expectations are test inputs, never package
  # internals.
  cp "$repo_dir/tests/consumer/main.bend" "$test_dir/consumer.bend"
  cp "$repo_dir/tests/consumer/expected.txt" "$evidence_dir/consumer.expected"
fi
if [ "$mode" = native ]; then
  extract_example guide-gateway bend "$guide"
fi
if [ "$mode" = node ]; then
  extract_program readme-javascript js README.md mjs
  for program in $javascript_programs; do
    extract_program "$program" js "$javascript_guide" mjs
  done
  mkdir -p "$test_dir/recipes"
  for recipe in $recipes; do
    extract_example "$recipe" js "$javascript_guide"
    cp "$evidence_dir/$recipe-extract.stdout" "$test_dir/recipes/$recipe.mjs"
  done
  extract_example javascript-typescript ts "$javascript_guide"
  cp "$evidence_dir/javascript-typescript-extract.stdout" "$test_dir/typescript.ts"
  cp "$repo_dir/tests/consumer/types.ts" "$repo_dir/tests/consumer/fetch-types.ts" "$test_dir/"
  cp "$repo_dir/tests/consumer/facade.mjs" "$test_dir/facade.mjs"
  cp "$repo_dir/tests/consumer/facade-expected.txt" "$evidence_dir/facade.expected"
fi
if [ "$mode" = browser ]; then
  mkdir -p "$test_dir/page" "$test_dir/quickstart"
  cp "$repo_dir/tests/consumer/browser/index.html" "$repo_dir/tests/consumer/browser/page.mjs" "$test_dir/page/"
  # The README's browser quick start, served by the JavaScript guide's
  # server for it.
  extract_example readme-page-html html README.md
  cp "$evidence_dir/readme-page-html-extract.stdout" "$test_dir/quickstart/page.html"
  extract_program readme-page js README.md mjs
  mv "$test_dir/readme-page.mjs" "$test_dir/quickstart/page.mjs"
  extract_example javascript-server js "$javascript_guide"
  cp "$evidence_dir/javascript-server-extract.stdout" "$test_dir/quickstart/server.mjs"
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
  # shellcheck disable=SC2317,SC2329 # run_logged invokes these functions.
  page_install() { (cd "$1" && npm install --offline --ignore-scripts --no-audit --no-fund "$dependency/packages/trace-context"); }
  # shellcheck disable=SC2317,SC2329
  page_hashes() { (cd page/dist && for file in *; do cksum "$file"; done); }
  # shellcheck disable=SC2317,SC2329
  page_tests() {
    (cd "$repo_dir" && BEND_BROWSER_CONSUMER="$test_dir/page/dist" BEND_BROWSER_EVIDENCE="$evidence_dir" \
      BEND_BROWSER_QUICKSTART="$test_dir/quickstart" BEND_QUICKSTART_EXPECTED="$evidence_dir/readme-page.expected" \
      npx --no-install playwright test --config tests/consumer/playwright.config.mjs)
  }
  # shellcheck disable=SC2317,SC2329
  bundle_pages() { "$dependency/bend" page/index.html -o "$1"; }
  # shellcheck disable=SC2317,SC2329
  bundle_quickstart() { (cd quickstart && "$dependency/bend" page.html -o dist); }
  printf '{"name": "bend-browser-consumer", "private": true, "type": "module"}\n' > page/package.json
  printf '{"name": "bend-browser-quickstart", "private": true, "type": "module"}\n' > quickstart/package.json
  run_logged facade-install page_install page
  run_logged quickstart-install page_install quickstart
  run_logged quickstart-bundle bundle_quickstart
  run_logged bundle bundle_pages page/dist
  run_logged rebundle bundle_pages page/rebuilt
  run_logged bundle-reproducible diff -r page/dist page/rebuilt
  run_logged bundle-hashes page_hashes
  echo "PASS: independent pinned page bundle is reproducible"
  run_logged browser-tests page_tests
  node "$repo_dir/tests/browser/check-results.mjs" "$evidence_dir/browser-results.json" 6
  echo "PASS: independent pinned page and the README's quick start (Chromium, Firefox and WebKit)"
  exit 0
fi
# Every Bend program runs directly. For Node every one is compiled to
# JavaScript too; natively the consumer and the README's quick start are
# built, and the guide's recipes, which the native build of the package's
# examples covers, run directly only.
for program in consumer $bend_programs; do
  run_logged "$program-direct" "$dependency/bend" "$program.bend"
  compare_output "$program-direct-diff" "$evidence_dir/$program.expected" "$evidence_dir/$program-direct.stdout"
  if [ "$mode" = node ]; then
    run_logged "$program-compile" "$dependency/bend" "$program.bend" -o "build/$program.js"
    run_logged "$program-compiled" node "build/$program.js"
  elif [ "$program" = consumer ] || [ "$program" = readme-bend ]; then
    run_logged "$program-compile" "$dependency/bend" "$program.bend" -o "build/$program"
    run_logged "$program-compiled" "./build/$program"
  else
    echo "PASS: independent pinned $program (direct)"
    continue
  fi
  compare_output "$program-compiled-diff" "$evidence_dir/$program.expected" "$evidence_dir/$program-compiled.stdout"
  echo "PASS: independent pinned $program ($mode)"
done
if [ "$mode" = native ]; then
  # The guide's native HTTP service is the gateway example with an
  # application's imports: apart from comments, the programs are the same.
  # shellcheck disable=SC2317,SC2329 # run_logged invokes this function.
  code_of() {
    sed -e 's|^import \./deps/bend-trace-context/packages/trace-context/|import ../|' "$1" | grep -v -e '^ *#' -e '^ *$'
  }
  code_of "$evidence_dir/guide-gateway-extract.stdout" > "$evidence_dir/guide-gateway.code"
  code_of "$dependency/packages/trace-context/examples/gateway.bend" > "$evidence_dir/gateway-example.code"
  run_logged guide-gateway-diff diff -u "$evidence_dir/gateway-example.code" "$evidence_dir/guide-gateway.code"
  echo "PASS: the guide's native HTTP service is the gateway example"
fi
if [ "$mode" = node ]; then
  # The application installs the facade from the checkout as a package, as
  # the root README shows. The recipes' frameworks and TypeScript are the
  # versions that the repository's package-lock.json locks: `npm ci`
  # installed them in the repository, and the application links them from
  # there, so that no registry is needed and no dependency floats.
  printf '{"name": "bend-consumer", "private": true, "type": "module"}\n' > package.json
  run_logged facade-install npm install --offline --ignore-scripts --no-audit --no-fund \
    "$dependency/packages/trace-context"
  for tool in express fastify @opentelemetry/api typescript typescript-5; do
    [ -d "$repo_dir/node_modules/$tool" ] || {
      echo "Run npm ci --ignore-scripts in the repository first: $tool is missing." >&2
      exit 1
    }
    mkdir -p "node_modules/$(dirname "$tool")"
    ln -s "$repo_dir/node_modules/$tool" "node_modules/$tool"
  done
  for program in facade readme-javascript $javascript_programs; do
    run_logged "$program" node "$program.mjs"
    compare_output "$program-diff" "$evidence_dir/$program.expected" "$evidence_dir/$program.stdout"
    echo "PASS: independent pinned $program (JavaScript facade on Node)"
  done
  recipe_files=
  for recipe in $recipes; do recipe_files="$recipe_files $test_dir/recipes/$recipe.mjs"; done
  run_logged recipes env BEND_RECIPES="$recipe_files" node --test --test-reporter=tap \
    "$repo_dir/tests/consumer/recipes.mjs"
  grep -F '# fail 0' "$evidence_dir/recipes.stdout" >/dev/null
  grep -F '# skipped 0' "$evidence_dir/recipes.stdout" >/dev/null
  echo "PASS: the JavaScript guide's recipes serve traced and untraced requests, and answer 502 without downstream"
  # The declarations of the first two entries need no DOM or Node types, and
  # those of the Fetch entry the DOM library's, with each TypeScript.
  cp "$repo_dir/tests/consumer/tsconfig.json" "$repo_dir/tests/consumer/tsconfig.dom.json" "$test_dir/"
  versions=
  for typescript in typescript-5 typescript; do
    for config in tsconfig.json tsconfig.dom.json; do
      run_logged "types-$typescript-${config%.json}" node "node_modules/$typescript/bin/tsc" -p "$config"
    done
    versions="$versions${versions:+ and }$(node -p "require('./node_modules/$typescript/package.json').version")"
  done
  echo "PASS: the facade's types, with TypeScript $versions"
fi
