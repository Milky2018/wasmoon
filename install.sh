#!/bin/bash

# Build and install wasmoon and wasmoon-tools

set -euo pipefail

repo_root="$(cd "$(dirname "$0")" && pwd)"
build_dir="${repo_root}/target/moon-install-build"
artifact_dir="${build_dir}/native/release/build/Milky2018/wasmoon/cmd"

install_binary() {
  local name="$1"
  local src="${artifact_dir}/${name}/${name}.exe"
  if [ ! -f "$src" ]; then
    src="${artifact_dir}/${name}/${name}"
  fi
  if [ ! -f "$src" ]; then
    echo "Error: missing built binary: ${artifact_dir}/${name}/${name}[.exe]" >&2
    exit 1
  fi
  cp -f "$src" "${repo_root}/${name}"
  chmod +x "${repo_root}/${name}"
}

rm -rf "$build_dir"

(
  cd "$repo_root"
  moon build \
    modules/wasmoon/cmd/wasmoon \
    modules/wasmoon/cmd/wasmoon-tools \
    --target native \
    --release \
    --target-dir "$build_dir"
)
rm -f "${repo_root}/wasmoon" "${repo_root}/wasmoon-tools"
install_binary wasmoon
install_binary wasmoon-tools
if command -v xattr >/dev/null 2>&1; then
  xattr -c "${repo_root}/wasmoon" "${repo_root}/wasmoon-tools" 2>/dev/null || true
fi

echo "Done! You can now run ./wasmoon and ./wasmoon-tools"
