# Wasmoon

A WebAssembly runtime written in MoonBit with JIT compilation support.

> **Warning**: This project is primarily developed with AI assistance and has not been thoroughly audited. **Do not use in production or security-sensitive environments.**

> **Note**: The JIT compiler performs minimal optimization. Expect slower execution compared to production runtimes like Wasmtime or Wasmer.

## Features

- **JIT Compiler**: AArch64 native code generation with SSA-based IR
- **Interpreter**: Full WebAssembly 1.0 support as fallback
- **WAT/WASM Parser**: Parse both text and binary formats
- **WASI Preview 1 Support**: File I/O, environment variables, command-line arguments

## Installation

### As CLI Tool

```bash
git clone https://github.com/Milky2018/wasmoon.git
cd wasmoon
moon build && ./install.sh
```

`./install.sh` installs two binaries in the repository root:

- `./wasmoon`: the runtime CLI
- `./wasmoon-tools`: utility tooling (validate/convert/WIT inspection)

### As Library

```bash
moon add Milky2018/wasmoon
```

## CLI Usage

Quick differential testing vs Wasmtime (wasm-smith):
```bash
python3 scripts/smith_diff/run.py run --count 1000
```

```bash
# Run with default _start function
wasmoon run hello.wat

# Call a specific function with arguments
wasmoon run examples/add.wat --invoke add --arg 5 --arg 3

# Run with interpreter (no JIT)
wasmoon run examples/add.wat --invoke add --arg 5 --arg 3 --no-jit

# Run WAST test scripts
wasmoon test spec/i32.wast

# Run component-model .wast tests (validation-only; requires wasm-tools)
python3 scripts/run_component_wast.py --dir component-spec --rec

# Explore compilation stages (IR, VCode, machine code)
wasmoon explore examples/add.wat --stage ir vcode mc
```

## wasmoon-tools Usage

`wasmoon-tools` is a small companion CLI for common inspection/conversion tasks:

```bash
# Validate a core Wasm module (WASM/WAT)
./wasmoon-tools validate examples/add.wat

# Convert between WASM and WAT
./wasmoon-tools wasm2wat examples/add.wasm -o examples/add.wat
./wasmoon-tools wat2wasm examples/add.wat -o examples/add.wasm

# Parse WIT (text) and print a normalized representation
./wasmoon-tools wit path/to/foo.wit

# Parse a directory as a WIT package (all *.wit files, sorted by filename),
# resolve it with `deps/`, and print a canonicalized output (toplevel-use removed,
# include flattened, and transitive interface imports injected).
./wasmoon-tools wit path/to/pkgdir

# Emit the resolved WIT graph to a directory (root + deps/*.wit)
./wasmoon-tools wit path/to/pkgdir --out-dir out

# Emit a JSON AST (stable, for scripting/debugging)
./wasmoon-tools wit path/to/foo.wit --json

# Encode a WIT package as a component (type-only) binary / text
./wasmoon-tools wit path/to/foo.wit --wasm -o foo.wasm
./wasmoon-tools wit path/to/foo.wit --wat > foo.wat

# Alias for compatibility with wasm-tools' subcommand shape
./wasmoon-tools component wit path/to/foo.wit --json
```

WIT support is still evolving. `wasmoon-tools wit` implements directory + `deps/` resolution, and can emit a minimal component representation for simple WIT packages (currently functions with built-in scalar types).

## Library Usage

### Basic Example

```moonbit check
///|
test "basic add" {
  let wat =
    #|(module
    #|  (func (export "add") (param i32 i32) (result i32)
    #|    local.get 0
    #|    local.get 1
    #|    i32.add))
  let mod = @wat.parse(wat)
  let (store, instance) = @executor.instantiate_module(mod)
  let result = @executor.call_exported_func(store, instance, "add", [
    @types.Value::I32(5),
    @types.Value::I32(3),
  ])
  inspect(result, content="[I32(8)]")
}
```

### Memory Operations

```moonbit check
///|
test "memory" {
  let wat =
    #|(module
    #|  (memory (export "mem") 1)
    #|  (func (export "store") (param i32 i32)
    #|    local.get 0 local.get 1 i32.store)
    #|  (func (export "load") (param i32) (result i32)
    #|    local.get 0 i32.load))
  let mod = @wat.parse(wat)
  let (store, instance) = @executor.instantiate_module(mod)
  @executor.call_exported_func(store, instance, "store", [
    @types.Value::I32(0),
    @types.Value::I32(42),
  ])
  |> ignore
  let result = @executor.call_exported_func(store, instance, "load", [
    @types.Value::I32(0),
  ])
  inspect(result, content="[I32(42)]")
}
```

### Cross-module Imports

```moonbit check
///|
test "cross-module" {
  let linker = @runtime.Linker::new()
  let mod_a =
    #|(module (func (export "add") (param i32 i32) (result i32)
    #|  local.get 0 local.get 1 i32.add))
  let mod_a = @wat.parse(mod_a)
  let inst_a = @executor.instantiate_with_linker(linker, "math", mod_a)
  linker.register("math", inst_a)
  let mod_b =
    #|(module
    #|  (import "math" "add" (func $add (param i32 i32) (result i32)))
    #|  (func (export "use_add") (param i32 i32) (result i32)
    #|    local.get 0 local.get 1 call $add))
  let mod_b = @wat.parse(mod_b)
  let inst_b = @executor.instantiate_with_linker(linker, "main", mod_b)
  let result = @executor.call_exported_func(
    linker.get_store(),
    inst_b,
    "use_add",
    [@types.Value::I32(3), @types.Value::I32(5)],
  )
  inspect(result, content="[I32(8)]")
}
```

### Host Functions

```moonbit check
///|
test "host function" {
  let linker = @runtime.Linker::new()
  // Register a host function that doubles an i32
  linker.add_host_func(
    "env",
    "double",
    fn(args) {
      guard args[0] is @types.Value::I32(x) else { return [] }
      [@types.Value::I32(x * 2)]
    },
    func_type={
      params: [@types.ValueType::I32],
      results: [@types.ValueType::I32],
    },
  )
  let wat =
    #|(module
    #|  (import "env" "double" (func $double (param i32) (result i32)))
    #|  (func (export "quadruple") (param i32) (result i32)
    #|    local.get 0 call $double call $double))
  let mod = @wat.parse(wat)
  let instance = @executor.instantiate_with_linker(linker, "main", mod)
  let result = @executor.call_exported_func(
    linker.get_store(),
    instance,
    "quadruple",
    [@types.Value::I32(5)],
  )
  inspect(result, content="[I32(20)]")
}
```

## Project Status

- [x] WebAssembly 1.0 core specification
- [x] JIT compiler (AArch64)
- [x] Multi-value returns
- [x] Reference types (funcref, externref)
- [x] Tail calls
- [x] Cross-module function calls
- [ ] WASI Preview 1 (partial)
- [ ] GC proposal (in progress)
- [ ] JIT compiler (x86-64)
- [ ] Component Model
- [ ] JIT optimizations (constant folding, dead code elimination, etc.)

## License

Apache-2.0
