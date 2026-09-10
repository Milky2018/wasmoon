name = "Milky2018/wasmoon"

version = "0.15.0"

import {
  "moonbitlang/x@0.5.1",
  "Milky2018/wasm_core@0.15.0",
  "Milky2018/wasm_component@0.15.0",
  "Milky2018/wasm_milkir@0.15.0",
  "Milky2018/milkir@0.15.0",
  "Milky2018/vcode@0.15.0",
  "Milky2018/vcode_regalloc@0.15.0",
  "Milky2018/x64_target@0.15.0",
  "Milky2018/aarch64_target@0.15.0",
  "Milky2018/wasmoon_jit@0.15.0",
  "moonbitlang/async@0.21.2",
}

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "wasm", "webassembly", "runtime", "jit" ]

description = "A slow and insecure runtime for WebAssembly"

preferred_target = "native"

supported_targets = "native"
