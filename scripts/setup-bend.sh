#!/bin/sh
# Install the immutable Bend release assets, never the moving upstream installer.
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
[ "$#" -le 1 ] || { echo "Usage: $0 [destination]" >&2; exit 2; }
destination=${1:-$repo_dir/.tools/bend-2.0.27}
version=2.0.27
release_commit=63bee70b55a71024d6bdcb49a745111bc54b114e
# https://github.com/bendlang/bend/releases/tag/v2.0.27
# Digests are pinned from the release body and GitHub release asset metadata.
case "$(uname -s)/$(uname -m)" in
  Darwin/arm64)
    platform=darwin-arm64
    digest=de1f0a8b8db18c336edfb9385234b34f7da60fa4c79a4261e3be4a9674a2ffd7
    ;;
  Linux/x86_64)
    platform=linux-x64
    digest=58adc86af6605ed0c48f7d84e4c23028f78893ce4a867a20a4f004b11582687b
    ;;
  *) echo "Supported compiler hosts: macOS ARM64 and Linux x86_64." >&2; exit 1 ;;
esac
for command_name in curl tar diff; do
  command -v "$command_name" >/dev/null || { echo "Required command: $command_name" >&2; exit 1; }
done
if command -v sha256sum >/dev/null; then
  hash_command=sha256sum
elif command -v shasum >/dev/null; then
  hash_command=shasum
else
  echo "Install sha256sum or shasum to verify the compiler archive." >&2
  exit 1
fi
mkdir -p "$(dirname -- "$destination")"
parent_dir=$(CDPATH='' cd -- "$(dirname -- "$destination")" && pwd)
destination="$parent_dir/$(basename -- "$destination")"
work_dir=$(mktemp -d "$parent_dir/.bend-setup.XXXXXXXX")
trap 'rm -rf "$work_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
asset="bend-$version-$platform.tar.gz"
url="https://github.com/bendlang/bend/releases/download/v$version/$asset"
echo "Bend release: v$version ($release_commit)"
echo "Asset: $url"
echo "Expected SHA256: $digest"
curl --fail --silent --show-error --location --retry 3 --proto '=https' --tlsv1.2 "$url" -o "$work_dir/$asset"
if [ "$hash_command" = sha256sum ]; then
  actual_digest=$(sha256sum "$work_dir/$asset" | cut -d ' ' -f 1)
else
  actual_digest=$(shasum -a 256 "$work_dir/$asset" | cut -d ' ' -f 1)
fi
[ "$actual_digest" = "$digest" ] || { echo "Compiler checksum mismatch; nothing was installed." >&2; exit 1; }
tar -xzf "$work_dir/$asset" -C "$work_dir"
export BEND_NO_TELEMETRY=1
[ -f "$work_dir/bend/bend2/base.bend" ]
[ -d "$work_dir/bend/bend2/effs" ]
[ "$("$work_dir/bend/bin/bend" version)" = "bend $version" ] || {
  echo "Compiler version mismatch; nothing was installed." >&2
  exit 1
}
if [ -e "$destination" ] || [ -L "$destination" ]; then
  if [ ! -d "$destination" ] || [ -L "$destination" ] || ! diff -qr "$work_dir/bend" "$destination" >/dev/null; then
    echo "Existing destination differs from the verified release: $destination" >&2
    echo "Choose an empty destination or inspect the existing installation." >&2
    exit 1
  fi
  echo "Existing installation matches the verified release: $destination"
else
  mv "$work_dir/bend" "$destination"
  echo "Installed verified compiler: $destination"
fi
"$destination/bin/bend" version
