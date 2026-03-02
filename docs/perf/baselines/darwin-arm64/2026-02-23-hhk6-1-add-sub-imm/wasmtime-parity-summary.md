# Wasmoon vs Wasmtime Parity

- Iterations: `5` (warmup `1`)

| Workload | Wasmoon median (s) | Wasmtime median (s) | Ratio | Threshold | Status |
|---|---:|---:|---:|---:|---|
| `examples/algorithms/aead_aegis128l.wasm` | 5.5972 | 0.7749 | 7.2232x | 6.0000x | regressed |
| `examples/benchmark.wasm` | 0.2625 | 0.3099 | 0.8470x | 1.5000x | ok |

## Failures

- examples/algorithms/aead_aegis128l.wasm: ratio 7.2232x exceeds threshold 6.0000x