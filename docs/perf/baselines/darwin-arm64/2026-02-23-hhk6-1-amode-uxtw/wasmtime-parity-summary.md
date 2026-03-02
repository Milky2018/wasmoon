# Wasmoon vs Wasmtime Parity

- Iterations: `5` (warmup `1`)

| Workload | Wasmoon median (s) | Wasmtime median (s) | Ratio | Threshold | Status |
|---|---:|---:|---:|---:|---|
| `examples/algorithms/aead_aegis128l.wasm` | 5.5766 | 0.7999 | 6.9716x | 6.0000x | regressed |
| `examples/benchmark.wasm` | 0.3062 | 0.3086 | 0.9922x | 1.5000x | ok |

## Failures

- examples/algorithms/aead_aegis128l.wasm: ratio 6.9716x exceeds threshold 6.0000x