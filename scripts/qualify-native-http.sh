#!/bin/sh
# Qualify the native HTTP transport, bend-kit's HTTP package: its own laws
# and checks at the commit whose http.bend BendHub serves, and the transport
# consumer's real HTTP observer tests.
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
[ "$#" -eq 0 ] || { echo "Usage: $0" >&2; exit 2; }
cd "$repo_dir"
fixture=tests/native/fixtures/transport-service.bend
# The native HTTP programs, which must import the same bend-kit packages.
programs="$fixture tests/harness/actions.bend tests/propagation/service.bend
  packages/trace-context/examples/gateway.bend"
# The bend-kit commit that published bend-kit-http 0.23.0.1.
bend_kit_url=https://github.com/paymog/bend-kit.git
bend_kit_commit=31912fbd99e9090df43bf2ef70da4340241e9e51
result_dir="$repo_dir/build/native-http"
rm -rf "$result_dir"
mkdir -p "$result_dir"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/bend-native-http.XXXXXXXX")
trap 'rm -rf "$work_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
# The programs import bend-kit's packages from BendHub by content hash, and
# those packages import theirs by name and version; a fresh cache, outside
# the evidence, makes each run fetch and resolve them again.
BEND_LIB="$work_dir/package-cache"
export BEND_LIB
export BEND_NO_TELEMETRY=1

if command -v sha256sum >/dev/null; then
  sha256() { sha256sum "$1" | cut -d ' ' -f 1; }
else
  sha256() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
fi

# The package that each program imports as `name`, one line per distinct one.
# shellcheck disable=SC2086 # $programs is a list of paths without spaces.
imported() { sed -n "s|^import \(0x[0-9a-f]*\)/$1\.bend as .*|\1|p" $programs | sort -u; }
for name in http json; do
  [ "$(imported "$name" | wc -l | tr -d ' ')" -eq 1 ] || {
    echo "The native HTTP programs import different bend-kit $name packages:" >&2
    imported "$name" >&2
    exit 1
  }
done
http_package=$(imported http)

{
  printf 'Package commit: %s\n' "$(git rev-parse HEAD)"
  printf 'Platform: %s %s\n' "$(uname -s)" "$(uname -m)"
  printf 'bend-kit-http package: %s\n' "$http_package"
  printf 'bend-kit-json package: %s\n' "$(imported json)"
  printf 'bend-kit commit: %s\n' "$bend_kit_commit"
  ./bend version
  clang --version
} > "$result_dir/environment.txt" 2>&1
cat "$result_dir/environment.txt"

./bend "$fixture" -o "$result_dir/transport-service" > "$result_dir/transport-compile.txt" 2>&1 || {
  cat "$result_dir/transport-compile.txt" >&2
  exit 1
}
# Every package that BendHub resolved by name for the build, with its hash.
for name in "$BEND_LIB"/names/*; do
  printf '%s %s\n' "$(basename "$name")" "$(cat "$name")"
done > "$result_dir/hub-names.txt"
cat "$result_dir/hub-names.txt"

# bend-kit's laws and checks, at the commit whose http.bend is, byte for
# byte, the http.bend of the package the programs import.
git init --quiet "$work_dir/bend-kit"
git -C "$work_dir/bend-kit" fetch --quiet --depth 1 "$bend_kit_url" "$bend_kit_commit"
git -C "$work_dir/bend-kit" checkout --quiet FETCH_HEAD
[ "$(git -C "$work_dir/bend-kit" rev-parse HEAD)" = "$bend_kit_commit" ] || {
  echo "Unexpected bend-kit source" >&2
  exit 1
}
[ "$(sha256 "$work_dir/bend-kit/http/http.bend")" = "$(sha256 "$BEND_LIB/$http_package/http.bend")" ] || {
  echo "bend-kit's http.bend at $bend_kit_commit is not the one BendHub serves as $http_package" >&2
  exit 1
}
# As bend-kit's own check does, accept SOME PROOFS FAIL only when every
# complaint is a definition that relies on @unsafe or foreign code, and no
# law is one.
status=0
(cd "$work_dir/bend-kit/http" && "$repo_dir/bend" PROOF.bend --check-only) \
  > "$result_dir/dependency-proofs.txt" 2>&1 || status=$?
if [ "$status" -ne 0 ]; then
  awk '
    NR == 1 { ok = $0 == "SOME PROOFS FAIL"; next }
    NR == 2 { ok = ok && /^Error: [0-9]+ defs? rel(y|ies) on unsafe or foreign code:$/; next }
    !/^- / || $2 ~ /^LAWS[.]/ { ok = 0 }
    END { exit !ok }
  ' "$result_dir/dependency-proofs.txt" || {
    cat "$result_dir/dependency-proofs.txt" >&2
    echo "bend-kit's HTTP laws do not all hold." >&2
    exit 1
  }
fi
head -n 2 "$result_dir/dependency-proofs.txt"
(cd "$work_dir/bend-kit/http" && "$repo_dir/bend" check.bend) > "$result_dir/dependency-check.txt" 2>&1 || {
  cat "$result_dir/dependency-check.txt" >&2
  exit 1
}
printf 'PASS: bend-kit HTTP laws (no law relies on unsafe or foreign code) and its %s checks\n' \
  "$(grep -c '^ok ' "$result_dir/dependency-check.txt")"

BEND_NATIVE_HTTP_SERVICE="$result_dir/transport-service" \
  node --test --test-reporter=tap tests/native/transport.mjs \
  > "$result_dir/transport-tests.txt" 2>&1 || {
    cat "$result_dir/transport-tests.txt" >&2
    exit 1
  }
cat "$result_dir/transport-tests.txt"
grep -F '# skipped 0' "$result_dir/transport-tests.txt" >/dev/null

printf 'PASS: native HTTP qualification on bend-kit; evidence: %s\n' "$result_dir"
