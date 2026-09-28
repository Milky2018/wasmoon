# Compiler allocation investigation: replacement result, 2026-09-28

## Correction and scope

The [first attempt](compiler-temporary-memory-2026-09-28-first-attempt.md) did not
establish an overall improvement. Its completion claim is withdrawn. The new
`CodeData` path, generic result callbacks, and unused `release_scratch()` API
layers have been removed. The original immutable code-object path is restored.
The previous raw data remains available rather than being rewritten.

This investigation starts from production sources at
`6dcd997e14d1076057ef6f0c2d633b78f3e4af85`, before that attempt. It retains three
small production changes in `vcode/builder.mbt`, `regalloc/function_liverange.mbt`,
and `regalloc/liverange.mbt`. There is no new public compiler API, arena, global
cache, or manually invoked release step. All changes execute on the existing
AArch64 and x64 compilation paths.

## Diagnosis and fixes

Three hypotheses were considered: optimizer array rebuilding, duplicated
register-allocation data, and unnecessarily retained stage data. Actual allocation
stacks instead identified avoidable short-lived allocation and one quadratic
buffer-growth pattern. An AEGIS-128L compile-only baseline made 2,811,291 tracked
allocations requesting 105,423,979 bytes, with a 6,317,428-byte tracked live peak.

A bounded attribution by compiler frames in allocation stacks assigns about
20.6 MB to optimization, 37.4 MB to register allocation, 27.7 MB to frontend and
semantic lowering, 17.0 MB to target construction/emission, and 2.6 MB to other
or truncated stacks. These are stack-based categories, not exhaustive timed
stage intervals; shared helpers and the ten-frame depth limit constrain attribution.
The raw summary retains the rule's resulting totals and representative stacks.

1. **Call-clobber storage repeatedly grew to exactly the next batch size.**
   Both VCode builder paths called `push_iter`, whose current implementation
   reserves exactly `length + batch_length` when the iterator has a size hint.
   Repeated call batches therefore recopied the existing register array on each
   append. Appending each register with ordinary `push` retains geometric growth.
   A 256-batch regression fails on the original implementation and passes on both
   builder paths after the fix; it also checks every instruction's slice and
   every stored register. This changes cumulative copy cost from quadratic to
   amortized linear without changing instruction contents.
2. **Each liveness operand created three immutable `UsePosition` objects.**
   The constructor followed by `with_preference` and `with_tie` materialized two
   discarded intermediate records. The compiler now constructs the final record
   once with all fields. Existing public constructors remain unchanged. A
   regression checks timing, constraint, preference, and tie metadata together.
3. **Dense live-range lookup constructed a redundant outer `Option`.**
   `Array::get(...).bind(...)` wrapped a slot that was already optional. An explicit
   bounds check returns the existing slot directly. Negative IDs, sparse holes,
   out-of-range IDs, and register classes retain their original behavior.

The clobber-only ablation and the final combined experiment are both retained in
[the data](compiler-temporary-memory-2026-09-28.json). The final production diff
is small; diagnostics and reproducible measurements are separate from production.

## Uninstrumented complete compilation time

The executable fixture calls the production `commands.compile_module` API with
O2, from Wasm bytes through parsing, validation, optimization, lowering, allocation,
and complete artifact creation. It takes one timestamp before the call and one
after it. Artifact encoding/file output occurs afterward. No per-stage collector
or allocation tracer is enabled. The API bypasses the disk JIT cache.

Each workload has two independent rounds of 21 alternating AB/BA pairs, one
fresh process per sample, plus one filesystem warmup per variant. The second
round reverses workload order. No builds, tests, or diagnostic captures ran
concurrently with either round. All 420 measured compilations produce exactly the
same artifact bytes for a given input, including code, relocations, and metadata.
These are five real algorithm modules, not synthetic straight-line loops.

| Workload | Before ms | After ms | Paired change | Bootstrap 95% interval | Second-round paired change |
| --- | ---: | ---: | ---: | --- | ---: |
| aead_aegis128l | 56.619 | 55.374 | -2.11% | [-2.49%, -1.80%] | -2.33% |
| aead_aegis256 | 61.837 | 59.403 | -2.63% | [-3.11%, -2.10%] | -2.12% |
| pwhash_scrypt_ll | 49.336 | 47.890 | -2.69% | [-3.18%, -2.36%] | -3.18% |
| sign | 150.858 | 145.210 | -3.77% | [-4.40%, -3.34%] | -3.65% |
| generichash | 48.979 | 47.569 | -2.68% | [-3.05%, -2.38%] | -2.35% |

The interval resamples within-pair percentage changes using a fixed seed. It
summarizes these runs, not all machines or all Wasm workloads. Paired medians are
not ratios of independently computed time medians. The first round is shown in
full above; all samples from both rounds remain in the JSON. Complete process
wall-time medians also decreased in all five workloads in both rounds.

## Allocation measurements, collected separately

The diagnostic build substitutes only the generated MoonBit C and runtime.c
mimalloc entry points. It records requested bytes, allocation count, frees, live
requested bytes, and allocation stacks. Object headers are included; mimalloc
size-class overhead, native-stub allocations, mapped pages, and stack storage are
not. The large recorder tables are deliberately outside the counters. Its wall
time and RSS must not be treated as performance results.

| Workload | Before requested MB | After requested MB | Change | Before allocations | After allocations |
| --- | ---: | ---: | ---: | ---: | ---: |
| aead_aegis128l | 105.424 | 96.771 | -8.21% | 2,811,291 | 2,644,071 |
| aead_aegis256 | 110.396 | 101.310 | -8.23% | 2,941,399 | 2,766,014 |
| pwhash_scrypt_ll | 90.289 | 83.438 | -7.59% | 2,428,457 | 2,283,613 |
| sign | 328.109 | 250.670 | -23.60% | 7,188,219 | 6,680,411 |
| generichash | 88.640 | 81.437 | -8.13% | 2,366,905 | 2,224,177 |

MB above means 1,000,000 bytes. The recorder's independent 20-byte + 30-byte
positive control reports exactly 50 total, two allocations, 50 peak, and zero
live after freeing both. Stack totals reconcile with global totals. No unmatched
free was observed in any compiler capture. A second capture of every variant
reproduced all allocation counts and artifact hashes; total bytes can differ by
a few bytes due to formatting the diagnostic elapsed-time integer.

## Memory tradeoff

| Workload | Ordinary before peak RSS MiB | Ordinary after peak RSS MiB | Traced before live peak MiB | Traced after live peak MiB |
| --- | ---: | ---: | ---: | ---: |
| aead_aegis128l | 13.656 | 13.344 | 6.025 | 6.044 |
| aead_aegis256 | 14.297 | 13.766 | 6.074 | 6.093 |
| pwhash_scrypt_ll | 13.469 | 13.094 | 5.874 | 5.893 |
| sign | 24.016 | 23.609 | 14.175 | 14.207 |
| generichash | 13.891 | 13.516 | 6.059 | 6.079 |

Geometric growth deliberately retains spare capacity: the tracked live peak
increases by roughly 0.2-0.3%, while cumulative requested allocation falls
7.6-23.6%. Ordinary process peak RSS falls modestly. These are distinct metrics;
this is not a claim that every memory measure improves. At process teardown,
all diagnostic variants retain the same 12,556 tracked bytes; this observation
alone is not proof of leak freedom or of the exact release time of each stage.

## Reproduction

Host: Apple M3 Max, macOS 26.7 arm64; Moon 0.1.20260920 (914d7da),
moonc 0.10.14+7d59c7ec9. Build the same fixture at the baseline and candidate,
retaining each executable. To reproduce the baseline from this tree, restore
only the three production files listed above from `6dcd997e` in an isolated
checkout; keep the measurement fixture and scripts identical. Restore candidate
sources before building the second executable.

```sh
moon build modules/wasmoon/testsuite/compiler_memory --target native --release
python3 scripts/benchmark_compiler_memory.py \
  --before /path/to/compile-before --after /path/to/compile-after \
  --output target/compile-comparison --repetitions 21 \
  examples/algorithms/aead_aegis128l.wasm \
  examples/algorithms/aead_aegis256.wasm \
  examples/algorithms/pwhash_scrypt_ll.wasm \
  examples/algorithms/sign.wasm examples/algorithms/generichash.wasm
python3 scripts/profile_compiler_allocations.py \
  --output target/allocation-profile \
  examples/algorithms/aead_aegis128l.wasm \
  examples/algorithms/aead_aegis256.wasm \
  examples/algorithms/pwhash_scrypt_ll.wasm \
  examples/algorithms/sign.wasm examples/algorithms/generichash.wasm
```

The allocation tool currently requires macOS, `atos`, and the native mimalloc
backend. It compiles a copied runtime unit and a separate instrumented executable;
it does not edit installed runtime sources or generated C. The recorder assumes
serial compilation and is not a concurrent allocator profiler. The timing runner
supports macOS/Linux RSS units; only macOS arm64 was measured here.

Local complete captures are under `target/compiler-redo/{final-pairs,repeat-pairs,
allocation-before,allocation-after}`. The checked-in JSON contains raw timing
samples, input/binary/artifact hashes, allocation totals and repeat measurements,
bounded stack summaries, and the clobber-only ablation. Full symbolized stacks
are retained locally because they are hundreds of megabytes. Compiler output
identity and test results are separate from the performance claim.

## Validation and limits

- The clobber-growth regression was observed failing before the fix and passing
  afterward; original register order and instruction slices are checked.
- Native warning-denied check, generated interfaces, module-boundary audit, and
  all 2,583 native tests pass.
- Core WAST: both engines pass 258 files / 62,563 commands each using the final CLI.
- ASan/UBSan harness passes 61 tests and lifecycle/instrumentation controls; its
  existing exclusions still include MoonBit runtime objects and JIT machine code.
- No universal speedup, Windows/x64 performance result, or complete resolution
  of reusable compiler context issue ISS-451 is claimed. This fixes three measured
  allocation costs. Broader stage-storage reuse still requires separate evidence.
