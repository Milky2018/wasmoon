# Wasmoon vs Wasmtime Parity

- Iterations: `3` (warmup `1`)

| Workload | Wasmoon median (s) | Wasmtime median (s) | Ratio | Threshold | Status |
|---|---:|---:|---:|---:|---|
| `examples/algorithms/aead_aegis128l.wasm` | 6.5804 | 0.7819 | 8.4161x | 6.0000x | regressed |
| `examples/benchmark.wasm` | 0.2916 | 0.2933 | 0.9944x | 1.5000x | ok |

## Failures

- examples/algorithms/aead_aegis128l.wasm: ratio 8.4161x exceeds threshold 6.0000x