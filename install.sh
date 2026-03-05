#!/bin/bash

# Build and install wasmoon and wasmoon-tools

set -euo pipefail

repo_root="$(cd "$(dirname "$0")" && pwd)"
install_dir="${repo_root}/target/moon-install-bin"

mkdir -p "$install_dir"

# Build + install binaries via `moon install`.
moon install --path "${repo_root}/cmd/wasmoon" --bin "$install_dir"
moon install --path "${repo_root}/cmd/wasmoon-tools" --bin "$install_dir"

main_bin="${install_dir}/wasmoon"
tools_bin="${install_dir}/wasmoon-tools"

if [ ! -f "$main_bin" ]; then
  echo "Error: missing installed binary: $main_bin" >&2
  exit 1
fi
if [ ! -f "$tools_bin" ]; then
  echo "Error: missing installed binary: $tools_bin" >&2
  exit 1
fi

# Install repo-local entrypoints as direct binaries.
# On macOS, running symlinked binaries from moon-install output can occasionally
# get stuck during dynamic loader startup, so we keep a local executable copy.
rm -f "${repo_root}/wasmoon" "${repo_root}/wasmoon-tools"
cp -f "$main_bin" "${repo_root}/wasmoon"
cp -f "$tools_bin" "${repo_root}/wasmoon-tools"
chmod +x "${repo_root}/wasmoon" "${repo_root}/wasmoon-tools"
if command -v xattr >/dev/null 2>&1; then
  xattr -c "${repo_root}/wasmoon" "${repo_root}/wasmoon-tools" 2>/dev/null || true
fi

echo "Done! You can now run ./wasmoon and ./wasmoon-tools"
