# Examples

This directory contains example WebAssembly files for testing wasmoon.

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

# WASI function signature test
./wasmoon run examples/wasi_file_test.wat
```

### Validation Examples

```bash
# Test invalid rights validation (should return EINVAL)
./wasmoon run examples/wasi_invalid_rights.wat --dir .
```

### Benchmark

```bash
# CPU-intensive benchmark (~10 seconds)
./wasmoon run examples/benchmark.wat
```

## Example Descriptions

| File | Description |
|------|-------------|
| `add.wat` | Simple addition function, no WASI |
| `hello_wasi.wat` | Print "Hello, World!" using WASI fd_write |
| `args_wasi.wat` | Print command line arguments |
| `benchmark.wat` | CPU-intensive Fibonacci benchmark (~10 seconds) |
| `wasi_file_io.wat` | Full file I/O test: create, write, read, close |
| `wasi_file_test.wat` | Test WASI function signatures and error codes |
| `wasi_invalid_rights.wat` | Test that invalid rights are rejected |

## Generated Files

- `test_output.txt` - Created by `wasi_file_io.wat`, contains "Hello from WebAssembly!"
