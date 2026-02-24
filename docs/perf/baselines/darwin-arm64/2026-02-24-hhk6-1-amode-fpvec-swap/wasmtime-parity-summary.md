# Wasmoon vs Wasmtime Parity

- Iterations: `3` (warmup `1`)

| Workload | Wasmoon median (s) | Wasmtime median (s) | Ratio | Threshold | Status |
|---|---:|---:|---:|---:|---|
| `examples/algorithms/aead_aegis128l.wasm` | 5.5514 | 0.7779 | 7.1364x | 6.0000x | regressed |
| `examples/benchmark.wasm` | 0.2928 | 0.2950 | 0.9925x | 1.5000x | ok |

## Failures

- examples/algorithms/aead_aegis128l.wasm: ratio 7.1364x exceeds threshold 6.0000x