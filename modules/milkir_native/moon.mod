name = "Milky2018/milkir_native"

version = "0.12.6"

repository = "https://github.com/Milky2018/wasmoon.git"

license = "Apache-2.0"

keywords = [ "compiler", "milkir", "native-code", "lowering" ]

description = "Direct streaming lowering from MilkIR to native target selectors"

import {
  "Milky2018/milkir@0.12.6",
  "Milky2018/native_types@0.12.6",
  "Milky2018/native_lowering@0.12.6",
}

preferred_target = "wasm-gc"

supported_targets = "all"
