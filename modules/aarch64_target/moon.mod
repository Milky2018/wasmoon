name = "Milky2018/aarch64_target"

version = "0.1.2"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "aarch64", "compiler", "codegen", "jit" ]

description = "AArch64 ISA target for lowering MilkIR into MachV"

import {
  "Milky2018/milkir@0.2.0",
  "Milky2018/machv@0.3.0",
  "Milky2018/machv_regalloc@0.2.2",
  "Milky2018/milkir_machv@0.3.0",
}

preferred_target = "wasm-gc"

supported_targets = "all"
