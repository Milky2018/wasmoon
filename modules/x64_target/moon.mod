name = "Milky2018/x64_target"

version = "0.5.2"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "x64", "x86-64", "compiler", "codegen" ]

description = "x64 target pipeline from semantic MachV to native code"

import {
  "Milky2018/milkir@0.6.2",
  "Milky2018/machv@0.8.2",
  "Milky2018/machv_regalloc@0.6.2",
  "Milky2018/milkir_machv@0.7.2",
}

preferred_target = "wasm-gc"

supported_targets = "all"
