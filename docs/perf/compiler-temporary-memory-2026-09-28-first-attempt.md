> Superseded experiment; the completion claim was withdrawn. Its production
> changes were removed because overall benefit was not established. The commands
> below refer to the benchmark script at c57604bd. See the
> [replacement investigation](compiler-temporary-memory-2026-09-28.md).

# Compiler temporary storage: measured comparison, 2026-09-28

## Result

Artifact production no longer copies emitter output into an immutable code
object and then copies it back into a mutable artifact. The existing immutable
API retains its snapshot contract. Long-lived compilation sessions can explicitly
release retained allocator arrays without invalidating earlier results.

Ordinary CLI wall time changed by less than 1% in all four final workloads, and
peak RSS was essentially unchanged. This is a local reduction in copying and an
explicit memory-lifetime control, not evidence of a broad compiler speedup or a
large reduction in peak process memory.

## Implementation and ownership

Before: emitter arrays -> `code_object.build` defensive snapshot -> getter copies
-> `FunctionCode`. After: emitter arrays -> `CodeData::verify` -> trim excess
capacity -> `FunctionCode` referencing those fresh arrays. Trimming can itself
allocate and copy; this is not a zero-allocation compilation claim. The reusable
session does not retain those result arrays. Installation still validates the
artifact, and the immutable `UnlinkedCodeObject` APIs still copy, including nested
safepoint roots. Both AArch64 and x64 use this path.

`release_scratch()` clears and shrinks all 31 retained scalar arrays in a register
allocation session. The VCode adapter, both target sessions, and `NativeCompiler`
forward the operation. Call it between jobs when a long-lived compiler becomes
idle, not from an observer while a job is running or unconditionally after every
function. The CLI already scopes its compiler to a module, so retaining scratch
there was not a leak. No automatic shrink threshold was introduced.

A native white-box probe compiled a 4,096-virtual-register chain and then a
2-register chain through the same allocator. Retained payload was **409,760 ->
409,760 bytes**, then **0 bytes** after release. This sums array capacity times
native element size, excludes headers/allocator overhead, and does not assert
that the operating system immediately reclaims RSS. The permanent regression
checks positive retained capacity, zero capacity after release, idempotence,
reuse, and preservation of previously returned plans without hard-coding the
current capacity growth policy.

## Method

- Baseline: `6dcd997e14d1076057ef6f0c2d633b78f3e4af85`.
- Optimized: source changes accompanying this report, tracked as ISS-586.
- Apple M3 Max, macOS 26.7 arm64; Moon 0.1.20260920 (914d7da),
  moonc 0.10.14+7d59c7ec9, wasm-tools 1.254.0.
- Both binaries built with `./install.sh` using the same release toolchain.
- Eleven samples per binary and workload; AB/BA order alternated. Every sample
  uses a fresh process and empty artifact cache; cache reports must confirm
  `freshly_compiled=true` and `cache_hit=false`.
- No other validation or build jobs ran concurrently with the final measurements.
- Ordinary CLI wall time includes process startup, parse/compile, installation,
  execution, and cache writing. Peak RSS comes from macOS `/usr/bin/time -l`.
- A separate instrumented run records module compilation and artifact packaging.
  Detailed metrics allocate their own storage; do not compare its RSS directly
  with an ordinary run. Microsecond packaging totals include timer quantization.
- Every generated function is called, results depend on a parameter, and guest
  output is `42`. Instrumented runs check function count and equal emitted-code
  size across versions. This is a synthetic AArch64 host benchmark, not an x64
  performance result or an application corpus sweep.

Workloads use a repeated integer add/rotate/multiply step:

| Workload | Generated functions, excluding main |
| --- | --- |
| many-small | 1,500 functions with 4 steps each |
| one-medium | 1 function with 3,000 steps |
| one-large | 1 function with 30,000 steps |
| large-then-small | 1 function with 30,000 steps, then 1,000 with 4 steps |

## Ordinary CLI medians

| Workload | Before ms | After ms | Time change | Before peak MiB | After peak MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| many-small | 165.925 | 166.106 | +0.11% | 68.078 | 68.094 |
| one-medium | 30.356 | 30.296 | -0.20% | 24.703 | 24.656 |
| one-large | 356.802 | 357.889 | +0.30% | 166.984 | 166.969 |
| large-then-small | 429.484 | 425.553 | -0.92% | 199.906 | 199.781 |

## Detailed metrics medians (separate run)

| Workload | Before compile ms | After compile ms | Before packaging us | After packaging us |
| --- | ---: | ---: | ---: | ---: |
| many-small | 143.281 | 144.651 | 323 | 202 |
| one-medium | 23.853 | 23.514 | 2 | 1 |
| one-large | 332.414 | 313.401 | 8 | 1 |
| large-then-small | 397.762 | 391.486 | 218 | 132 |

Packaging fell about 37-39% in the workloads containing many small functions,
but accounts for only a fraction of a millisecond. The instrumented large-function
compile improvement did not recur in ordinary wall time, so it is not presented
as a reliable application speedup. Earlier exploratory runs included an approximately
1 ms medium-function slowdown and approximately 2% mixed-workload slowdown;
those observations also argue against claiming a broad performance gain.

No optimizer scratch pool or arena was added: these measurements do not establish
one as a worthwhile next optimization. Further work should measure phase-specific
allocation volume and object lifetimes in representative applications before
introducing more retained state. This experiment measures peak RSS, not total
allocated bytes.

## Reproduction and evidence

[Raw samples, medians, binary/input hashes, and toolchain](compiler-temporary-memory-2026-09-28-first-attempt.json)
are checked in. Build and save a baseline binary before changing sources, then
build and save the optimized binary. Use new output directories:

```sh
python3 scripts/benchmark_compiler_memory.py \
  --before /path/to/before/wasmoon --after /path/to/after/wasmoon \
  --output target/compiler-memory/plain --repetitions 11 --no-metrics
python3 scripts/benchmark_compiler_memory.py \
  --before /path/to/before/wasmoon --after /path/to/after/wasmoon \
  --output target/compiler-memory/detail --repetitions 11
```

The runner retains generated WAT/Wasm, stdout/stderr, cold-cache reports, and
per-function metrics. This run's local directories are
`target/compiler-memory/verified-plain` and `target/compiler-memory/verified-detail`.

## Correctness validation

- Warning-denied native check and 2,584/2,584 native tests.
- Core WAST: 258/258 files and 62,563 commands for each of interpreter and JIT.
- New tests cover immutable nested metadata isolation, invalid mutable code data,
  artifact independence across successful reuse, failure, and release on both
  targets, and allocator capacity release without damaging previous plans.
- Module-boundary audit and three benchmark-harness unit tests passed.
- ASan/UBSan harness: 61/61 tests, external event-loop lifecycle, resolver
  lifecycle checks, and instrumentation positive controls passed. The existing
  harness excludes MoonBit runtime objects and generated JIT machine code.
