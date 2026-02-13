#!/bin/bash

# Build and install wasmoon and wasmoon-tools

set -e

# Build the main packages explicitly. With newer `moon` toolchains, building at
# the repo root may not build main packages automatically.
moon build --target native --release cli/main
moon build --target native --release cli/tools

resolve_binary() {
  local binary_name="$1"
  shift
  local explicit_paths=("$@")

  for explicit_path in "${explicit_paths[@]}"; do
    if [ -n "$explicit_path" ] && [ -f "$explicit_path" ]; then
      echo "$explicit_path"
      return 0
    fi
  done

  local found
  for build_root in "_build/native/release/build" "target/native/release/build"; do
    if [ -d "$build_root" ]; then
      found="$(find "$build_root" -type f \
        \( -name "${binary_name}.exe" -o -name "${binary_name}" \) \
        | head -n 1)"
      if [ -n "$found" ] && [ -f "$found" ]; then
        echo "$found"
        return 0
      fi
    fi
  done

  echo "Error: cannot find built binary for ${binary_name}" >&2
  return 1
}

canonical_path() {
  local target="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$target"
    return
  fi
  local dir
  dir="$(cd "$(dirname "$target")" && pwd)"
  echo "${dir}/$(basename "$target")"
}

main_bin="$(resolve_binary "main" \
  "_build/native/release/build/cli/main/main.exe" \
  "target/native/release/build/cli/main/main.exe")"
tools_bin="$(resolve_binary "tools" \
  "_build/native/release/build/cli/tools/tools.exe" \
  "target/native/release/build/cli/tools/tools.exe")"
main_bin_abs="$(canonical_path "$main_bin")"
tools_bin_abs="$(canonical_path "$tools_bin")"

# Install binaries atomically by swapping symlinks (avoids copying, and avoids
# overwriting an inode that may still be mapped by an existing process).
tmp_wasmoon="$(mktemp ./wasmoon.tmp.XXXXXX)"
ln -sf "$main_bin_abs" "$tmp_wasmoon"
mv -f "$tmp_wasmoon" ./wasmoon

tmp_tools="$(mktemp ./wasmoon-tools.tmp.XXXXXX)"
ln -sf "$tools_bin_abs" "$tmp_tools"
mv -f "$tmp_tools" ./wasmoon-tools

echo "Done! You can now run ./wasmoon and ./wasmoon-tools"
