name = "Milky2018/milkir_machv"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "compiler", "lowering", "isa", "codegen" ]

description = "MilkIR-to-MachV lowering"

import {
  "moonbitlang/x@0.4.38",
  "Milky2018/milkir@0.1.0",
  "Milky2018/machv@0.1.0",
}

preferred_target = "wasm-gc"

supported_targets = "all"
