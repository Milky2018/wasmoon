#!/bin/bash

# Build and install wasmoon and wasmoon-tools

set -e

moon build --target native --release

# Install binaries atomically (avoid overwriting an inode that may still be
# mapped by an existing process).
tmp_wasmoon="$(mktemp ./wasmoon.tmp.XXXXXX)"
cp target/native/release/build/cli/main/main.exe "$tmp_wasmoon"
chmod +x "$tmp_wasmoon"
mv -f "$tmp_wasmoon" ./wasmoon

tmp_tools="$(mktemp ./wasmoon-tools.tmp.XXXXXX)"
cp target/native/release/build/cli/tools/tools.exe "$tmp_tools"
chmod +x "$tmp_tools"
mv -f "$tmp_tools" ./wasmoon-tools

echo "Done! You can now run ./wasmoon and ./wasmoon-tools"
