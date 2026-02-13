# Round9 Baseline (i32 MAC fusion alignment)

- Host: darwin-arm64
- Wasmoon working branch: `milky/optimization-jit-closure`
- Wasmtime: `wasmtime 40.0.0 (68a6afd4f 2025-11-22)`
- Cranelift references:
  - `cranelift/codegen/src/isa/aarch64/lower.isle` (`iadd_imul_{right,left}`, `isub_imul`)
  - `cranelift/codegen/src/isa/aarch64/inst.isle` (`madd`/`msub` forms over `fits_in_64`)

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
  - wasmoon: `3445715000`
  - wasmtime: `3712025000`
  - delta: `-7.1731%`
- `benchmark.wasm` wall-clock:
  - wasmoon: `0.249124s`
  - wasmtime: `0.280073s`
  - delta: `-11.0502%`
- `keygen.wasm` output value:
  - wasmoon: `7965000`
  - wasmtime: `9049500`
  - delta: `-11.9881%`
- `sign2.wasm` output value:
  - wasmoon: `690305000`
  - wasmtime: `693030000`
  - delta: `-0.3931%`

Compared with Round8 (`-10.2685%` on `aead_aegis128l`), this round improved the aead delta by about `+3.10` percentage points toward parity.

Raw run logs are stored as JSON files in this directory.
