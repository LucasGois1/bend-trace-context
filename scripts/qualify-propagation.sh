#!/bin/sh
# Qualify Trace Context propagation over HTTP on one host: natively, over the
# pinned HTTP transport bend-net, or in Node, over node:http through the
# JavaScript facade. From a pinned checkout of this repository, build or
# install the propagation service and the gateway example as an application
# would, run the repository's propagation checks against an independent
# observer, and run the W3C Trace Context harness at its pinned commit with
# SPEC_LEVEL=2 and STRICT_LEVEL=2.
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
usage="Usage: $0 [native|node] [full-commit-sha]"
mode=${1:-native}
revision=${2:-$(git -C "$repo_dir" rev-parse HEAD)}
[ "$#" -le 2 ] || { echo "$usage" >&2; exit 2; }
case "$mode" in native|node) ;; *) echo "$usage" >&2; exit 2 ;; esac
case "$revision" in *[!0-9a-f]*|'') echo "Use a full lowercase Git commit SHA." >&2; exit 2 ;; esac
[ "${#revision}" -eq 40 ] || { echo "Use a full 40-character Git commit SHA." >&2; exit 2; }
bend_net_pin=274591f1d1fcca2e4aa39ba65e505b32e2dbff21
harness_pin=acab820be9db7b3433668baa5cdd43f57f4c4be0
harness_url=https://github.com/w3c/trace-context
harness_tests=41
cd "$repo_dir"
if [ "$mode" = native ]; then
  [ -f vendor/bend-net/http.bend ] || {
    echo "Initialize the pinned HTTP dependency with: git submodule update --init --recursive" >&2
    exit 1
  }
else
  node_major=$(node -p 'process.versions.node.split(".")[0]')
  case "$node_major" in 22|24) ;; *) echo "Node 22 or 24 is required." >&2; exit 1 ;; esac
fi

result_dir="$repo_dir/build/propagation-$mode"
rm -rf "$result_dir"
mkdir -p "$result_dir"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/bend-propagation.XXXXXXXX")
service_pid=
cleanup() {
  if [ -n "$service_pid" ]; then kill "$service_pid" 2>/dev/null || true; fi
  rm -rf "$work_dir"
  echo "Propagation evidence: $result_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

run_logged() {
  log_name=$1
  shift
  command_status=0
  "$@" > "$result_dir/$log_name.txt" 2> "$result_dir/$log_name.stderr.txt" || command_status=$?
  cat "$result_dir/$log_name.txt"
  cat "$result_dir/$log_name.stderr.txt" >&2
  return "$command_status"
}

# The service and the example come from a pinned checkout of the exact
# revision, as an application takes them. Natively, its bend-net submodule
# comes from the local pinned checkout; in Node, the facade needs no
# submodule, and the checkout installs its own Bend module loader. Only the
# loader, the harness and aiohttp are downloaded.
dependency="$work_dir/deps/bend-trace-context"
mkdir -p "$work_dir/deps" "$work_dir/package-cache"
git clone --quiet --no-local --no-checkout "$repo_dir" "$dependency"
git -C "$dependency" checkout --quiet --detach "$revision"
[ "$(git -C "$dependency" rev-parse HEAD)" = "$revision" ]
if [ "$mode" = native ]; then
  git -C "$dependency" config submodule.vendor/bend-net.url "$repo_dir/vendor/bend-net"
  git -C "$dependency" -c protocol.file.allow=always submodule --quiet update --init vendor/bend-net
  [ "$(git -C "$dependency/vendor/bend-net" rev-parse HEAD)" = "$bend_net_pin" ] || {
    echo "Unexpected bend-net source in the pinned checkout" >&2
    exit 1
  }
  cp tests/propagation/service.bend "$work_dir/service.bend"
else
  run_logged loader "$dependency/scripts/setup-bend-source.sh"
fi
export BEND_LIB="$work_dir/package-cache"
export BEND_NO_TELEMETRY=1

# The harness runs on the aiohttp version and hashes in requirements.txt.
harness_dir="$work_dir/harness"
git init --quiet "$harness_dir"
git -C "$harness_dir" fetch --quiet --depth 1 "$harness_url" "$harness_pin"
git -C "$harness_dir" checkout --quiet FETCH_HEAD
[ "$(git -C "$harness_dir" rev-parse HEAD)" = "$harness_pin" ] || {
  echo "Unexpected W3C harness source" >&2
  exit 1
}
python3 -m venv "$work_dir/venv"
"$work_dir/venv/bin/python" -m pip install --quiet --disable-pip-version-check --require-hashes \
  --only-binary :all: -r tests/propagation/requirements.txt

{
  printf 'Package commit: %s\n' "$revision"
  printf 'Host: %s\n' "$mode"
  printf 'W3C harness commit: %s\n' "$harness_pin"
  printf 'Platform: %s %s\n' "$(uname -s)" "$(uname -m)"
  if [ "$(uname -s)" = Darwin ]; then sw_vers; else cat /etc/os-release; fi
  if [ "$mode" = native ]; then
    ./bend version
    printf 'bend-net commit: %s\n' "$bend_net_pin"
    "${CC:-clang}" --version
  else
    printf 'Bend module loader commit: %s\n' "$(git -C "$dependency/.tools/bend-source-2.0.27" rev-parse HEAD)"
    printf 'npm %s\n' "$(npm --version)"
  fi
  node --version
  "$work_dir/venv/bin/python" --version
  "$work_dir/venv/bin/python" -m pip freeze --disable-pip-version-check
} > "$result_dir/environment.txt" 2>&1
cat "$result_dir/environment.txt"

if [ "$mode" = native ]; then
  (cd "$work_dir" && "$repo_dir/bend" service.bend -o "$result_dir/service") > "$result_dir/service-compile.txt" 2>&1 || {
    cat "$result_dir/service-compile.txt" >&2
    exit 1
  }
  "$repo_dir/bend" "$dependency/packages/trace-context/examples/gateway.bend" -o "$result_dir/gateway" \
    > "$result_dir/gateway-compile.txt" 2>&1 || {
      cat "$result_dir/gateway-compile.txt" >&2
      exit 1
    }
  # The failing source of service.bend.
  source_failure='SourceFailure 5 entropy unavailable'
else
  # The service installs the facade from the pinned checkout as a package,
  # and both programs run on the checkout's own loader.
  app_dir="$work_dir/app"
  mkdir -p "$app_dir"
  cp tests/propagation/service.mjs "$app_dir/service.mjs"
  printf '{"name": "propagation-service", "private": true, "type": "module"}\n' > "$app_dir/package.json"
  (cd "$app_dir" && npm install --offline --ignore-scripts --no-audit --no-fund \
    "$dependency/packages/trace-context") > "$result_dir/service-install.txt" 2>&1 || {
      cat "$result_dir/service-install.txt" >&2
      exit 1
    }
  loader="$dependency/.tools/bend-source-2.0.27/bend2/main.ts"
  printf '#!/bin/sh\nexec node --import "%s" "%s"\n' "$loader" "$app_dir/service.mjs" > "$result_dir/service"
  printf '#!/bin/sh\nexec node --import "%s" "%s"\n' "$loader" \
    "$dependency/packages/trace-context/examples/gateway.mjs" > "$result_dir/gateway"
  chmod +x "$result_dir/service" "$result_dir/gateway"
  # An unavailable WebCrypto, as the facade reports it.
  source_failure='SourceFailure 1 unavailable'
fi

# Node's test runner reports skips; a skipped check does not pass.
BEND_PROPAGATION_SERVICE="$result_dir/service" BEND_PROPAGATION_SOURCE_FAILURE="$source_failure" \
  run_logged propagation-tests node --test --test-reporter=tap tests/propagation/propagation.mjs
grep -F '# fail 0' "$result_dir/propagation-tests.txt" >/dev/null
grep -F '# skipped 0' "$result_dir/propagation-tests.txt" >/dev/null
BEND_GATEWAY="$result_dir/gateway" run_logged gateway-tests node --test --test-reporter=tap tests/propagation/gateway.mjs
grep -F '# fail 0' "$result_dir/gateway-tests.txt" >/dev/null
grep -F '# skipped 0' "$result_dir/gateway-tests.txt" >/dev/null

"$result_dir/service" > "$result_dir/harness-service.txt" 2>&1 &
service_pid=$!
tries=0
until grep -F 'http://127.0.0.1:18775' "$result_dir/harness-service.txt" >/dev/null; do
  tries=$((tries + 1))
  [ "$tries" -le 20 ] || { cat "$result_dir/harness-service.txt" >&2; echo "The service did not start." >&2; exit 1; }
  sleep 1
done
harness_status=0
(cd "$harness_dir/test" && SPEC_LEVEL=2 STRICT_LEVEL=2 "$work_dir/venv/bin/python" test.py \
  http://127.0.0.1:18775/test TraceContextTest AdvancedTest TraceContext2Test) \
  > "$result_dir/w3c-harness.txt" 2>&1 || harness_status=$?
kill "$service_pid"
service_pid=
cat "$result_dir/w3c-harness.txt"
[ "$harness_status" -eq 0 ] || { echo "The W3C harness failed (exit $harness_status)." >&2; exit 1; }
# Every test must run: a skipped test, such as the Level 2 class without
# SPEC_LEVEL=2, reports "OK (skipped=...)" and fails here.
grep -E "^Ran $harness_tests tests in " "$result_dir/w3c-harness.txt" >/dev/null || {
  echo "Expected $harness_tests harness tests." >&2
  exit 1
}
grep -Fx 'OK' "$result_dir/w3c-harness.txt" >/dev/null || { echo "The W3C harness did not report OK." >&2; exit 1; }

printf 'PASS: %s Trace Context propagation, gateway example and W3C harness (%s tests); evidence: %s\n' \
  "$mode" "$harness_tests" "$result_dir"
