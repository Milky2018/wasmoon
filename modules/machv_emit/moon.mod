name = "Milky2018/machv_emit"

version = "0.2.2"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "compiler", "machine-code", "emitter", "jit" ]

description = "Reusable MachV machine-code emitter"

import {
  "moonbitlang/x@0.4.38",
  "Milky2018/machv_legacy@0.2.2",
  "Milky2018/machv_regalloc@0.2.2",
}

preferred_target = "native"

supported_targets = "native"
