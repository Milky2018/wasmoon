# T3 Regalloc Merge Incremental Cache - Perf Snapshot

## Revision Context
- Wasmoon base commit: `e45fec3` (with uncommitted T3 patch in `vcode/regalloc/backtrack.mbt`)
- Wasmtime/Cranelift: `68a6afd4f`

## Gate Status
- `moon info`: pass
- `moon fmt`: pass
- `moon test --target native`: pass (`1688/1688`)
- `./install.sh`: pass
- `python3 scripts/run_all_wast.py --dir spec --rec`: pass (`258/258` interp, `258/258` jit)

## 5-run medians
- AEAD runtime:
  - Wasmoon: `3.28s`
  - Wasmtime: `0.87s`
  - Ratio: `3.77x`
- Benchmark runtime:
  - Wasmoon: `0.37s`
  - Wasmtime: `0.40s`
  - Ratio: `0.93x`

## AEAD compile profile delta vs locked baseline
Baseline ref: `docs/perf/baselines/darwin-arm64/2026-02-09-main-e45fec3/BASELINE.md`

- `module_compile_us`: `2437757` -> `2347776` (`-3.69%`)
- `regalloc_us_total`: `1693016` -> `1614310` (`-4.65%`)
- `optimize_us_total`: `398329` -> `391229` (`-1.78%`)
- `emit_us_total`: `26739` -> `25754` (`-3.68%`)

Hot function (`func_56`) regalloc:
- `1554002` -> `1488177` (`-4.24%`)
