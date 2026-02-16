#!/bin/bash

# Build and install wasmoon and wasmoon-tools

set -euo pipefail

repo_root="$(cd "$(dirname "$0")" && pwd)"
install_dir="${repo_root}/target/moon-install-bin"

mkdir -p "$install_dir"

# Build + install binaries via `moon install`.
moon install --path "${repo_root}/cli/main" --bin "$install_dir"
moon install --path "${repo_root}/cli/tools" --bin "$install_dir"

main_bin="${install_dir}/main"
tools_bin="${install_dir}/tools"

if [ ! -f "$main_bin" ]; then
  echo "Error: missing installed binary: $main_bin" >&2
  exit 1
fi
if [ ! -f "$tools_bin" ]; then
  echo "Error: missing installed binary: $tools_bin" >&2
  exit 1
fi

# Install repo-local entrypoints atomically by swapping symlinks.
tmp_wasmoon="$(mktemp "${repo_root}/wasmoon.tmp.XXXXXX")"
ln -sf "$main_bin" "$tmp_wasmoon"
mv -f "$tmp_wasmoon" "${repo_root}/wasmoon"

tmp_tools="$(mktemp "${repo_root}/wasmoon-tools.tmp.XXXXXX")"
ln -sf "$tools_bin" "$tmp_tools"
mv -f "$tmp_tools" "${repo_root}/wasmoon-tools"

echo "Done! You can now run ./wasmoon and ./wasmoon-tools"
