# Wasmoon

WebAssembly Runtime in MoonBit

## Overview

Wasmoon is a WebAssembly interpreter written in MoonBit, targeting WebAssembly 1.0 specification compliance.

## Features

- **Binary Parser**: Full WASM binary format parsing with LEB128 decoding
- **WAT Parser**: Parse WebAssembly Text Format to WASM modules
- **Disassembler**: Convert WASM binary to WAT-like text format
- **Instruction Set**: 190+ instruction variants
- **Numeric Operations**: i32, i64, f32, f64 arithmetic, comparison, and bitwise operations
- **Runtime**: Stack-based execution with memory, tables, and globals

## Installation

```bash
moon add Milky2018/wasmoon
```

## Quick Start

```moonbit
///|
test "add function example" {
  // Define a module using WAT (WebAssembly Text Format)
  let wat =
    #|(module
    #|  (func (export "add") (param i32 i32) (result i32)
    #|    local.get 0
    #|    local.get 1
    #|    i32.add))
  let mod = @wat.parse(wat)

  // Instantiate and execute
  let (store, instance) = @executor.instantiate_module(mod)
  let result = @executor.call_exported_func(store, instance, "add", [
    @types.Value::I32(5),
    @types.Value::I32(3),
  ])
  inspect(result, content="[I32(8)]")
}
```

## License

Apache-2.0
