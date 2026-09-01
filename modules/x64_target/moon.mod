name = "Milky2018/x64_target"

version = "0.12.6"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "x64", "x86-64", "compiler", "codegen" ]

description = "x64 target pipeline from semantic MachV to native code"

import {
  "Milky2018/milkir@0.12.6",
  "Milky2018/native_types@0.12.6",
  "Milky2018/vcode@0.12.6",
  "Milky2018/code_object@0.12.6",
  "Milky2018/vcode_regalloc@0.12.6",
  "Milky2018/milkir_machv@0.12.6",
}

preferred_target = "wasm-gc"

supported_targets = "all"
