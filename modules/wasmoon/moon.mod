name = "Milky2018/wasmoon"

version = "0.12.1"

import {
  "moonbitlang/x@0.4.48",
  "TheWaWaR/clap@0.2.6",
  "Milky2018/wasm_core@0.5.1",
  "Milky2018/wasm_milkir@0.6.1",
  "Milky2018/milkir@0.6.1",
  "Milky2018/machv@0.8.1",
  "Milky2018/milkir_machv@0.7.1",
  "Milky2018/machv_regalloc@0.6.1",
  "Milky2018/x64_target@0.5.1",
  "Milky2018/aarch64_target@0.6.1",
  "Milky2018/wasmoon_jit@0.7.1",
  "moonbitlang/async@0.20.5",
}

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "wasm", "webassembly", "runtime", "jit" ]

description = "A slow and insecure runtime for WebAssembly"

preferred_target = "native"

supported_targets = "native"
