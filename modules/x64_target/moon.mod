name = "Milky2018/x64_target"

version = "0.1.3"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "x64", "x86-64", "compiler", "codegen" ]

description = "x64 target pipeline from semantic MachV to native code"

import {
  "Milky2018/milkir@0.2.1",
  "Milky2018/machv@0.4.0",
  "Milky2018/machv_regalloc@0.2.3",
  "Milky2018/milkir_machv@0.3.1",
}

preferred_target = "wasm-gc"

supported_targets = "all"
