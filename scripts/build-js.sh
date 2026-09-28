#!/bin/sh
# Build the JavaScript facade's ES module of trace_context.bend with the
# pinned compiler: packages/trace-context/javascript/trace_context.mjs, which
# the facade imports, so that an application needs no Bend at run time.
# With --check, build it elsewhere and require the committed file to match it
# byte for byte.
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
usage="Usage: $0 [--check]"
[ "$#" -le 1 ] || { echo "$usage" >&2; exit 2; }
case "${1:-}" in ''|--check) ;; *) echo "$usage" >&2; exit 2 ;; esac
cd "$repo_dir"
target=packages/trace-context/javascript/trace_context.mjs
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/bend-js-module.XXXXXXXX")
trap 'rm -rf "$work_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

version=$(./bend version)
./bend packages/trace-context/trace_context.bend -o "$work_dir/compiled.mjs"
{
  printf '// Generated from trace_context.bend by scripts/build-js.sh with %s.\n' "$version"
  printf '// Do not edit: change the Bend sources and run the script again.\n'
  cat "$work_dir/compiled.mjs"
} > "$work_dir/trace_context.mjs"

if [ "${1:-}" = --check ]; then
  if ! cmp -s "$work_dir/trace_context.mjs" "$target"; then
    echo "$target is not the build of the Bend sources with $version." >&2
    echo "Run ./scripts/build-js.sh and commit the result." >&2
    exit 1
  fi
  printf 'PASS: %s is the build of the Bend sources with %s\n' "$target" "$version"
else
  mv "$work_dir/trace_context.mjs" "$target"
  printf 'Built %s with %s\n' "$target" "$version"
fi
