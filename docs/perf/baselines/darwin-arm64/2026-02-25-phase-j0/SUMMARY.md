# Phase J0 Baseline

- Commit: `def0224`
- Branch: `milky/runtime-quality-improvements`
- Host: `Darwin arm64` (macOS `26.3`)
- Wasmtime: `wasmtime 40.0.0 (68a6afd4f 2025-11-22)`

## Commands

```bash
./install.sh
python3 scripts/check_wasmtime_parity.py \
  --workload examples/algorithms/aead_aegis128l.wasm \
  --workload examples/benchmark.wasm \
  --iterations 5 \
  --warmup 1 \
  --threshold examples/algorithms/aead_aegis128l.wasm=999 \
  --threshold examples/benchmark.wasm=999 \
  --out-dir docs/perf/baselines/darwin-arm64/2026-02-25-phase-j0
```

## Results (Median)

| Workload | Wasmoon (s) | Wasmtime (s) | Ratio |
|---|---:|---:|---:|
| `examples/algorithms/aead_aegis128l.wasm` | 5.5359 | 0.7822 | 7.0776x |
| `examples/benchmark.wasm` | 0.2908 | 0.2934 | 0.9914x |

Artifacts:

- `docs/perf/baselines/darwin-arm64/2026-02-25-phase-j0/wasmtime-parity-summary.json`
- `docs/perf/baselines/darwin-arm64/2026-02-25-phase-j0/wasmtime-parity-summary.md`
