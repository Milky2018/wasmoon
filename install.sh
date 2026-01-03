#!/bin/bash

# Build and install wasmoon

set -e

moon build --target native --release
cp target/native/release/build/cli/main/main.exe ./wasmoon
chmod +x ./wasmoon

echo "Done! You can now run ./wasmoon"
