name = "Milky2018/vcode_regalloc"

version = "0.12.6"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "compiler", "register-allocation", "vcode", "jit" ]

description = "Target VCode adapter for the reusable register allocator"

import {
  "moonbitlang/x@0.4.48",
  "Milky2018/vcode@0.12.6",
  "Milky2018/regalloc@0.12.6",
}

preferred_target = "wasm-gc"

supported_targets = "all"
