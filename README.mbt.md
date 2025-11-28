# Wasmoon

WebAssembly Runtime in MoonBit

## Overview

Wasmoon is a WebAssembly interpreter written in MoonBit, targeting WebAssembly 1.0 specification compliance.

## Features

- **Binary Parser**: Full WASM binary format parsing with LEB128 decoding
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
  // Create a module with an add function
  let mod : @wasmoon.Module = {
    types: [
      {
        params: [@wasmoon.ValueType::I32, @wasmoon.ValueType::I32],
        results: [@wasmoon.ValueType::I32],
      },
    ],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "add", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [
      {
        locals: [],
        body: [@wasmoon.LocalGet(0), @wasmoon.LocalGet(1), @wasmoon.I32Add],
      },
    ],
    datas: [],
  }

  // Instantiate and execute
  let (store, instance) = @executor.instantiate_module(mod)
  let result = @executor.call_exported_func(store, instance, "add", [
    @wasmoon.Value::I32(5),
    @wasmoon.Value::I32(3),
  ])
  inspect(result, content="[I32(8)]")
}
```

## Development

```bash
# Build
moon build

# Test
moon test

# Format
moon fmt
```

## Current Status

- Phase 1 (MVP): Complete
- Phase 2 (Core Features): In progress
  - Numeric operations: Done
  - Memory operations: Planned
  - Control flow: Planned

See [ROADMAP.md](ROADMAP.md) for details.

## License

Apache-2.0
