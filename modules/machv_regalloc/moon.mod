name = "Milky2018/machv_regalloc"

version = "0.6.0"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "compiler", "register-allocation", "machv", "jit" ]

description = "Target VCode adapter for the reusable register allocator"

import {
  "moonbitlang/x@0.4.48",
  "Milky2018/machv@0.8.0",
  "Milky2018/regalloc@0.7.0",
}

preferred_target = "wasm-gc"

supported_targets = "all"
