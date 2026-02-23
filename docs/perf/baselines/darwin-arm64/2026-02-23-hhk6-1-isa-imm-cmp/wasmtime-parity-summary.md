# Wasmoon vs Wasmtime Parity

- Iterations: `5` (warmup `1`)

| Workload | Wasmoon median (s) | Wasmtime median (s) | Ratio | Threshold | Status |
|---|---:|---:|---:|---:|---|
| `examples/algorithms/aead_aegis128l.wasm` | 5.5650 | 0.7584 | 7.3380x | 6.0000x | regressed |
| `examples/benchmark.wasm` | 0.2562 | 0.3150 | 0.8135x | 1.5000x | ok |

## Failures

- examples/algorithms/aead_aegis128l.wasm: ratio 7.3380x exceeds threshold 6.0000x