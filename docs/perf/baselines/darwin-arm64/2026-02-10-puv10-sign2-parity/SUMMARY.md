# 2026-02-10 PUV.10 Sign2 parity

- Branch: milky/optimization-jit-closure
- Commit baseline: 266fce6
- Command: ./wasmoon run examples/sign2.wasm
- Command: wasmtime run examples/sign2.wasm

## sign2 output (5 runs)
- Wasmoon median: 680170000
- Wasmtime median: 670085000
- Ratio (wasmoon/wasmtime): 1.0151
- Delta vs wasmtime: 1.51%

## benchmark.wasm wall-time (5 runs)
- Wasmoon median real: 0.22s
- Wasmtime median real: 0.25s
- Ratio (wasmoon/wasmtime): 0.8800

## Notes
- This run includes regalloc cache-policy change: disable mem0_desc dedicated cache register reservation in function-level policy.
- Full gates run in this workspace:
  - moon test --target native
  - ./install.sh && python3 scripts/run_all_wast.py --dir spec --rec
