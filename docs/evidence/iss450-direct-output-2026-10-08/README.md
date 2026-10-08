# ISS-450 direct allocation output

## Scope and result

Baseline: `7f5faf099721d2f6195371e2b3fa0da441797c24` (merged PR #525).
Candidate: the module files pinned by `source-hashes.json`, on
`milky/verify-iss450-acceptance`. Host: macOS ARM64, Moon 0.1.20260920.
The subsequent cross-platform acceptance below covers native x64 and ARM64.

The allocator now uses one statically dispatched `AllocationSink`. Production
writes homes, operands, spill slots, and resolved transfers directly into VCode;
there is no production `AllocationPlan` or final plan-to-VCode conversion loop.
Standalone allocator tests and clients use a plan sink through the same policy.
The only allocator-owned edit buffer contains unresolved parallel moves.
Strict verification records resolved generic edits; production does not.

VCode still constructs its own safepoint metadata and verifies output
completeness. Those operations are necessary output construction, not a generic
plan conversion. Incremental write validation preserves class, index, and slot
checks even when full dataflow verification is off.

Final VCode tables are now allocated earlier, so their lifetime overlaps more
allocator scratch. Operand ownership snapshots use integer ids instead of one
`Value` object per operand; instruction edit buckets allocate only when needed.
These reduce construction overhead but **do not eliminate the measured peak RSS
increase**. This change trades a small memory increase for a simpler output
boundary and modest compilation improvement.

## Complete-compilation measurements

`scripts/benchmark_compiler_memory.py` runs fresh processes and calls
`compile_module` directly, with artifact caching and detailed metrics disabled.
Before/after order alternates. There are 15 pairs per workload. Filesystem pages
are warmed once per binary; compiler state is fresh for every sample. All
successful comparisons verify exact artifact hashes. Compilation remains serial.
No Wasmtime comparison was run.

Final capture: `final-compile.json.gz`.

| Workload | Before median | After median | Paired median change (bootstrap 95% interval) | Peak RSS before / after |
| --- | ---: | ---: | ---: | ---: |
| AEGIS-128L | 59.376 ms | 57.682 ms | -2.28% [-3.07%, -1.40%] | 13,778,944 / 14,188,544 bytes |
| AEGIS-256 | 61.662 ms | 60.396 ms | -1.99% [-4.10%, +1.31%] | 14,106,624 / 14,696,448 bytes |
| sign2 | 138.368 ms | 133.629 ms | -3.17% [-5.24%, -1.58%] | 27,607,040 / 28,950,528 bytes |

Paired percentages are the median of per-pair changes, not the percentage change
between the two independent medians. AEGIS-256 is inconclusive. Memory increases
are approximately 0.39, 0.56, and 1.28 MiB respectively; do not report a memory win.

Reproduce with separately built baseline/candidate
`modules/wasmoon/testsuite/compiler_memory` release binaries:

```sh
python3 scripts/benchmark_compiler_memory.py \
  --before /path/to/before --after /path/to/after \
  --repetitions 15 --output /tmp/iss450-repeat \
  examples/algorithms/aead_aegis128l.wasm \
  examples/algorithms/aead_aegis256.wasm \
  examples/algorithms/sign2.wasm
```

## Attribution and negative results

Detailed captures use the same harness in an isolated source archive, with only
this extra line after artifact serialization:

```mbt
@fs.write_string_to_file(args[2] + ".metrics.json", @perf.export_json())
```

Run each binary in a fresh process with `WASMOON_PERF_METRICS=1` and
`WASMOON_PERF_METRICS_DETAIL=1`, alternating order, for AEGIS-128L. This separate
instrumented experiment is not used as the complete-compilation timing above.
`detailed-metrics.json.gz` retains all 42 raw reports from the final 21 pairs.
`final-phases-21.json.gz` includes binary/artifact hashes, raw samples, and
per-function code sizes, spill slots, spills, reloads, moves, and spill-to-spill
counts. Every allocation vector and artifact hash matches across those runs.

Final 21-pair complete regalloc: independent medians 17.975 / 17.748 ms;
paired median -3.07%, bootstrap 95% interval [-4.31%, -1.97%]. Phase medians:

| Phase | Before | After |
| --- | ---: | ---: |
| Input view | 18 us | 2 us |
| Output table creation | included in plan translation | 386 us |
| Operand assignment | 3,023 us | 2,815 us |
| Edit resolution, including direct final writes after the change | 243 us | 324 us |
| Plan translation / allocation finalization | 884 us | 299 us |

The finalization phase was renamed because it no longer translates a plan.
Output construction and transfer writes moved into their actual phases. Only
complete regalloc and complete compilation establish a net gain; subtracting
884 and 299 alone would overstate it. Phase medians do not necessarily sum to
the median total.

Retained exploratory captures:

- `exploratory-direct.json.gz`: the initial sink prototype, before compact
  operand snapshots and lazy edit buckets, two workloads and seven pairs.
- `exploratory-checked.json.gz`: complete output checks and compact operand
  snapshots, before lazy buckets. AEGIS-128L and sign2 were inconclusive.
- `initial-phases.json.gz`: seven pairs before lazy buckets; regalloc paired
  median -2.12% [-3.85%, -0.22%].
- `final-phases-7.json.gz`: first final-candidate phase sample was inconclusive:
  +0.50% [-5.49%, +2.59%]. The larger 21-pair repeat above improves precision,
  but does not erase this noisy result or guarantee a gain on every host.

One exploratory invocation additionally requested a nonexistent `regex_redux`
fixture and stopped after its two valid workloads. It was not used as the final
three-workload acceptance result. The final capture above completed successfully.

## Validation and remaining gate

- `moon info`, `moon fmt`, strict warning-denied native check: passed.
- `VCODE_REGALLOC_VALIDATION=1 moon test --target native`: 2,635 passed.
- `moon test --target native`: 2,635 passed.
- `python3 scripts/audit_module_boundaries.py`: passed.
- New regressions cover implicit GC operands, spilled root homes, repeated
  sessions, identical checked/unchecked output, and rejected incomplete/invalid
  output. Existing parallel-move and target-specific regressions remain active.
- Raw test output: `strict-native.txt`, `normal-native.txt`.
- Cross-platform CI passed; ISS-450 is closed. See the acceptance record below.

## Cross-platform acceptance

[PR #526](https://github.com/Milky2018/wasmoon/pull/526), implementation commit
`63cd76a75485e33659123428ff7eb19e415ec89c`, passed all five jobs in
[run 37719673512](https://github.com/Milky2018/wasmoon/actions/runs/37719673512):

| Gate | Result |
| --- | --- |
| Linux AMD64 | Passed |
| macOS ARM64 | Passed |
| Windows AMD64 (clang) | Passed |
| Windows AMD64 (MSVC) | Passed |
| Linux ASan and UBSan | Passed |

`ci-acceptance.json.gz` contains the exact run, head SHA, jobs, and step results.
Linux and macOS each passed 2,635 native tests, 110 Preview 3 runs using the
existing documented contract profile, and 692 misc cases plus 72 script-only
entries, with zero misc failures/timeouts. Both Windows toolchains passed their
native inventory and external corpus gates. The clang native step spent
1,103.5 seconds successfully building the test inventory before executing the
packages; it did not time out. No workflow or timeout changes were needed.

The performance measurements remain local ARM64 measurements; CI establishes
cross-platform correctness and packaging, not equivalent speedups on x64.
