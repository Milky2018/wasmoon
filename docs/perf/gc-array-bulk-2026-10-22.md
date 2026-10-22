# Native GC array bulk operations

Date: 2026-10-22. Baseline: `2f6268bf3774332f9b528e275ad8c9a21bea24cd`.

## Change and invariants

The compact-layout migration replaced bulk copies with generic element get/set
calls. Each call repeated object, bounds and layout lookup; with
`WASMOON_GC_VERIFY=1`, each element also triggered a heap verification.

Bulk helpers now validate the whole range and resolve immutable element layouts
once. Compatible widths and reference encodings use `memmove`. Reference
copies scan the original source through the existing per-reference barrier
before moving, including overlapping copies. Different layouts retain a
zero-extending/truncating conversion loop. Fill selects `memset` for repeated
byte patterns, otherwise a constant-width store loop (2/4/8/16 bytes).
Nonempty operations verify the heap once, after all writes.

The existing barriers validate/count references without allocating, collecting
or invoking host callbacks. That contract permits retaining raw payload addresses
through each operation. No barrier protocol, root protection, public API or JIT
lowering was removed or changed. Public bridge range checks now use subtraction
to reject overflowing ranges before any write; the original accepted-range
regression failed before this repair.

An exploratory C microbenchmark compared direct reference stores plus barriers
against barrier scanning plus memmove. The latter was faster in the initial
long-array samples; warmed follow-up samples were close. No architecture-specific
length threshold was inferred from these samples.

## Fixed-Wasm CLI comparison

The [local receipt](gc-array-bulk-2026-10-22.json) preserves all three samples,
source hashes, result checks and limits. Sources/builds/caches were isolated in
auto-cleaned OS temporary directories. The baseline copied current module
sources and restored both functional files to the baseline revision; the repaired
build differed only in those two functional files. The after-source tree is
explicitly dirty, not clean CI evidence.

Each module creates a source and destination array of the stated type and length.
The source contains 42; V128 contains lanes 1,2,3,42; reference elements point to
a struct containing 42. A loop performs the full-range copy/fill and adds the
destination's final element (or lane/field) to an i32 checksum. Short arrays run
500000 iterations; long arrays run 128. Every result must equal iterations * 42.
The same compiled Wasm file runs in all engines. All 180 executions passed.

Commands per sample:

```sh
WASMOON_JIT_CACHE_DIR=<fresh-cache> <isolated-wasmoon> run --invoke run --arg <iterations> <fixture.wasm>
wasmtime run -C parallel-compilation=n -C cache=n --invoke run <fixture.wasm> <iterations>
```

Platform: macOS ARM64. Wasmtime 49.0.1 (46c23a87d); wasm-tools 1.254.0.
Verification flags were absent from timed processes. Table entries are median
wall milliseconds across three independent processes, including startup,
compilation, allocation and execution. These are end-to-end measurements, not
steady-state bandwidth or general engine parity. Sampling was sequential and
short post-fix durations have substantial startup/compiler sensitivity.

| Type-length-operation | Before ms | After ms | Wasmtime ms | Before / after |
| --- | ---: | ---: | ---: | ---: |
| i8-8-copy | 46.16 | 16.27 | 7.61 | 2.84 |
| i8-8-fill | 44.30 | 16.24 | 8.65 | 2.73 |
| i8-65536-copy | 66.05 | 4.69 | 7.17 | 14.09 |
| i8-65536-fill | 47.44 | 4.78 | 7.60 | 9.93 |
| i32-8-copy | 58.07 | 16.35 | 7.74 | 3.55 |
| i32-8-fill | 40.85 | 18.75 | 8.59 | 2.18 |
| i32-65536-copy | 96.98 | 4.62 | 7.25 | 20.99 |
| i32-65536-fill | 55.96 | 6.53 | 9.14 | 8.57 |
| i64-8-copy | 48.31 | 13.34 | 7.57 | 3.62 |
| i64-8-fill | 35.00 | 16.61 | 8.78 | 2.11 |
| i64-65536-copy | 75.38 | 5.61 | 7.54 | 13.44 |
| i64-65536-fill | 45.05 | 6.56 | 8.83 | 6.87 |
| v128-8-copy | 57.48 | 14.15 | 7.93 | 4.06 |
| v128-8-fill | 39.32 | 19.68 | 8.43 | 2.00 |
| v128-65536-copy | 89.93 | 6.36 | 9.35 | 14.15 |
| v128-65536-fill | 55.06 | 6.82 | 10.09 | 8.08 |
| ref-8-copy | 56.53 | 24.28 | 9.08 | 2.33 |
| ref-8-fill | 45.95 | 28.08 | 9.11 | 1.64 |
| ref-65536-copy | 82.83 | 20.75 | 10.09 | 3.99 |
| ref-65536-fill | 53.09 | 17.55 | 9.98 | 3.02 |

## Validation

- Native 2957/2957 with regalloc validation, heap verification and barrier assertions.
- Wasm 1390/1390; strict checks on both targets, info/fmt and module boundaries.
- All 44 native C stubs compile with warnings denied; generated MSVC bridge check passes.
- Fresh isolated macOS ASan/UBSan 266/266, both ASan positive controls detected.
  LSan is unavailable locally; this is not Windows/x64 or Linux CI acceptance.
- Regressions cover all widths, nonzero V128, zero fill, typed/legacy layout
  combinations, both overlap directions, reference barriers/GC survival,
  whole-range rejection including integer overflow, and production
  interpreter/JIT agreement at optimization levels 0 and 2.
