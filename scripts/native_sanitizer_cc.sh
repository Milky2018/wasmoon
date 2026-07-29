#!/usr/bin/env bash
set -euo pipefail

exec "${WASMOON_SANITIZER_REAL_CC:?missing real C compiler}" "$@" \
  -O1 \
  -g \
  -fsanitize=address,undefined \
  -fno-omit-frame-pointer
