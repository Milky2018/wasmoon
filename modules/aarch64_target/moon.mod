name = "Milky2018/aarch64_target"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "aarch64", "compiler", "codegen", "jit" ]

description = "AArch64 ISA target for lowering MilkIR into MachV"

import {
  "Milky2018/milkir@0.1.0",
  "Milky2018/machv@0.1.0",
}

preferred_target = "wasm-gc"

supported_targets = "all"
