# Wasmoon vs Wasmtime Parity

- Iterations: `5` (warmup `1`)

| Workload | Wasmoon median (s) | Wasmtime median (s) | Ratio | Threshold | Status |
|---|---:|---:|---:|---:|---|
| `examples/aead_aegis128l.wasm` | 2.7916 | 0.7816 | 3.5717x | 6.0000x | ok |
| `examples/benchmark.wasm` | 0.2929 | 0.2922 | 1.0026x | 1.5000x | ok |