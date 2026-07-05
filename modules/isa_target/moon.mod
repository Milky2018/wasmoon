name = "Milky2018/isa_target"

version = "0.1.0"

license = "Apache-2.0"

description = "ISA lowering from MilkIR to MachV VCode"

import {
  "moonbitlang/x@0.4.38",
  "Milky2018/wasm_core@0.1.0",
  "Milky2018/milkir@0.1.0",
  "Milky2018/machv@0.1.0",
  "Milky2018/machv_regalloc@0.1.0",
}

preferred_target = "native"

supported_targets = "native"
