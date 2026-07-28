# Wasmoon CLI

Command-line interface for the wasmoon WebAssembly runtime.

## Installation

```bash
moon build
./install.sh
```

This builds the project and installs the `wasmoon` binary.

## Commands

### Run WebAssembly

```bash
./wasmoon run <file.wasm|file.wat> [args...]
```

Execute a WebAssembly module. Supports both binary (.wasm) and text (.wat) formats.

Options:
- `--no-jit`: Run in interpreter-only mode (disable JIT)

### Run WAST Tests

```bash
./wasmoon test <file.wast>
```

Execute a WAST (WebAssembly Script Test) file. WAST files contain test assertions for WebAssembly modules.

Options:
- `--no-jit`: Run tests in interpreter-only mode

Example:
```bash
./wasmoon test spec/i32.wast
```

### Run a WASI Component Command

```bash
./wasmoon component command.component.wasm --run
```

The command must export the pinned `wasi:cli/run` interface from either
Preview 2 `0.2.11` or Preview 3 `0.3.0-rc-2025-09-16`. Components are
validated before instantiation.

Core functions use JIT compilation by default when their component call graph
can enter native code safely. Use `--no-jit` to force interpreter execution:

```bash
./wasmoon component command.component.wasm --run --no-jit
```

Filesystem and network authority are denied by default. Grant only the
capabilities the command requires:

```bash
./wasmoon component command.component.wasm --run \
  --arg input.txt \
  --env LANG=C \
  --dir /srv/data::/data \
  --network loopback
```

`--network` accepts `deny`, `loopback`, or `all`. Standard input, output, and
error are inherited by command execution.

### Run Component Model Tests

```bash
./wasmoon component-test component-tests.json
```

The component test harness also enables JIT execution by default. Pass
`--no-jit` to run the same script through the interpreter. The pinned upstream
suites expose the same switch:

```bash
python3 scripts/run_component_wast.py --suite stable-0.2
python3 scripts/run_component_wast.py --suite stable-0.2 --no-jit
```

### Explore Compilation

```bash
./wasmoon explore <file.wat> [--stage <stages>]
```

Explore the compilation pipeline stages for debugging and analysis.

Stages:
- `source`: Function source text
- `milkir`: MilkIR SSA before optimization (`ir` is retained as a CLI alias)
- `opt-milkir`: Optimized MilkIR (`opt-ir` is retained as a CLI alias)
- `machv`: Target-neutral semantic MachV
- `vcode`: Selected target VCode before register allocation
- `allocated-vcode`: Target VCode after allocation materialization
- `code-object`: Verified unlinked code object and metadata
- `mc`: Machine code (final assembly)

Example:
```bash
./wasmoon explore test.wat \
  --stage milkir machv vcode allocated-vcode code-object mc
```

### Disassemble

```bash
./wasmoon disasm <file.wasm>
```

Disassemble a binary WebAssembly file to text format.

## Examples

### Running a Simple Module

```wat
;; hello.wat
(module
  (func (export "add") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.add))
```

```bash
./wasmoon run hello.wat
```

### Running WAST Tests

```bash
# Run a single test file
./wasmoon test spec/i32.wast

# Run all tests
python3 scripts/run_all_wast.py

# Run without JIT (interpreter only)
./wasmoon test --no-jit spec/i32.wast
```

### Debugging JIT Output

```bash
# View IR for a function
./wasmoon explore mymodule.wat --stage milkir

# View generated machine code
./wasmoon explore mymodule.wat --stage mc

# View full pipeline
./wasmoon explore mymodule.wat \
  --stage milkir machv vcode allocated-vcode code-object mc
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 134 | Crash (use lldb to debug) |

## Debugging Crashes

If wasmoon crashes with an unusual exit code (e.g., 134):

```bash
lldb -- ./wasmoon test path/to/test.wast
(lldb) run
# After crash:
(lldb) bt    # Show stack trace
(lldb) frame select 0
(lldb) register read
```
