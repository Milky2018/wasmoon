name = "Milky2018/wasmoon_jit"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "wasm", "jit", "runtime", "native" ]

description = "Wasmoon-specific JIT integration and native runtime glue"

import {
  "moonbitlang/x@0.4.38",
  "Milky2018/wasm_core@0.1.0",
  "Milky2018/milkir@0.1.0",
  "Milky2018/machv@0.1.0",
  "Milky2018/isa_target@0.1.0",
  "Milky2018/machv_regalloc@0.1.0",
  "Milky2018/machv_emit@0.1.0",
}

preferred_target = "native"

supported_targets = "native"
