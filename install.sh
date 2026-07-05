#!/bin/bash

# Build and install wasmoon and wasmoon-tools

set -euo pipefail

repo_root="$(cd "$(dirname "$0")" && pwd)"
wasmoon_module="${repo_root}/modules/wasmoon"
build_dir="${repo_root}/target/moon-install-build"
install_dir="${repo_root}/target/moon-install-bin"

rm -rf "$build_dir" "$install_dir"
mkdir -p "$build_dir"
mkdir -p "$install_dir"

# Build release artifacts first, then copy selected executables.
# This mirrors Wasmtime's release-artifact pipeline style.
moon -C "$wasmoon_module" build --target native --release --target-dir "$build_dir"

release_build_dir="${build_dir}/native/release/build"
main_bin_src="$(find "$release_build_dir" -type f \( \
  -path "*/cmd/wasmoon/wasmoon.exe" -o \
  -path "*/cmd/wasmoon/wasmoon" \
\) | sort | head -n 1)"
tools_bin_src="$(find "$release_build_dir" -type f \( \
  -path "*/cmd/wasmoon-tools/wasmoon-tools.exe" -o \
  -path "*/cmd/wasmoon-tools/wasmoon-tools" \
\) | sort | head -n 1)"

if [ -z "$main_bin_src" ] || [ ! -f "$main_bin_src" ]; then
  echo "Error: missing built wasmoon binary under $release_build_dir" >&2
  exit 1
fi
if [ -z "$tools_bin_src" ] || [ ! -f "$tools_bin_src" ]; then
  echo "Error: missing built wasmoon-tools binary under $release_build_dir" >&2
  exit 1
fi

main_bin="${install_dir}/wasmoon"
tools_bin="${install_dir}/wasmoon-tools"

cp -f "$main_bin_src" "$main_bin"
cp -f "$tools_bin_src" "$tools_bin"

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
