#!/bin/sh
# Run the pinned compiler installed by scripts/setup-bend.sh.
set -eu
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
compiler="$repo_dir/.tools/bend-2.0.27/bin/bend"
if [ ! -x "$compiler" ]; then
  echo "Bend 2.0.27 is not installed. Run: $repo_dir/scripts/setup-bend.sh" >&2
  exit 1
fi
export BEND_NO_TELEMETRY=1
exec "$compiler" "$@"
