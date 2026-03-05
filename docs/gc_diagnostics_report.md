# GC Diagnostics Report

Date: 2026-03-04
Branch: `feat/gc-bugfinding-tooling`

## Scope

This report covers the GC hardening work requested for:

- differential execution matrix (`--no-jit` / `JIT` / stress lane / optional `wasmtime`)
- GC stress controls (collect nearly every allocation, tiny heap)
- heap verifier and write-barrier assertions
- allocation fault-injection
- directed GC fuzzing (`compare_jit_interp(...)`)
- sanitizer CI lane for `jit/jit_ffi/*.c`
- automatic reducer for failing repros

## What Was Implemented

### 1) Differential matrix and trap normalization

Updated `scripts/find_gc_bugs.py`:

- matrix lanes:
  - `interp` (`--no-jit`)
  - `jit`
  - `jit_stress_verify`
  - optional `wasmtime`
  - optional `jit_fault_inject`
- trap-signature extraction/normalization for cross-lane comparison
- GC stress lane env:
  - `WASMOON_GC_STRESS=1`
  - `WASMOON_GC_STRESS_EVERY=1`
  - `WASMOON_GC_VERIFY=1`
  - `WASMOON_GC_HEAP_CAPACITY=4096`

### 2) GC stress and tiny heap controls

- `runtime/store.mbt` now supports `WASMOON_GC_HEAP_CAPACITY` for C-heap initial bytes.
- `executor/context.mbt` now supports:
  - `WASMOON_GC_STRESS`
  - `WASMOON_GC_STRESS_EVERY`
  - collection after allocation sites with stack + frame-locals roots.

### 3) Heap verifier and barrier assertions

`jit/jit_ffi/gc_heap.c`:

- verifier entry (`gc_heap_verify`) and runtime hook (`WASMOON_GC_VERIFY`)
- consistency checks:
  - object table bounds/order/overlap
  - header size/alignment/kind validity
  - array payload/length bounds
  - free-list index validity
- write-barrier debug hook:
  - `gc_heap_write_barrier(...)`
  - `WASMOON_GC_ASSERT_BARRIER=1` asserts owner liveness/bounds
  - barrier-call counter exported as stats

### 4) Fault injection

`jit/jit_ffi/gc_heap.c`:

- `WASMOON_GC_FAIL_ALLOC_AT`
- `WASMOON_GC_FAIL_ALLOC_EVERY`

Also added test hook API:

- `wasmoon_gc_heap_debug_set_fail_alloc(...)`
- MoonBit wrapper `gc_debug_set_fail_alloc(...)` in `jit/c_heap.mbt`

### 5) GC-directed fuzz (compare JIT vs interpreter)

Added `testsuite/gc_fuzz_test.mbt`:

- deterministic pseudo-random case generation
- mixes struct/array/ref operations, cyclic references, and table/ref traffic
- checks parity with `compare_jit_interp(...)` across 64 generated seeds

### 6) Sanitizer CI lane

Updated `.github/workflows/check.yml` with a new `build-ubuntu-sanitizer` job:

- `ASan + UBSan` compile/link flags for native build
- builds `wasmoon` and runs `scripts/find_gc_bugs.py --dir spec/gc`

### 7) Automatic reducer

Added `scripts/reduce_wast.py`:

- command-template driven delta reduction (`{file}` placeholder)
- line-based ddmin for failing `.wast/.wat/.wasm` repros

## Validation Results

Commands run:

- `moon check --target native`
- `moon test --target native`
- `./install.sh`
- `python3 scripts/find_gc_bugs.py --dir spec/gc --timeout 30`

Observed:

- `moon check`: pass
- `moon test`: pass (`1786/1786`)
- GC differential (`spec/gc`):
  - interp: `17/17` pass
  - jit: `17/17` pass
  - stress: `17/17` pass
  - regressions: `0`
  - trap mismatches: `0`

## Findings: Is There a GC Bug Right Now?

For the current tested matrix (`spec/gc` + directed fuzz + stress lane), no JIT-vs-interpreter GC correctness divergence was observed.

## Known Limitations / Risk Notes

1. Current collector is non-generational.  
   - Barrier assertions validate barrier-call path and owner validity, but there is no old/young invariant yet.

2. Precise reference-kind verification is limited.  
   - Because values are encoded in `int64_t` and type maps are not embedded in verifier checks, verifier focuses on structural invariants rather than exact semantic reference typing.

3. Collection during arbitrary JIT execution points remains constrained.  
   - Stress collection is strongest in interpreter paths where roots are explicit (stack + locals).

4. Optional `wasmtime` lane may report non-pass on some `.wast` files due directive/diagnostic mismatch rather than Wasmoon regressions.  
   - This lane is auxiliary and should be interpreted with the raw tail diagnostics in JSON.
