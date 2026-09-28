# Compiler allocation follow-ups, 2026-09-28

## Scope and decisions

Baseline: `999e9e3916b1b7796de3ac277be3f673dcdd65fd`. This is incremental
work after [the corrected allocation investigation](compiler-temporary-memory-2026-09-28.md),
not a comparison with its older, slower baseline.

Four candidates were built independently from this baseline. Each received two
rounds of 21 alternating AB/BA fresh-process pairs on five real Wasm modules;
the second round reversed workload order. The fixture times the complete public
`compile_module` path at O2, with allocation tracing and stage metrics disabled.
Encoding and writing the complete artifact happen outside the timed region.
No builds, tests, or allocation captures ran concurrently with timing rounds.

The [measurement data](compiler-allocation-followups-2026-09-28.json) preserves
all individual samples, binary/input/artifact hashes, confidence intervals, and
all four candidate patches, including the two not applied to production.
Intervals are fixed-seed bootstrap intervals of within-pair percentage changes;
a negative change means faster. These intervals describe these samples, not a
hardware-independent guarantee, and are not adjusted for multiple comparisons.

1. **Retain natural-order comparisons.** Private register-allocation lookups
   previously constructed an empty block-order array just to request numeric
   order. They now use private numeric comparison/containment methods sharing
   the same lexicographic comparison implementation. Custom block permutations
   retain the public API and their previous behavior. Signed extremes and
   inclusive range endpoints have a regression test. Both rounds favor this
   change in all five paired medians, although several individual intervals
   cross zero; `sign` shows an improvement in both rounds.
2. **Retain direct internal allocation snapshots.** VCode's allocation
   constructor now reads its own instruction operand slices and value types
   directly instead of creating checked public instruction/value/operand
   snapshots to discard most of their fields. It still constructs the owned
   `Value` handles stored by the allocation. Public accessors, foreign-handle
   rejection, snapshot shape, and ownership boundaries remain unchanged.
   `scrypt_ll`, `sign`, and `generichash` show improvements with intervals below
   zero in both rounds. The two AEGIS modules do not establish individual gains.
3. **Defer the queue return wrapper.** A private value-type result and explicit
   nonempty loop condition remove `Some((bundle, hint))`. First-round evidence
   was weak and all five second-round intervals cross zero. This does not prove
   there is no allocation or speed benefit; it is insufficient evidence to
   adopt a new unchecked-pop precondition in this pass. The production queue
   remains unchanged. The experiment passed the register-allocator tests and
   produced identical artifacts.
4. **Defer contiguous pointer dependencies.** A CSR-style dependency array
   replaces one growable array per value while preserving dependency insertion
   and worklist order. It requires two additional instruction/operand passes
   and offset/cursor arrays. Separate allocation captures show only 0.93–1.21%
   less cumulative requested memory and 1.17–1.32% fewer allocations, with
   exactly unchanged tracked live peaks on all five workloads. Timing evidence
   changes between rounds: only `generichash` has a below-zero interval in the
   first round, and its second round is essentially neutral. This tradeoff does
   not justify the added representation complexity yet. The production
   optimizer remains unchanged. Its 133 optimizer tests and artifact equality
   passed during the experiment.

No public API, package dependency, cache, pool, arena, or release protocol was
added. These are small changes to shared compiler code used by both targets.
Timing evidence is limited to Apple M3 Max / macOS 26.7 arm64, Moon 0.1.20260920
and moonc 0.10.14+7d59c7ec9; x64 speed is not inferred from these results.

## Individual experiments

| Candidate | Workload | First paired change (95% interval) | Second paired change (95% interval) |
| --- | --- | ---: | ---: |
| natural | aead_aegis128l | -0.42% [-0.63%, +0.13%] | -0.44% [-0.96%, +0.07%] |
| natural | aead_aegis256 | -0.59% [-0.79%, -0.32%] | -0.32% [-1.23%, +0.56%] |
| natural | pwhash_scrypt_ll | -0.86% [-1.92%, +0.30%] | -1.25% [-1.98%, -0.60%] |
| natural | sign | -1.57% [-2.20%, -0.71%] | -0.99% [-2.23%, -0.19%] |
| natural | generichash | -1.27% [-2.62%, -0.39%] | -0.44% [-0.83%, +0.20%] |
| queue | aead_aegis128l | -0.92% [-1.51%, -0.23%] | -0.56% [-1.23%, +0.30%] |
| queue | aead_aegis256 | -2.12% [-3.12%, +0.15%] | -0.55% [-1.13%, +0.51%] |
| queue | pwhash_scrypt_ll | -0.53% [-1.47%, -0.30%] | -0.67% [-1.48%, +0.22%] |
| queue | sign | -0.50% [-0.77%, +0.39%] | -0.70% [-1.46%, +0.10%] |
| queue | generichash | -0.68% [-1.44%, +0.77%] | -0.73% [-1.32%, +0.18%] |
| snapshot | aead_aegis128l | -0.41% [-2.14%, +0.18%] | +0.05% [-0.49%, +0.59%] |
| snapshot | aead_aegis256 | -1.38% [-1.45%, +0.21%] | -0.24% [-1.39%, +0.25%] |
| snapshot | pwhash_scrypt_ll | -1.01% [-1.54%, -0.81%] | -1.06% [-1.19%, -0.41%] |
| snapshot | sign | -0.70% [-1.64%, -0.29%] | -1.48% [-1.72%, -0.60%] |
| snapshot | generichash | -0.55% [-1.73%, -0.03%] | -1.16% [-1.44%, -0.62%] |
| deps | aead_aegis128l | -0.53% [-1.35%, +1.84%] | -0.70% [-1.50%, -0.17%] |
| deps | aead_aegis256 | +0.18% [-1.61%, +1.20%] | -1.26% [-1.71%, -0.30%] |
| deps | pwhash_scrypt_ll | -0.46% [-1.17%, +0.21%] | -0.35% [-1.76%, +0.15%] |
| deps | sign | -1.11% [-2.61%, +0.02%] | -0.84% [-1.61%, -0.50%] |
| deps | generichash | -2.01% [-3.53%, -0.74%] | -0.00% [-0.77%, +0.79%] |

## Combined allocation measurements

Allocation tracing runs separately from performance timing. The tracer counts
requested bytes (including MoonBit object headers), allocation calls, and live
requested bytes through generated MoonBit C and runtime mimalloc entry points.
Native-stub allocations, mapped pages, allocator size-class overhead, and stack
storage are excluded. Its recorder tables are outside the counters. Instrumented
execution time and RSS are not used as performance results.

The baseline tracer is the previous investigation's final production build,
reused here with new captures and the same runtime SHA. Diagnostic binary and
runtime hashes are in the JSON. Capture output paths have matching lengths.
The normal baseline binary SHA matches the previous report's final binary.
The 20+30-byte allocation control produced 50 cumulative/peak bytes, two calls,
and zero remaining bytes. All full captures had zero unknown frees, identical
artifacts, and 12,556 tracked bytes still live at exit in both variants. This is
not a new claim that all native or runtime allocations have been audited.

| Workload | Before requested MB | After requested MB | Byte change | Allocation count change | Before / after live peak bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| aead_aegis128l | 96.770 | 93.328 | -3.56% | -4.55% | 6,337,744 / 6,337,744 |
| aead_aegis256 | 101.310 | 97.682 | -3.58% | -4.58% | 6,389,004 / 6,389,004 |
| pwhash_scrypt_ll | 83.438 | 80.423 | -3.61% | -4.60% | 6,179,641 / 6,179,641 |
| sign | 250.670 | 240.427 | -4.09% | -5.31% | 14,897,619 / 14,897,619 |
| generichash | 81.437 | 78.366 | -3.77% | -4.84% | 6,374,006 / 6,374,006 |

For AEGIS-128L, stacks containing `segment_at` go from 51,260 allocations to
zero; stacks containing `instruction_operand_at` go from 46,800 allocations to
714. The latter accessor still serves other callers. These stack matches can
overlap and are not additive categories; inlining and the ten-frame trace limit
also affect attribution. They support the expected mechanism rather than
replacing whole-program totals.

The tracked live peak is unchanged on every workload. Ordinary uninstrumented
RSS does not show a reliable improvement either. This optimization reduces
allocation churn, not established peak-memory pressure.

## Combined complete compilation time

The retained pair received two 21-pair rounds. Because the first round had
intervals crossing zero on three workloads, a third, fixed 63-pair confirmation
round was scheduled after both original rounds. No samples or rounds were
excluded. The third round uses a different workload order. All 2,730 measured
compilations across the independent and combined experiments have identical
complete artifact bytes for a given input; warmup runs are additional.

| Workload | Round 1 paired change (95% interval) | Round 2 paired change (95% interval) | 63-pair confirmation (95% interval) |
| --- | ---: | ---: | ---: |
| aead_aegis128l | -1.46% [-2.27%, -0.45%] | -1.33% [-2.64%, -0.97%] | -1.29% [-1.71%, -0.90%] |
| aead_aegis256 | -0.33% [-2.07%, +0.20%] | -1.64% [-2.38%, -1.11%] | -0.66% [-1.22%, -0.48%] |
| pwhash_scrypt_ll | +0.01% [-1.81%, +1.02%] | -1.02% [-1.32%, -0.33%] | -1.00% [-1.95%, -0.69%] |
| sign | -0.85% [-2.10%, +0.39%] | -2.11% [-2.87%, -1.37%] | -1.76% [-1.99%, -1.38%] |
| generichash | -1.93% [-3.28%, -0.77%] | -1.79% [-2.48%, -1.21%] | -0.55% [-1.76%, +0.16%] |

The confirmation round supports small compile-time improvements on four
workloads (about 0.66–1.76%). `generichash`'s confirmation interval crosses zero,
despite favorable first and second rounds. Some earlier rounds are also noisy.
This is evidence of lower allocation churn and modest performance gains, not
uniform or guaranteed speedups. Independent time medians can disagree with
paired percentage medians when system conditions drift; the JSON retains both,
along with full process wall time and ordinary peak RSS for every sample.

## Validation and reproduction

- `moon info`, `moon fmt`, `moon check --target native --warn-list +73 --deny-warn`.
- `moon test --target native`: 2,584 passed.
- Rebuilt the release CLI from final sources; `python3 scripts/run_all_wast.py --rec`:
  interpreter and JIT each passed 258/258 files.
- `python3 scripts/run_sanitizers.py`: 61 tests passed; ASan/UBSan instrumentation
  checks, failure probes, resolver lifecycle, and event-loop fixture passed.
- `python3 scripts/audit_module_boundaries.py`: passed.
- `python3 -m unittest discover -s scripts/tests`: 174 tests, 54 skipped, no failures.
- Generated public interfaces remain unchanged.

Build `modules/wasmoon/testsuite/compiler_memory` with `--target native --release`
at the baseline and final revision, preserving both executables. Run
`scripts/benchmark_compiler_memory.py --before <baseline> --after <final>
--output <new-directory> --repetitions 21 <workloads>` (or 63 for confirmation).
The five inputs and their hashes/order are recorded in each JSON round. The
runner rejects artifact mismatches and starts a fresh process for each trial.
Build/test/profiling jobs must not overlap the timing run. Individual experiments
are reproducible by applying the recorded candidate patch to the baseline.

Run `scripts/profile_compiler_allocations.py --output <new-directory> <workloads>`
separately for allocation diagnostics. Do not use its time or RSS as speed or
memory-footprint evidence. Full local traces and per-sample files are under
`target/compiler-next`; the checked-in JSON keeps raw timing samples, aggregate
allocation measurements, representative stacks, and provenance hashes.
