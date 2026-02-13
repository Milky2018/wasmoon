#!/bin/sh
set -eu

# Build x86_64 ("amd64") native artifacts on Apple Silicon without replacing the
# primary arm64 MoonBit toolchain.
#
# Background:
# - MoonBit's macOS toolchain is arm64-only today.
# - However, `moon` supports `MOON_HOME` and `MOON_CC` overrides.
# - By cloning MOON_HOME and providing a universal `libmoonbitrun.o` that
#   includes an x86_64 slice, we can cross-link x86_64 executables using clang.
#
# Output (x86_64):
# - target-rosetta/native/release/build/cli/main/main.exe
# - target-rosetta/native/release/build/cli/tools/tools.exe

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

SOURCE_MOON_HOME="${SOURCE_MOON_HOME:-$HOME/.moon}"
ROSETTA_MOON_HOME="${ROSETTA_MOON_HOME:-$HOME/.moon-rosetta}"
TARGET_DIR="${TARGET_DIR:-$ROOT_DIR/target-rosetta}"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" 1>&2
    exit 1
  fi
}

need_cmd rsync
need_cmd moon
need_cmd clang
need_cmd ld
need_cmd lipo

if [ ! -d "$ROSETTA_MOON_HOME" ]; then
  rsync -a "$SOURCE_MOON_HOME/" "$ROSETTA_MOON_HOME/"
fi

mkdir -p "$ROSETTA_MOON_HOME/bin"
cat >"$ROSETTA_MOON_HOME/bin/clang-x86_64" <<'EOF'
#!/bin/sh
exec clang -arch x86_64 "$@"
EOF
chmod +x "$ROSETTA_MOON_HOME/bin/clang-x86_64"

if ! lipo -info "$ROSETTA_MOON_HOME/lib/libmoonbitrun.o" 2>/dev/null | grep -q 'x86_64'; then
  cd "$ROSETTA_MOON_HOME/lib"
  clang -c -O2 -arch x86_64 -I"$ROSETTA_MOON_HOME/include" runtime.c -o runtime.x86_64.o
  clang -c -O2 -arch x86_64 -I"$ROSETTA_MOON_HOME/include" runtime_core.c -o runtime_core.x86_64.o
  ld -r -arch x86_64 -o libmoonbitrun.x86_64.o runtime.x86_64.o runtime_core.x86_64.o
  lipo -create -output libmoonbitrun.o "$SOURCE_MOON_HOME/lib/libmoonbitrun.o" libmoonbitrun.x86_64.o
fi

cd "$ROOT_DIR"
MOON_HOME="$ROSETTA_MOON_HOME" \
  MOON_CC="$ROSETTA_MOON_HOME/bin/clang-x86_64" \
  MOON_AR=/usr/bin/ar \
  moon build --target native --release --target-dir "$TARGET_DIR"

echo "Built x86_64 executables:"
echo "  $TARGET_DIR/native/release/build/cli/main/main.exe"
echo "  $TARGET_DIR/native/release/build/cli/tools/tools.exe"
