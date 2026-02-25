# Wasmoon vs Wasmtime Parity

- Iterations: `5` (warmup `1`)

| Workload | Wasmoon median (s) | Wasmtime median (s) | Ratio | Threshold | Status |
|---|---:|---:|---:|---:|---|
| `examples/algorithms/aead_aegis128l.wasm` | 5.5359 | 0.7822 | 7.0776x | 999.0000x | ok |
| `examples/benchmark.wasm` | 0.2908 | 0.2934 | 0.9914x | 999.0000x | ok |