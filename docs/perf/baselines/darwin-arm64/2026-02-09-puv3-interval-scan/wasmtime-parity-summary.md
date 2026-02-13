# Wasmoon vs Wasmtime Parity

- Iterations: `5` (warmup `1`)

| Workload | Wasmoon median (s) | Wasmtime median (s) | Ratio | Threshold | Status |
|---|---:|---:|---:|---:|---|
| `examples/aead_aegis128l.wasm` | 1.6285 | 0.7884 | 2.0656x | 6.0000x | ok |
| `examples/benchmark.wasm` | 0.2621 | 0.3209 | 0.8167x | 1.5000x | ok |