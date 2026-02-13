# 2026-02-10 PUV4 Regalloc Priority Alignment

## Environment
- Host: darwin-arm64
- Project: wasmoon
- Runner: local interactive run

## Commands
- `./wasmoon run examples/aead_aegis128l.wasm` (5 runs)
- `wasmtime run examples/aead_aegis128l.wasm` (5 runs)
- `time ./wasmoon run examples/benchmark.wasm` (5 runs, real)
- `time wasmtime run examples/benchmark.wasm` (5 runs, real)

## Results
- AEAD median output time value:
  - wasmoon: 3686540000
  - wasmtime: 3625165000
  - ratio (wasmoon/wasmtime): 1.016930
- benchmark real-time median:
  - wasmoon: 0.24 s
  - wasmtime: 0.27 s
  - ratio (wasmoon/wasmtime): 0.888889

## Acceptance
- AEAD parity target (<= 1.05x): **PASS** (ratio=1.016930)
- benchmark no-regression target (<= 1.10x baseline ratio): **PASS**
