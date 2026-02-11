# Round10 Baseline (large-function memory peepholes enabled)

- Host: darwin-arm64
- Wasmoon working branch: `milky/optimization-jit-closure`
- Wasmtime: `wasmtime 40.0.0 (68a6afd4f 2025-11-22)`
- Cranelift references:
  - `cranelift/codegen/src/machinst/compile.rs` (full lowering+regalloc pipeline does not gate memory code-quality passes on function size)
  - `cranelift/codegen/src/egraph/elaborate.rs` (large-function optimization still keeps code-quality rewrites active)

## Commands

```bash
./wasmoon run examples/algorithms/aead_aegis128l.wasm
wasmtime run examples/algorithms/aead_aegis128l.wasm
./wasmoon run examples/benchmark.wasm
wasmtime run examples/benchmark.wasm
./wasmoon run examples/algorithms/keygen.wasm
wasmtime run examples/algorithms/keygen.wasm
./wasmoon run examples/algorithms/sign2.wasm
wasmtime run examples/algorithms/sign2.wasm
```

Each command above was executed 5 times; medians are reported.

## Medians

- `aead_aegis128l` output value:
  - wasmoon: `3414550000`
  - wasmtime: `3707425000`
  - delta: `-7.8997%`
- `benchmark.wasm` wall-clock:
  - wasmoon: `0.251318s`
  - wasmtime: `0.283415s`
  - delta: `-11.3249%`
- `keygen.wasm` output value:
  - wasmoon: `7430000`
  - wasmtime: `8585000`
  - delta: `-13.4537%`
- `sign2.wasm` output value:
  - wasmoon: `693405000`
  - wasmtime: `692330000`
  - delta: `0.1553%`

Raw run logs are stored as JSON files in this directory.