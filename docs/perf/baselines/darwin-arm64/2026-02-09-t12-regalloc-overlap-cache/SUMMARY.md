# T12 Regalloc Bundle-Overlap Cache (Backtracking)

- Base reference: `docs/perf/baselines/darwin-arm64/2026-02-09-t9-runtime-init-path`
- Branch: `milky/optimization-jit-closure`
- Scope: `vcode/regalloc/backtrack.mbt` conflict-path optimization

## Change

- Added `BacktrackingAllocator::bundle_overlaps_cached(...)`.
- Reused cached bundle-overlap checks in:
  - `find_conflicts(...)`
  - `is_reg_free(...)`

This aligns our hot conflict-check path with regalloc2's intent: avoid repeated
pairwise overlap scans in the allocator inner loop.

## Validation Gates

- `moon info`
- `moon fmt`
- `moon test --target native` (1689/1689 passed)
- `./install.sh`
- `python3 scripts/run_all_wast.py --dir spec --rec` (258/258 interpreter, 258/258 jit)

## Perf (AEAD, compile profile)

- `module_compile_us`: `2124649 -> 1992871` (`-6.20%`)
- `regalloc_us_total`: `1599498 -> 1472746` (`-7.92%`)
- `hot func_56 regalloc_us`: `1474094 -> 1335974` (`-9.37%`)

No spill-count shape change in `func_56`:

- `spills`: `148 -> 148`
- `reloads`: `676 -> 676`
- `reg_moves`: `306 -> 306`

## Perf (AEAD output parity, 5-run medians)

Sample A:
- Wasmoon output median: `4013735000`
- Wasmtime output median: `3647720000`
- Ratio: `1.10034x`

Sample B:
- Wasmoon outputs: `3985010000, 3984595000, 3988150000, 3995555000, 3983145000`
- Wasmtime outputs: `3667645000, 3625840000, 3636225000, 3672745000, 3615920000`
- Ratio (median/median): `1.09592x`

`benchmark.wasm` remains non-regressed in wall-time checks (Wasmoon faster than Wasmtime in median runs on this host).
