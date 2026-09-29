#!/bin/sh
# Compare what a documented program printed with the output that its
# document shows, and print the difference. A document shows the span IDs of
# one run in `span_id=` log fields, and every run prints new ones, so both
# sides mask them. The span IDs that the documents give as received parents
# stay, so that a program that logs the parent's ID instead of a new one
# fails.
set -eu

[ "$#" -eq 2 ] || { echo "Usage: $0 EXPECTED PRINTED" >&2; exit 2; }
masked() {
  sed -e 's/span_id=00f067aa0ba902b7/span_id=received-00f067aa0ba902b7/g' \
    -e 's/span_id=b7ad6b7169203331/span_id=received-b7ad6b7169203331/g' \
    -e 's/span_id=[0-9a-f]\{16\}/span_id=<new span ID>/g' -e 's/span_id=received-/span_id=/g' "$1"
}
work=$(mktemp -d "${TMPDIR:-/tmp}/bend-output.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
masked "$1" > "$work/expected"
masked "$2" > "$work/printed"
diff -u "$work/expected" "$work/printed"
