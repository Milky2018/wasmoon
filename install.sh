#!/bin/bash

# Build and install wasmoon and wasmoon-tools

set -e

moon build --target native --release

# Install binaries atomically by swapping symlinks (avoids copying, and avoids
# overwriting an inode that may still be mapped by an existing process).
tmp_wasmoon="$(mktemp ./wasmoon.tmp.XXXXXX)"
ln -sf target/native/release/build/cli/main/main.exe "$tmp_wasmoon"
mv -f "$tmp_wasmoon" ./wasmoon

tmp_tools="$(mktemp ./wasmoon-tools.tmp.XXXXXX)"
ln -sf target/native/release/build/cli/tools/tools.exe "$tmp_tools"
mv -f "$tmp_tools" ./wasmoon-tools

echo "Done! You can now run ./wasmoon and ./wasmoon-tools"
