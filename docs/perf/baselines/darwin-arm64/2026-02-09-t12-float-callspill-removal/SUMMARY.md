# T12 Round 3: Remove Forced Float Spill Across C Calls

- Base reference: `docs/perf/baselines/darwin-arm64/2026-02-09-t12-regalloc-overlap-cache/SUMMARY.md`
- Branch: `milky/optimization-jit-closure`
- Wasmtime/Cranelift ref: `68a6afd4f`
- Scope: `/Users/zhengyu/Documents/projects/wasmoon/vcode/regalloc/backtrack.mbt`

## Cranelift Alignment

Before this change, Wasmoon force-spilled every float bundle crossing a C call. That was stricter than Cranelift/regalloc2 behavior and increased allocator pressure.

Reviewed references before implementation:

- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/cranelift/codegen/src/isa/aarch64/abi.rs`
- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/cranelift/codegen/src/machinst/abi.rs`
- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/cranelift/codegen/src/machinst/compile.rs`
- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/cranelift/codegen/src/isa/x64/abi.rs`

Decision: remove the Wasmoon-only forced-spill shortcut for float bundles and let normal conflict/clobber splitting logic decide. Keep vector cross-call conservative spill policy unchanged in this round.

## Validation Gates

- `moon info`
- `moon fmt`
- `moon test --target native` (1689/1689 passed)
- `./install.sh`
- `python3 scripts/run_all_wast.py --dir spec --rec` (258/258 interpreter, 258/258 jit)

## Compile Profile Delta (AEAD)

Single-run metrics with `WASMOON_PERF_METRICS=1`:

- `module_compile_us`: `1992871 -> 1963526` (`-1.47%`)
- `regalloc_us_total`: `1472746 -> 1456129` (`-1.13%`)
- `func_56 regalloc_us`: `1335974 -> 1320317` (`-1.17%`)

Spill shape in `func_56` stays unchanged:

- `spills`: `148`
- `reloads`: `676`
- `reg_moves`: `306`

## Runtime Parity (5-run medians)

From `scripts/check_wasmtime_parity.py`:

- AEAD wall: Wasmoon `2.7916s`, Wasmtime `0.7816s`, ratio `3.5717x`
- Benchmark wall: Wasmoon `0.2929s`, Wasmtime `0.2922s`, ratio `1.0026x`

Program output parity for AEAD (same metric used in `wasmoon-opt.12`):

- Wasmoon median output: `4001100000`
- Wasmtime median output: `3651545000`
- Ratio: `1.09573x` (within 10%)

Artifacts in this folder:

- `wasmoon_aead_outputs.txt`
- `wasmtime_aead_outputs.txt`
- `wasmtime-parity-summary.md`
- `wasmtime-parity-summary.json`
- `aead.metrics.json`
- `aead.stdout.txt`
