# Register-Allocation Cutover Status

This document records dated engineering evidence for the production
register-allocation path. It is not a stable performance promise.

## Production state

As of 2026-07-20, both AArch64 and x64 production JIT paths use the same direct
allocation seam:

```text
Semantic MachV
  -> verified target-owned VCode
  -> read-only regalloc.FunctionView
  -> regalloc.allocate_function(Backtracking)
  -> AllocationPlan materialization
  -> independent VCode allocation verification
  -> frame planning and target emission
```

The adapter does not copy VCode into a second instruction or CFG graph.
Production compilation does not fall back to `SinglePass`. The aggregate target
pipeline verifies selected VCode before allocation; after materialization it
uses the independent VCode allocation verifier instead of rebuilding the same
whole-function analysis in the generic plan verifier.

The current AArch64 host validation passes:

- 2,280/2,280 native tests;
- 258/258 interpreter WAST files and 62,563/62,563 assertions;
- 258/258 JIT WAST files and 62,563/62,563 assertions.

## AArch64 paired evidence

The latest comparison used 21 paired runs on an arm64 macOS host. The candidate
working tree was based on `15921254dd2b9b955ee9aaef17cc510fcd140bde`; the fixed
legacy baseline was `af3fa2d99598554baab7614e0b08584ab5f8d9da`.

| Metric | Point ratio | Upper 95% ratio | Result |
| --- | ---: | ---: | --- |
| Corpus compile time | 0.936100x | 0.943234x | Pass |
| Corpus runtime | 0.977739x | 1.118256x | Inconclusive; strict limit is 1.03x |
| Total emitted bytes | 0.927594x | — | Pass: 37,152 versus 40,052 bytes |
| `large_cfg.wast` compile time | 1.029926x | 1.042708x | Pass |
| `large_cfg.wast` emitted bytes | 0.999164x | — | Pass: 14,340 versus 14,352 bytes |
| `matmul.wat` compile time | 1.045751x | 1.070426x | Pass |
| `matmul.wat` emitted bytes | 1.036232x | — | Pass: 572 versus 552 bytes |

A 2026-07-21 two-pair deterministic code-size confirmation at
`/private/tmp/machv-cutover-20260721-code-size-final/perf-report.json`
records 36,200 candidate bytes versus 40,052 legacy bytes (0.903825x).
`ref.wast` is 4 versus 12 bytes, `register_pressure.wast` is 1,676 versus
1,640 bytes (1.021951x), and every workload is within the 1.05 size limit.
The short run is not used to replace the 21-pair timing confidence evidence.

This replaces the earlier pathological result in which `large_cfg.wast` took
roughly 13–18 seconds and approached 300x legacy compile time. The responsible
costs were cumulative rather than one allocator choice:

- repeated whole-function use/def and verification analysis;
- dense allocation-verifier state;
- uncached VCode view conversions and successor queries;
- linear conflict and fixed-constraint searches;
- redundant ABI entry moves and edge-copy cycles;
- missed fallthrough, immediate, and compare-branch target patterns.

The fixed large-CFG scalability defect is closed in
[ISS-211](../../../issues/ISS-211.md).

## Remaining failures

The formal decision is still `fail`; aggregate improvement does not waive the
strict per-workload gates:

- Runtime: `gcd.wat` and `matmul.wat` are statistically inconclusive, while
  `fnv1a.wat` measures 1.085316x. `matmul.wat` has a favorable 0.826709x point
  estimate but unusually high variance, so the confidence gate correctly does
  not accept that sample.
- Compile time: `float_exprs.wast`, `ref.wast`, and
  `simd_f32x4_arith.wast` exceed their per-workload limits.
- Code size has no remaining per-workload failure; ISS-213 is closed.

The material `matmul` delta was an instruction-selection problem, not the
former allocator scalability problem. AArch64 target-owned selection now
combines multiply-add, scaled/register-offset memory addressing, power-of-two
arithmetic, and branch-comparison immediates without adding target operations
to semantic MachV. `matmul.wat` is now inside the per-workload code-size limit.
Compile-time follow-up is tracked by
[ISS-212](../../../issues/ISS-212.md), the completed code-size and
target-selection work by [ISS-213](../../../issues/ISS-213.md), and complete dual-target acceptance by
[ISS-221](../../../issues/ISS-221.md).

## Reproduction

Build the candidate, then run the paired comparison against the pinned legacy
binary:

```bash
./install.sh
python3 scripts/run_machv_cutover_perf.py \
  --out-dir /tmp/wasmoon-regalloc-paired \
  --pairs 9 \
  --expanded-pairs 21 \
  --candidate-binary ./wasmoon \
  --legacy-binary /tmp/wasmoon-fixed-legacy/wasmoon \
  --legacy-repo /tmp/wasmoon-fixed-legacy
```

The machine-readable report used above is `perf-report.json` in the selected
output directory. Correctness success, point estimates, and confidence-bound
acceptance are deliberately reported separately.
