name = "Milky2018/wasm_machv"

version = "0.3.0"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "wasm", "webassembly", "milkir", "machv", "lowering" ]

description = "WebAssembly MilkIR dialect adapter for target-neutral MachV"

import {
  "Milky2018/wasm_milkir@0.4.0",
  "Milky2018/milkir@0.4.0",
  "Milky2018/machv@0.6.0",
  "Milky2018/milkir_machv@0.5.0",
}

preferred_target = "wasm-gc"

supported_targets = "all"
