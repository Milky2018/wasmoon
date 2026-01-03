#!/bin/bash

# Build and install wasmoon and wasmoon-tools

set -e

moon build --target native --release

# Install main wasmoon binary
cp target/native/release/build/cli/main/main.exe ./wasmoon
chmod +x ./wasmoon

# Install wasmoon-tools binary
cp target/native/release/build/cli/tools/tools.exe ./wasmoon-tools
chmod +x ./wasmoon-tools

echo "Done! You can now run ./wasmoon and ./wasmoon-tools"
