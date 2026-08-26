name = "Milky2018/wasmoon_jit"

version = "0.7.3"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "wasm", "jit", "runtime", "native" ]

description = "Wasmoon-specific JIT integration and native runtime glue"

import {
  "moonbitlang/x@0.4.48",
  "Milky2018/wasm_core@0.5.3",
  "Milky2018/wasm_milkir@0.6.3",
  "Milky2018/wasm_machv@0.5.3",
  "Milky2018/milkir@0.6.3",
  "Milky2018/machv@0.8.3",
  "Milky2018/milkir_machv@0.7.3",
  "Milky2018/machv_regalloc@0.6.3",
  "Milky2018/aarch64_target@0.6.3",
  "Milky2018/x64_target@0.5.3",
}

preferred_target = "native"

supported_targets = "native"
