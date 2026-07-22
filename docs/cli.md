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
