name = "Milky2018/wasmoon_runtime"

version = "0.17.0"

import {
  "moonbitlang/x@0.5.5",
  "Milky2018/wasm_core@0.17.0",
  "Milky2018/wasm_milkir@0.17.0",
  "moonbitlang/async@0.22.4",
}

readme = "README.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

description = "Shared Wasmoon interpreter state and target-specific storage primitives"

preferred_target = "native"

supported_targets = "native+wasm"
