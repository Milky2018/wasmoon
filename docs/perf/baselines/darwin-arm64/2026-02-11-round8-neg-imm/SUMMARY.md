# Round8 Baseline (neg-immediate lowering alignment)

- Host: darwin-arm64
- Wasmoon base commit before Round8: `7649100937514d705ffd82827643566df37aa1be`
- Wasmtime: `wasmtime 40.0.0 (68a6afd4f 2025-11-22)`

## Commands

```bash
./wasmoon run examples/algorithms/aead_aegis128l.wasm
wasmtime run examples/algorithms/aead_aegis128l.wasm
./wasmoon run examples/benchmark.wasm
wasmtime run examples/benchmark.wasm
```

Each command above was executed 5 times, medians were recorded.

## Medians

- `aead_aegis128l` output value:
  - wasmoon: `3318935000`
  - wasmtime: `3698740000`
  - delta: `-10.2685%`
- `benchmark.wasm` wall-clock:
  - wasmoon: `0.251044s`
  - wasmtime: `0.282578s`
  - delta: `-11.1595%`

Raw run logs are stored as JSON files in this directory.
