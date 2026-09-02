name = "Milky2018/vcode_regalloc"

version = "0.14.0"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "compiler", "register-allocation", "vcode", "jit" ]

description = "Target VCode adapter for the reusable register allocator"

import {
  "moonbitlang/x@0.5.1",
  "Milky2018/vcode@0.14.0",
  "Milky2018/regalloc@0.14.0",
}

preferred_target = "wasm-gc"

supported_targets = "all"
