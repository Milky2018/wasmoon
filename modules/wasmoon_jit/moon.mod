name = "Milky2018/wasmoon_jit"

version = "0.1.0"

license = "Apache-2.0"

description = "Wasmoon-specific JIT integration and native runtime glue"

import {
  "Milky2018/wasm_core@0.1.0",
  "Milky2018/milkir@0.1.0",
  "Milky2018/machv@0.1.0",
  "Milky2018/regalloc@0.1.0",
  "Milky2018/machv_regalloc@0.1.0",
  "Milky2018/machv_emit@0.1.0",
  "Milky2018/x64_target@0.1.0",
  "Milky2018/aarch64_target@0.1.0",
}

preferred_target = "native"

supported_targets = "native"
