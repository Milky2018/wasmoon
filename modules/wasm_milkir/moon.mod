name = "Milky2018/wasm_milkir"

version = "0.13.0"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "wasm", "webassembly", "milkir", "compiler", "dialect" ]

description = "WebAssembly dialect adapter for MilkIR extension operations"

import {
  "Milky2018/milkir@0.13.0",
  "Milky2018/vcode@0.13.0",
}

preferred_target = "wasm-gc"

supported_targets = "all"
