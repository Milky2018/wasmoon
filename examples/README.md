# Examples

This directory contains runnable WebAssembly usage examples and benchmark workloads.
Owned regression suites live under [`tests/`](../tests/README.md).

## Running Examples

### Basic Examples

```bash
# Simple addition (no WASI required)
./wasmoon run examples/add.wat

# Hello world with WASI
./wasmoon run examples/hello_wasi.wat

# Command line arguments
./wasmoon run examples/args_wasi.wat -- arg1 arg2 arg3
```

### File I/O Examples

These examples require the `--dir` flag to grant filesystem access:

```bash
# Real file I/O test (creates test_output.txt)
./wasmoon run examples/wasi_file_io.wat --dir .
```

### Benchmark

```bash
# CPU-intensive benchmark (~10 seconds)
./wasmoon run examples/benchmark.wat
```

### Component Model Examples

```bash
# Run component-model example suite
python3 scripts/run_component_wast.py --dir examples/component-model --rec
```

### Algorithm Benchmarks

`examples/algorithms/` contains benchmark workloads imported from
https://github.com/jedisct1/webassembly-benchmarks under the ISC License. See
`examples/algorithms/UPSTREAM.md` and `examples/algorithms/LICENSE`.

## Example Descriptions

| File | Description |
|------|-------------|
| `add.wat` | Simple addition function, no WASI |
| `hello_wasi.wat` | Print "Hello, World!" using WASI fd_write |
| `args_wasi.wat` | Print command line arguments |
| `benchmark.wat` | CPU-intensive Fibonacci benchmark (~10 seconds) |
| `wasi_file_io.wat` | Full file I/O test: create, write, read, close |

## Generated Files

- `test_output.txt` - Created by `wasi_file_io.wat`, contains "Hello from WebAssembly!"
