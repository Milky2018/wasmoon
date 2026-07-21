name = "Milky2018/wasmoon_jit"

version = "0.2.0"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "wasm", "jit", "runtime", "native" ]

description = "Wasmoon-specific JIT integration and native runtime glue"

import {
  "moonbitlang/x@0.4.38",
  "Milky2018/wasm_core@0.1.2",
  "Milky2018/wasm_milkir@0.2.0",
  "Milky2018/wasm_machv@0.1.0",
  "Milky2018/milkir@0.2.0",
  "Milky2018/machv@0.3.0",
  "Milky2018/milkir_machv@0.3.0",
  "Milky2018/machv_regalloc@0.2.2",
  "Milky2018/aarch64_target@0.1.2",
  "Milky2018/x64_target@0.1.2",
}

preferred_target = "native"

supported_targets = "native"
