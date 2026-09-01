name = "Milky2018/wasm_machv"

version = "0.12.6"

readme = "README.mbt.md"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "wasm", "webassembly", "milkir", "machv", "lowering" ]

description = "WebAssembly MilkIR dialect adapter for target-neutral MachV"

import {
  "Milky2018/wasm_milkir@0.12.6",
  "Milky2018/milkir@0.12.6",
  "Milky2018/native_types@0.12.6",
  "Milky2018/milkir_machv@0.12.6",
}

preferred_target = "wasm-gc"

supported_targets = "all"
