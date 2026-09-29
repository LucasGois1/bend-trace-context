#!/bin/sh
# Print the code block that a document marks as NAME, between
# <!-- test:NAME:start --> and <!-- test:NAME:end -->, in a fence of FENCE,
# such as bend, js or text. A missing, duplicate, empty or malformed marked
# block fails, so that a test never skips a block silently. With --programs,
# print the names of the document's programs: the marked blocks whose output
# it shows in a block marked NAME-output.
set -eu

usage="Usage: $0 NAME FENCE DOCUMENT, or $0 --programs DOCUMENT"
if [ "${1:-}" = --programs ]; then
  [ "$#" -eq 2 ] || { echo "$usage" >&2; exit 2; }
  names=$(sed -n 's/^<!-- test:\([A-Za-z0-9-]*\):start -->$/\1/p' "$2")
  found=0
  for name in $names; do
    case "$name" in
      *-output) ;;
      *) if printf '%s\n' "$names" | grep -qx -- "$name-output"; then printf '%s\n' "$name"; found=1; fi ;;
    esac
  done
  [ "$found" = 1 ] || { echo "$2 shows the output of no marked program." >&2; exit 1; }
  exit 0
fi
[ "$#" -eq 3 ] || { echo "$usage" >&2; exit 2; }
marker=$1
fence=$2
document=$3
# shellcheck disable=SC2016 # $0 belongs to awk, not the shell.
awk -v marker="$marker" -v fence="$fence" -v document="$document" '
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
      print "Expected exactly one marked " marker " example in " document "." > "/dev/stderr"
      exit 1
    }
  }
' "$document"
