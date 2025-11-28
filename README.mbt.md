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

```text
// Create a module with an add function
let mod : @wasmoon.Module = {
  types: [{ params: [I32, I32], results: [I32] }],
  funcs: [0],
  codes: [{ locals: [], body: [LocalGet(0), LocalGet(1), I32Add] }],
  exports: [{ name: "add", desc: Func(0) }],
  ...
}

// Instantiate and execute
let (store, instance) = @wasmoon.instantiate_module(mod)
let result = @wasmoon.call_exported_func(store, instance, "add", [I32(5), I32(3)])
// result = [I32(8)]
```

## Project Structure

```
wasmoon/
├── wasmoon.mbt      # Core data structures (ValueType, Instruction, Module)
├── parser.mbt       # Binary format parser
├── runtime.mbt      # Runtime (Stack, Memory, Table, Store)
├── executor.mbt     # Instruction execution engine
└── cmd/main/        # CLI tool
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
