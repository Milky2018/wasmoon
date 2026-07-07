name = "Milky2018/machv"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "compiler", "machine-ir", "codegen", "jit" ]

description = "Reusable virtual-register machine IR"

import {
  "Milky2018/wasm_core@0.1.0",
  "Milky2018/milkir@0.1.0",
}

preferred_target = "wasm-gc"

supported_targets = "all"
