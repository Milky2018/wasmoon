name = "Milky2018/machv_regalloc"

version = "0.3.2"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "compiler", "register-allocation", "machv", "jit" ]

description = "Target VCode adapter for the reusable register allocator"

import {
  "moonbitlang/x@0.4.38",
  "Milky2018/machv@0.5.2",
  "Milky2018/regalloc@0.4.1",
}

preferred_target = "wasm-gc"

supported_targets = "all"
