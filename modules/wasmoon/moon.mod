name = "Milky2018/wasmoon"

version = "0.6.4"

import {
  "moonbitlang/x@0.4.38",
  "TheWaWaR/clap@0.2.6",
  "Milky2018/wasm_core@0.1.0",
  "Milky2018/milkir@0.1.0",
  "Milky2018/machv@0.1.0",
  "Milky2018/isa_target@0.1.0",
  "Milky2018/regalloc@0.1.0",
  "Milky2018/machv_regalloc@0.1.0",
  "Milky2018/machv_emit@0.1.0",
  "Milky2018/x64_target@0.1.0",
  "Milky2018/aarch64_target@0.1.0",
  "Milky2018/wasmoon_jit@0.1.0",
}

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "wasm", "runtime" ]

description = "A slow and insecure runtime for WebAssembly"

preferred_target = "native"

supported_targets = "native"
