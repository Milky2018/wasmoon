name = "Milky2018/aarch64_target"

version = "0.12.6"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "aarch64", "compiler", "codegen", "jit" ]

description = "AArch64 direct MilkIR target pipeline to native code"

import {
  "Milky2018/milkir@0.12.6",
  "Milky2018/vcode@0.12.6",
  "Milky2018/vcode_regalloc@0.12.6",
}

preferred_target = "wasm-gc"

supported_targets = "all"
