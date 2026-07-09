name = "Milky2018/x64_target"

version = "0.1.1"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "x64", "x86-64", "compiler", "codegen" ]

description = "x64 ISA target for lowering MilkIR into MachV"

import {
  "Milky2018/milkir@0.1.1",
  "Milky2018/machv@0.2.1",
  "Milky2018/milkir_machv@0.2.1",
}

preferred_target = "wasm-gc"

supported_targets = "all"
