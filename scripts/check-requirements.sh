#!/bin/sh
# Keep the requirements matrix current: packages/trace-context/REQUIREMENTS.md
# must cite every law of LAWS.bend, and every name in a Laws column of its
# tables must be a law.
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
laws="$repo_dir/packages/trace-context/LAWS.bend"
matrix="$repo_dir/packages/trace-context/REQUIREMENTS.md"
work=$(mktemp -d "${TMPDIR:-/tmp}/bend-requirements.XXXXXXXX")
trap 'rm -rf "$work"' EXIT

sed -n 's/^law \([a-z][a-z0-9_]*\):.*/\1/p' "$laws" | sort -u > "$work/laws"
[ -s "$work/laws" ] || { echo "LAWS.bend declares no law." >&2; exit 1; }
# The names in the Laws column of each table, found by its header.
# shellcheck disable=SC2016 # $0 belongs to awk, not the shell.
awk -F'|' '
  /^\|/ {
    if (column == 0) {
      for (i = 2; i < NF; i++) if ($i ~ /^ *Laws *$/) column = i
      next
    }
    if ($0 ~ /^\| *---/) next
    cell = $column
    while (match(cell, /`[^`]*`/)) {
      name = substr(cell, RSTART + 1, RLENGTH - 2)
      if (name ~ /^[a-z][a-z0-9_]*$/) print name
      cell = substr(cell, RSTART + RLENGTH)
    }
    next
  }
  { column = 0 }
' "$matrix" | sort -u > "$work/cited"
missing=$(comm -23 "$work/laws" "$work/cited" | tr '\n' ' ')
unknown=$(comm -13 "$work/laws" "$work/cited" | tr '\n' ' ')
[ -z "$missing" ] || { echo "REQUIREMENTS.md cites no evidence for these laws: $missing" >&2; exit 1; }
[ -z "$unknown" ] || { echo "REQUIREMENTS.md cites names that are not laws: $unknown" >&2; exit 1; }
echo "PASS: the requirements matrix cites all $(wc -l < "$work/laws" | tr -d ' ') laws, and only laws"
