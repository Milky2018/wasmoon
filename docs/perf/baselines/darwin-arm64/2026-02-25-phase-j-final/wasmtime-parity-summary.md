# Wasmoon vs Wasmtime Parity

- Iterations: `3` (warmup `1`)

| Workload | Wasmoon median (s) | Wasmtime median (s) | Ratio | Threshold | Status |
|---|---:|---:|---:|---:|---|
| `examples/algorithms/aead_aegis128l.wasm` | 5.4296 | 0.7820 | 6.9429x | 1.1000x | regressed |
| `examples/benchmark.wasm` | 0.2918 | 0.2922 | 0.9986x | 1.1000x | ok |

## Failures

- examples/algorithms/aead_aegis128l.wasm: ratio 6.9429x exceeds threshold 1.1000x