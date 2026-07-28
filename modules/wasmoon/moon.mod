name = "Milky2018/wasmoon"

version = "0.9.2"

import {
  "moonbitlang/x@0.4.38",
  "TheWaWaR/clap@0.2.6",
  "Milky2018/wasm_core@0.2.1",
  "Milky2018/wasm_milkir@0.3.2",
  "Milky2018/milkir@0.3.2",
  "Milky2018/machv@0.5.2",
  "Milky2018/milkir_machv@0.4.2",
  "Milky2018/machv_regalloc@0.3.2",
  "Milky2018/x64_target@0.2.2",
  "Milky2018/aarch64_target@0.3.2",
  "Milky2018/wasmoon_jit@0.4.2",
  "Milky2018/wasmoon_async@0.1.0",
}

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "wasm", "webassembly", "runtime", "jit" ]

description = "A slow and insecure runtime for WebAssembly"

preferred_target = "native"

supported_targets = "native"
