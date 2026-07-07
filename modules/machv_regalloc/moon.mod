name = "Milky2018/machv_regalloc"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "compiler", "register-allocation", "machv", "jit" ]

description = "MachV adapter for the reusable register allocator"

import {
  "moonbitlang/x@0.4.38",
  "Milky2018/machv@0.1.0",
  "Milky2018/regalloc@0.1.0",
}

preferred_target = "native"

supported_targets = "native"
