# Wasmoon

A WebAssembly runtime written in MoonBit with JIT compilation support.

## Features

- **JIT Compiler**: AArch64 native code generation with SSA-based IR
- **Interpreter**: Full WebAssembly 1.0 support as fallback
- **WAT/WASM Parser**: Parse both text and binary formats
- **WASI Support**: File I/O, environment variables, command-line arguments
- **Cross-module Calls**: Import functions from other JIT-compiled modules

## Installation

### As CLI Tool

```bash
git clone https://github.com/user/wasmoon.git
cd wasmoon
moon build && ./install.sh
```

### As Library

```bash
moon add Milky2018/wasmoon
```

## CLI Usage

### Run a WebAssembly Module

```bash
# Run with default _start function
wasmoon run hello.wat

# Call a specific function with arguments
wasmoon run examples/add.wat --invoke add --arg 5 --arg 3
# Output: 8

# Run with interpreter (no JIT)
wasmoon run examples/add.wat --invoke add --arg 5 --arg 3 --no-jit
```

### Run WAST Test Scripts

```bash
wasmoon test spec/i32.wast
```

### Explore Compilation Stages

```bash
# View IR, VCode, and machine code
wasmoon explore examples/add.wat --stage ir vcode mc
```

## Library Usage

### Basic Example

```moonbit
test "basic add" {
  let wat =
    #|(module
    #|  (func (export "add") (param i32 i32) (result i32)
    #|    local.get 0
    #|    local.get 1
    #|    i32.add))

  let mod = @wat.parse(wat)!
  let (store, instance) = @executor.instantiate_module(mod)!
  let result = @executor.call_exported_func(store, instance, "add", [
    @types.Value::I32(5),
    @types.Value::I32(3),
  ])!
  inspect!(result, content="[I32(8)]")
}
```

### Memory Operations

```moonbit
test "memory example" {
  let wat =
    #|(module
    #|  (memory (export "mem") 1)
    #|  (func (export "store") (param i32 i32)
    #|    local.get 0
    #|    local.get 1
    #|    i32.store)
    #|  (func (export "load") (param i32) (result i32)
    #|    local.get 0
    #|    i32.load))

  let mod = @wat.parse(wat)!
  let (store, instance) = @executor.instantiate_module(mod)!

  // Store value 42 at address 0
  @executor.call_exported_func(store, instance, "store", [
    @types.Value::I32(0),
    @types.Value::I32(42),
  ])! |> ignore

  // Load value from address 0
  let result = @executor.call_exported_func(store, instance, "load", [
    @types.Value::I32(0),
  ])!
  inspect!(result, content="[I32(42)]")
}
```

### Cross-module Imports

```moonbit
test "cross-module" {
  let linker = @runtime.Linker::new()

  // Module A: exports add function
  let mod_a = @wat.parse(
    #|(module
    #|  (func (export "add") (param i32 i32) (result i32)
    #|    local.get 0 local.get 1 i32.add))
  )!
  let inst_a = @executor.instantiate_with_linker(linker, "math", mod_a)!
  linker.register("math", inst_a)

  // Module B: imports from Module A
  let mod_b = @wat.parse(
    #|(module
    #|  (import "math" "add" (func $add (param i32 i32) (result i32)))
    #|  (func (export "double_add") (param i32 i32) (result i32)
    #|    local.get 0 local.get 1 call $add
    #|    local.get 0 local.get 1 call $add
    #|    i32.add))
  )!
  let inst_b = @executor.instantiate_with_linker(linker, "main", mod_b)!

  let store = linker.get_store()
  let result = @executor.call_exported_func(store, inst_b, "double_add", [
    @types.Value::I32(3),
    @types.Value::I32(5),
  ])!
  inspect!(result, content="[I32(16)]")  // (3+5) + (3+5) = 16
}
```

### WASI Example

```bash
# Hello World with WASI
wasmoon run examples/hello_wasi.wat

# Pass command-line arguments
wasmoon run examples/args_wasi.wat -- arg1 arg2

# Grant directory access
wasmoon run program.wasm --dir ./data
```

## Project Status

| Feature | Status |
|---------|--------|
| WebAssembly 1.0 | Done |
| JIT (AArch64) | Done |
| WASI Preview 1 | Partial |
| Multi-value | Done |
| Reference Types | Done |
| Tail Calls | Done |
| GC | In Progress |
| Component Model | Planned |
| JIT (x86-64) | Planned |

## Development

```bash
moon check          # Type check
moon test           # Run tests
moon fmt            # Format code
moon info           # Update .mbti files
```

## License

Apache-2.0
