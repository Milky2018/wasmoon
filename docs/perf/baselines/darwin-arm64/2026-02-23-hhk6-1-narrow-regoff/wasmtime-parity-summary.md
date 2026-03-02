# Wasmoon vs Wasmtime Parity

- Iterations: `5` (warmup `1`)

| Workload | Wasmoon median (s) | Wasmtime median (s) | Ratio | Threshold | Status |
|---|---:|---:|---:|---:|---|
| `examples/algorithms/aead_aegis128l.wasm` | 5.5323 | 0.7840 | 7.0561x | 6.0000x | regressed |
| `examples/benchmark.wasm` | 0.3001 | 0.3083 | 0.9734x | 1.5000x | ok |

## Failures

- examples/algorithms/aead_aegis128l.wasm: ratio 7.0561x exceeds threshold 6.0000x