name = "Milky2018/wasmoon"

version = "0.12.6"

import {
  "moonbitlang/x@0.4.48",
  "TheWaWaR/clap@0.2.6",
  "Milky2018/wasm_core@0.12.6",
  "Milky2018/wasm_milkir@0.12.6",
  "Milky2018/milkir@0.12.6",
  "Milky2018/native_types@0.12.6",
  "Milky2018/native_lowering@0.12.6",
  "Milky2018/code_object@0.12.6",
  "Milky2018/vcode_regalloc@0.12.6",
  "Milky2018/x64_target@0.12.6",
  "Milky2018/aarch64_target@0.12.6",
  "Milky2018/wasmoon_jit@0.12.6",
  "moonbitlang/async@0.20.5",
}

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "wasm", "webassembly", "runtime", "jit" ]

description = "A slow and insecure runtime for WebAssembly"

preferred_target = "native"

supported_targets = "native"
