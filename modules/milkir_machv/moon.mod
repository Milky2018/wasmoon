name = "Milky2018/milkir_machv"

version = "0.12.5"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "compiler", "lowering", "isa", "codegen" ]

description = "MilkIR-to-MachV lowering"

import {
  "moonbitlang/x@0.4.48",
  "Milky2018/milkir@0.12.5",
  "Milky2018/machv@0.12.5",
}

preferred_target = "wasm-gc"

supported_targets = "all"
