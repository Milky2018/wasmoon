name = "Milky2018/wasm_isa_lower"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "wasm", "compiler", "lowering", "jit" ]

description = "WebAssembly MilkIR dialect adapter for MachV lowering"

import {
  "moonbitlang/x@0.4.38",
  "Milky2018/wasm_milkir@0.1.0",
  "Milky2018/milkir@0.1.0",
  "Milky2018/machv@0.1.0",
  "Milky2018/milkir_machv@0.1.0",
}

preferred_target = "wasm-gc"

supported_targets = "all"
