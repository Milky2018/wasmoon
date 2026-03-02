# Wasmoon vs Wasmtime Parity

- Iterations: `5` (warmup `1`)

| Workload | Wasmoon median (s) | Wasmtime median (s) | Ratio | Threshold | Status |
|---|---:|---:|---:|---:|---|
| `examples/algorithms/aead_aegis128l.wasm` | 5.5691 | 0.7747 | 7.1890x | 6.0000x | regressed |
| `examples/benchmark.wasm` | 0.2878 | 0.2934 | 0.9811x | 1.5000x | ok |

## Failures

- examples/algorithms/aead_aegis128l.wasm: ratio 7.1890x exceeds threshold 6.0000x