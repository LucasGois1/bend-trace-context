#!/bin/sh
# Run the repository-local Bend compiler.
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export BEND_NO_TELEMETRY=1
exec "$repo_dir/.tools/runtime/bin/bend" "$@"
