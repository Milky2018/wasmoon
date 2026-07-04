# Wasmoon

A WebAssembly runtime written in MoonBit with JIT compilation support.

> **Warning**: This project is primarily developed with AI assistance and has not been thoroughly audited. **Do not use in production or security-sensitive environments.**

> **Note**: JIT optimization is actively improving. Performance depends on workload and platform; benchmark your target programs for an accurate comparison.

## Features

- **JIT Compiler**: AArch64 and amd64 native code generation with SSA-based IR
- **Interpreter**: Full WebAssembly 1.0 support as fallback
- **WAT/WASM Parser**: Parse both text and binary formats
- **WASI Preview 1 Support**: File I/O, environment variables, command-line arguments
- **GC Proposal Support**: i31/struct/array/ref operations in interpreter and JIT
- **Component Model**: Component parser/validator/runtime with component-spec runner support

## Requirements

- Required:
  - `moon`
  - `python3`
- Optional:
  - `wasmtime` (useful for differential/performance comparison workflows)

## Installation

### Path A: Global install (recommended)

```bash
moon install Milky2018/wasmoon/cmd/wasmoon
moon install Milky2018/wasmoon/cmd/wasmoon-tools
```

If your registry release does not expose these main packages yet, install from
the Git repository directly:

```bash
moon install https://github.com/Milky2018/wasmoon.git cmd/wasmoon
moon install https://github.com/Milky2018/wasmoon.git cmd/wasmoon-tools
```

Verify binaries are on `PATH`:

```bash
wasmoon --help
wasmoon-tools --help
```

By default these commands install binaries to `~/.moon/bin/` as:

- `wasmoon` (runtime CLI)
- `wasmoon-tools` (utility CLI)

### Path B: Repo-local build (development)

```bash
git clone https://github.com/Milky2018/wasmoon.git
cd wasmoon
./install.sh
```

`./install.sh` uses `moon build --target native --release` to build local binaries
into `target/moon-install-build/`, copies them to `target/moon-install-bin/`, and
then refreshes two repo-root executables:

- `./wasmoon`
- `./wasmoon-tools`

After code changes, re-run `./install.sh` to refresh both executables.

### As Library

```bash
moon add Milky2018/wasmoon
```

## Quick Start (60 seconds)

```bash
# 1) Run with default _start
wasmoon run examples/add.wat

# 2) Invoke an export with arguments
wasmoon run examples/add.wat --invoke add --arg 5 --arg 3

# 3) Interpreter mode
wasmoon run examples/add.wat --invoke add --arg 5 --arg 3 --no-jit

# 4) WASI dirs/env/options
wasmoon run examples/hello_wasi.wat \
  --dir . \
  --env FOO=bar \
  -S inherit-env
```

For detailed flags, run:

```bash
wasmoon run --help
```

## CLI Commands (concise)

```bash
# run
wasmoon run examples/add.wat --invoke add --arg 1 --arg 2
wasmoon run --help

# test
wasmoon test spec/i32.wast
wasmoon test --help

# explore
wasmoon explore examples/add.wat --stage ir vcode mc
wasmoon explore --help

# component
wasmoon component path/to/component.wasm --validate
wasmoon component --help

# component-test
wasmoon component-test path/to/component-tests.json
wasmoon component-test --help

# wat
wasmoon wat examples/add.wat
wasmoon wat --help

# disasm
wasmoon disasm examples/stream.wasm
wasmoon disasm --help
```

Quick differential testing vs Wasmtime (wasm-smith):

```bash
python3 scripts/smith_diff/run.py run --count 1000
```

## JIT Trap Debugging

Use these options when diagnosing JIT failures:

- `-D`: debug logging
- `--dump-on-trap`: dump IR/VCode/MC for the trapping function
- `-W`: generate DWARF debug info for JIT code (better stack traces in LLDB)

Example:

```bash
wasmoon run examples/core_ed25519.wasm -D --dump-on-trap -W
```

LLDB quick recipe:

```bash
lldb -- ./wasmoon run examples/core_ed25519.wasm
(lldb) run
(lldb) bt
```

## wasmoon-tools Usage

`wasmoon-tools` provides common validation/conversion/WIT workflows:

```bash
# Validate a core Wasm module (WASM/WAT)
wasmoon-tools validate examples/add.wat

# Convert between WASM and WAT
wasmoon-tools wasm2wat examples/stream.wasm -o examples/stream.wat
wasmoon-tools wat2wasm examples/add.wat -o examples/add.wasm

# Parse WIT and print normalized text / JSON
wasmoon-tools wit path/to/foo.wit
wasmoon-tools wit path/to/foo.wit --json

# Resolve a directory package (with deps/) and emit graph
wasmoon-tools wit path/to/pkgdir
wasmoon-tools wit path/to/pkgdir --out-dir out

# Encode WIT package as component binary / text
wasmoon-tools wit path/to/foo.wit --wasm -o foo.wasm
wasmoon-tools wit path/to/foo.wit --wat > foo.wat

# Importize world flow
wasmoon-tools wit foo.wasm --importize --wat
wasmoon-tools wit path/to/pkgdir --importize-world my-world --wat

# Compatibility alias (wasm-tools-like shape)
wasmoon-tools component wit path/to/foo.wit --json
```

WIT support is still evolving. Current `wasmoon-tools wit` supports parse/resolve
(`deps/`), JSON output, component encode/decode/importize workflows, and tested
non-scalar/resource-related cases. Some spec corners may still be unsupported.

## License

Wasmoon is licensed under Apache-2.0. Some test suites, benchmark workloads,
and generated diagnostic artifacts are imported from third-party projects under
their own compatible licenses. See `THIRD_PARTY_NOTICES.md`.

## Validation / CI-equivalent Checks

```bash
moon check --target native
moon test --target native
./install.sh
cargo install wasm-tools --version 1.248.0 --locked
python3 scripts/run_all_wast.py --dir spec --rec
python3 scripts/run_component_wast.py --dir component-spec --rec
```

## Library Usage

### JIT GC Setup Migration

`@jit.gc_setup(...)` now requires VMContext + full function-table context for typed funcref/ref.func safety:

- `ctx_ptr`
- `func_type_indices`
- `func_table_ptr`
- `num_funcs`

`@jit.gc_teardown(...)` also requires the same `ctx_ptr`.

GC runtime caches/heap references are now VMContext-local (no process-global GC cache state), aligned with Wasmtime-style per-store/per-context runtime isolation.
The API fails fast with `GCSetupError` when setup context is incomplete or inconsistent.

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
    I32(5),
    I32(3),
  ])
  debug_inspect(result, content="[I32(8)]")
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
  @executor.call_exported_func(store, instance, "store", [I32(0), I32(42)])
  |> ignore
  let result = @executor.call_exported_func(store, instance, "load", [I32(0)])
  debug_inspect(result, content="[I32(42)]")
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
    [I32(3), I32(5)],
  )
  debug_inspect(result, content="[I32(8)]")
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
      guard args[0] is I32(x) else { return [] }
      [I32(x * 2)]
    },
    func_type={ params: [I32], results: [I32] },
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
    [I32(5)],
  )
  debug_inspect(result, content="[I32(20)]")
}
```

## Project Status

- [x] WebAssembly 1.0 core specification
- [x] JIT compiler (AArch64, amd64)
- [x] Multi-value returns
- [x] Reference types (funcref, externref)
- [x] Tail calls
- [x] Cross-module function calls
- [x] WASI Preview 1 support
- [x] GC proposal support (current implemented subset; experimental)
- [x] Component Model support
- [x] JIT optimizations (constant folding, dead code elimination, etc.)

## Contributor Note

- Edit `README.mbt.md` as the source of truth.
- `README.md` is a symlink to `README.mbt.md`.

## License

Apache-2.0
