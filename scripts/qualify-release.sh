#!/bin/sh
# Qualify the release artifact of a commit: the BendHub package that
# `bend packages/trace-context/generation.bend --publish` makes from a fresh
# clone, and a clean consumer that imports it by its name.
#   candidate  rehearse the release on a local hub (tests/release/hub.mjs):
#              publish the package with the pinned compiler's --publish,
#              check it, name it with `bend link`, and run the consumer
#              against that hub; nothing is published
#   published  require https://hub.bend-lang.com to name exactly the
#              commit's package, and run the consumer against it
# Release X.Y.Z of VERSION is bend-trace-context@X.Y.Z.0 on BendHub, whose
# versions have four numbers; a candidate of X.Y.Z-dev is named the same.
# On BendHub, the name must be free or belong to the repository's owner.
# The report, build/release-MODE/artifact.txt, lists the package's files,
# their digests, its license, its description and its import lines, for
# review before publication.
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
mode=${1:-candidate}
revision=${2:-$(git -C "$repo_dir" rev-parse HEAD)}
usage="Usage: $0 [candidate|published] [full-commit-sha]"
[ "$#" -le 2 ] || { echo "$usage" >&2; exit 2; }
case "$mode" in candidate|published) ;; *) echo "$usage" >&2; exit 2 ;; esac
case "$revision" in *[!0-9a-f]*|'') echo "Use a full lowercase Git commit SHA." >&2; exit 2 ;; esac
[ "${#revision}" -eq 40 ] || { echo "Use a full 40-character Git commit SHA." >&2; exit 2; }
# The BendHub login that owns the package's name: the repository's owner.
owner=LucasGois1
real_hub=https://hub.bend-lang.com

evidence_dir="$repo_dir/build/release-$mode"
rm -rf "$evidence_dir"
mkdir -p "$evidence_dir"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/bend-release.XXXXXXXX")
hub_pid=
cleanup() {
  [ -z "$hub_pid" ] || kill "$hub_pid" 2>/dev/null || true
  echo "Release evidence: $evidence_dir"
  if [ "${KEEP_TEST_OUTPUT:-0}" = 1 ]; then
    echo "Release files retained at: $work_dir"
  else
    rm -rf "$work_dir"
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
fail() { echo "$1" >&2; exit 1; }

# The candidate: a fresh clone at the commit, with the compiler it pins.
source_dir="$work_dir/source"
run_logged clone git clone --quiet --no-local --no-checkout "$repo_dir" "$source_dir"
run_logged checkout git -C "$source_dir" checkout --quiet --detach "$revision"
[ "$(git -C "$source_dir" rev-parse HEAD)" = "$revision" ]
run_logged setup "$source_dir/scripts/setup-bend.sh"
bend="$source_dir/bend"
package="$source_dir/packages/trace-context"
version=$(cat "$source_dir/VERSION")
release=${version%-dev}
printf '%s\n' "$release" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' \
  || fail "VERSION must be X.Y.Z or X.Y.Z-dev, not $version."
if [ "$mode" = published ] && [ "$release" != "$version" ]; then
  fail "Commit $revision is version $version, not a release."
fi
named="bend-trace-context@$release.0"
export BEND_NO_TELEMETRY=1
{
  echo "Commit: $revision"
  echo "Version: $version"
  echo "Platform: $(uname -s) $(uname -m)"
  "$bend" version
  node --version
} > "$evidence_dir/environment.txt" 2>&1
cat "$evidence_dir/environment.txt"

# The local hub, on a free port, and a login for it: the compiler reads its
# key from ~/.bend/bender.json, so the rehearsal gives it a home of its own.
store="$work_dir/hub"
mkdir -p "$store" "$work_dir/home/.bend"
printf '{"key": "local-release-rehearsal", "login": "local"}\n' > "$work_dir/home/.bend/bender.json"
HUB_PORT=0 HUB_STORE=$store node "$source_dir/tests/release/hub.mjs" > "$evidence_dir/hub.log" 2>&1 &
hub_pid=$!
waited=0
until grep -q '^http://127\.0\.0\.1:[0-9]*$' "$evidence_dir/hub.log" 2>/dev/null; do
  waited=$((waited + 1))
  if [ "$waited" -gt 100 ] || ! kill -0 "$hub_pid" 2>/dev/null; then
    cat "$evidence_dir/hub.log" >&2
    exit 1
  fi
  sleep 0.1
done
local_hub=$(sed -n 1p "$evidence_dir/hub.log")
# shellcheck disable=SC2317,SC2329 # run_logged invokes this function.
on_local_hub() { HOME="$work_dir/home" BEND_HUB=$local_hub BEND_LIB="$work_dir/publish-lib" "$@"; }

# The compiler publishes the package without a name, as a release does
# first: the files it would send to BendHub, and the hash BendHub would
# give them.
run_logged publish on_local_hub "$bend" "$package/generation.bend" --publish
hash=$(sed -n 1p "$evidence_dir/publish.stdout")
printf '%s\n' "$hash" | grep -Eq '^0x[0-9a-f]{32}$' || fail "The publish printed no package hash."
grep -Fqx 'License: MIT (LICENSE)' "$evidence_dir/publish.stderr" || fail "The package is not published under the MIT license."
published="$store/$hash"

# The package holds the public modules, their internal modules and effects,
# and the license: no tool, test, document or other file of the repository.
cut -d' ' -f2- "$published/manifest" > "$evidence_dir/files.txt"
printf '%s\n' LICENSE entropy.bend entropy/native.c entropy/webcrypto.js generation.bend native_http.bend \
  src/digits.bend src/hex.bend trace_context.bend > "$evidence_dir/files.expected"
run_logged files diff -u "$evidence_dir/files.expected" "$evidence_dir/files.txt"
while read -r path; do
  if [ "$path" = LICENSE ]; then
    { printf 'SPDX-License-Identifier: MIT\n\n'; cat "$source_dir/LICENSE"; } | cmp -s - "$published/LICENSE" \
      || fail "The package's LICENSE is not the repository's MIT license with its identifier."
  else
    cmp -s "$package/$path" "$published/$path" || fail "$path differs from the commit's."
  fi
done < "$evidence_dir/files.txt"
# BendHub describes a package by the first line of its first .bend file,
# in the order of its manifest.
described=$(grep '\.bend$' "$evidence_dir/files.txt" | sed -n 1p)
description=$(sed -n '1s/^# //p' "$published/$described")
case "$description" in
  *'Source: https://github.com/LucasGois1/bend-trace-context') ;;
  *) fail "The first line of $described is not the package's description with its source." ;;
esac
echo "PASS: the package holds exactly the commit's modules, effects and MIT license, and its description"

# The JavaScript package declares the same version and the MIT license.
# shellcheck disable=SC2016 # The script is JavaScript.
node -e '
  const { version, license } = require(process.argv[1]);
  if (version !== process.argv[2] || license !== "MIT") {
    console.error(`package.json declares ${version} under ${license}, not ${process.argv[2]} under MIT`);
    process.exit(1);
  }
' "$package/package.json" "$version"
# A release has a dated changelog section that names the package that it
# publishes, and the README and the JavaScript guide install it.
if [ "$release" = "$version" ]; then
  grep -Eqx "## $release — [0-9]{4}-[0-9]{2}-[0-9]{2}" "$source_dir/CHANGELOG.md" \
    || fail "The changelog has no dated section for $release."
  awk -v heading="## $release " 'index($0, heading) == 1 { found = 1; next } found && /^## / { exit } found' \
    "$source_dir/CHANGELOG.md" > "$evidence_dir/changelog.txt"
  grep -Fq "\`$hash\`" "$evidence_dir/changelog.txt" \
    || fail "The changelog's $release section does not name the package $hash."
  for document in README.md packages/trace-context/JAVASCRIPT.md; do
    grep -Fq -- "git clone --branch v$release " "$source_dir/$document" || fail "$document does not install the tag v$release."
  done
  grep -Fq "import $named/trace_context.bend as TC" "$source_dir/README.md" || fail "README.md does not import $named."
  echo "PASS: the version, license, changelog and install instructions of $release agree"
fi

# The name on BendHub: free, or the owner's. A release registers it.
# shellcheck disable=SC2016 # The script is JavaScript.
run_logged hub-name node -e '
  const [hub, name, version, owner, mode] = process.argv.slice(1);
  (async () => {
    const answer = await fetch(`${hub}/name/${name}`);
    const entry = answer.status === 404 ? null : await answer.json();
    if (entry === null) {
      if (mode === "published") throw new Error(`${hub} has no name ${name}`);
      console.log(`Name: ${name} is free on BendHub`);
      return;
    }
    if (!answer.ok) throw new Error(`${hub}/name/${name} answered ${answer.status}`);
    if (String(entry.owner_login).toLowerCase() !== owner.toLowerCase()) {
      throw new Error(`${name} on BendHub belongs to ${entry.owner_login}, not ${owner}`);
    }
    const linked = (entry.versions ?? []).find((listed) => listed.version === version);
    console.log(`Name: ${name} belongs to ${entry.owner_login} on BendHub`);
    console.log(`Linked: ${linked === undefined ? "none" : linked.hash}`);
  })().catch((error) => { console.error(String(error)); process.exit(1); });
' "$real_hub" bend-trace-context "$release.0" "$owner" "$mode"

{
  echo "Publication target: $named on $real_hub"
  echo "Package: $hash"
  echo "Commit: $revision"
  echo "License: MIT"
  echo "Description: $description"
  sed -n 1p "$evidence_dir/hub-name.stdout"
  echo "Files (SHA-256, bytes, path):"
  bytes=0
  while read -r digest path; do
    size=$(wc -c < "$published/$path" | tr -d ' ')
    bytes=$((bytes + size))
    printf '  %s %7s %s\n' "$digest" "$size" "$path"
  done < "$published/manifest"
  echo "Bytes: $bytes"
  echo "Import lines:"
  echo "  import $named/trace_context.bend as TC"
  echo "  import $named/generation.bend as Generate"
  echo "  import $named/native_http.bend as NativeHttp"
} > "$evidence_dir/artifact.txt"
cat "$evidence_dir/artifact.txt"

if [ "$mode" = published ]; then
  # BendHub must name exactly the package that this commit publishes.
  grep -Fqx "Linked: $hash" "$evidence_dir/hub-name.stdout" || fail "BendHub does not name $named $hash."
  echo "PASS: BendHub names $named $hash, which $owner owns"
  consumer_hub=$real_hub
else
  # Name the package as a release does, once its hash is the reviewed one.
  run_logged link on_local_hub "$bend" link "$named" "$hash"
  consumer_hub=$local_hub
fi

# A clean consumer: the README's quick start and the guide's programs, with
# the package's name in place of the checkout's path, a program of the native
# HTTP adapter, and the guide's native HTTP service, which it compiles. It
# holds no source of the package, and reads the package from the hub.
consumer_dir="$work_dir/consumer"
mkdir -p "$consumer_dir/build"
by_name() {
  sed -e "s|^import \./deps/bend-trace-context/packages/trace-context/|import $named/|" "$1" > "$2"
  if grep -q 'deps/bend-trace-context' "$2"; then
    fail "$2 imports the package other than by its name."
  fi
}
program() {
  "$source_dir/scripts/doc-block.sh" "$1" bend "$source_dir/$2" > "$work_dir/$1.bend"
  by_name "$work_dir/$1.bend" "$consumer_dir/$1.bend"
  "$source_dir/scripts/doc-block.sh" "$1-output" text "$source_dir/$2" > "$evidence_dir/$1.expected"
}
guide="$source_dir/packages/trace-context/GUIDE.md"
recipes=$("$source_dir/scripts/doc-block.sh" --programs "$guide")
program readme-bend README.md
for recipe in $recipes; do
  program "$recipe" packages/trace-context/GUIDE.md
done
"$source_dir/scripts/doc-block.sh" guide-gateway bend "$guide" > "$work_dir/guide-gateway.bend"
by_name "$work_dir/guide-gateway.bend" "$consumer_dir/guide-gateway.bend"
sed -e "s|^import PACKAGE/|import $named/|" "$source_dir/tests/release/adapter.bend" > "$consumer_dir/adapter.bend"
cp "$source_dir/tests/release/adapter.expected" "$evidence_dir/adapter.expected"
cd "$consumer_dir"
export BEND_HUB="$consumer_hub"
export BEND_LIB="$consumer_dir/lib"
for program in readme-bend adapter $recipes; do
  run_logged "$program" "$bend" "$program.bend"
  run_logged "$program-diff" "$source_dir/scripts/same-output.sh" "$evidence_dir/$program.expected" \
    "$evidence_dir/$program.stdout"
done
# The quick start also as a native binary and as a program for Node, and the
# native HTTP service, on bend-kit from BendHub, compiled to C.
run_logged readme-bend-build "$bend" readme-bend.bend -o build/readme-bend
run_logged readme-bend-native ./build/readme-bend
run_logged readme-bend-native-diff "$source_dir/scripts/same-output.sh" "$evidence_dir/readme-bend.expected" \
  "$evidence_dir/readme-bend-native.stdout"
run_logged readme-bend-compile "$bend" readme-bend.bend -o build/readme-bend.js
run_logged readme-bend-node node build/readme-bend.js
run_logged readme-bend-node-diff "$source_dir/scripts/same-output.sh" "$evidence_dir/readme-bend.expected" \
  "$evidence_dir/readme-bend-node.stdout"
run_logged guide-gateway-compile "$bend" guide-gateway.bend -o build/guide-gateway.c
[ -s build/guide-gateway.c ] || fail "The guide's native HTTP service did not compile."
# The consumer resolved the name to the package and read it from the hub.
[ "$(cat "$BEND_LIB/names/$named")" = "$hash" ] || fail "The consumer resolved $named elsewhere."
[ -f "$BEND_LIB/$hash/generation.bend" ] || fail "The consumer did not read the package from the hub."
echo "PASS: a clean consumer imports $named from $consumer_hub: the README's quick start (direct, native and Node), the guide's programs, the native HTTP adapter and the guide's native HTTP service"
