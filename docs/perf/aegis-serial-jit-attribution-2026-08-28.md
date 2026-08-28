# AEGIS-128L Serial JIT Attribution (2026-08-28)

## Scope

- Wasmoon revision: `62c4f6f55e8f25f7ba4c9b5a9f56ead3b09a9f0e`
- Host: Apple M3 Max, arm64, macOS 26.5.2 (25F84)
- Workload: `examples/algorithms/aead_aegis128l.wasm`
- Metrics schema: 5
- Compilation model: serial, cold JIT cache, one process per capture
- Samples: seven compact and seven detailed captures, with their order
  alternating on each pair

Each capture used a distinct `WASMOON_JIT_CACHE_DIR`. Detailed captures also
set `WASMOON_PERF_METRICS_DETAIL=1`. The workload was the only corpus entry
executed.

## Top-level samples

All values are microseconds. The stage columns come from the detailed capture
on that row.

| Run | Detailed module | Compact module | Optimize | Semantic | Target | Regalloc | Frame | Emit |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 143,310 | 133,121 | 31,495 | 19,318 | 20,066 | 54,803 | 3,405 | 3,796 |
| 2 | 136,467 | 145,325 | 29,194 | 17,715 | 18,943 | 55,009 | 3,384 | 3,754 |
| 3 | 134,999 | 133,404 | 29,218 | 17,717 | 18,693 | 53,664 | 3,429 | 3,745 |
| 4 | 138,165 | 133,793 | 30,172 | 18,333 | 19,168 | 54,461 | 3,396 | 3,844 |
| 5 | 133,689 | 135,690 | 28,960 | 17,608 | 18,887 | 52,829 | 3,426 | 3,629 |
| 6 | 135,430 | 133,917 | 29,203 | 17,840 | 18,715 | 53,835 | 3,446 | 3,778 |
| 7 | 134,206 | 139,413 | 29,109 | 17,652 | 18,833 | 53,142 | 3,377 | 3,671 |
| Median | 135,430 | 133,917 | 29,203 | 17,717 | 18,887 | 53,835 | 3,405 | 3,754 |

Detailed collection adds a median 1,513 us, or 1.13 percent, over compact
collection. Every capture contains 63 functions. The complete code-size vector
is identical across all 14 captures, totals 59,428 bytes, has SHA-256
`2b421768c13e7cc1e7b1d662f49f5d616f0b017d5581676a1955afd4dc5e0b7a`,
and records 16,036 bytes for function 56.

## Detailed median attribution

Component medians are calculated independently, so their displayed medians do
not need to add arithmetically. Within every individual JSON report, the
module, function, semantic, target, and register-allocation parent totals all
reconcile with zero microseconds of unreported remainder.

| Parent | Subphase | Median us |
| --- | --- | ---: |
| Function | Frontend translation | 2,118 |
| Function | Function orchestration | 4,644 |
| Semantic lowering | Input validation | 3,558 |
| Semantic lowering | Semantic MachV construction | 5,402 |
| Semantic lowering | Cleanup input verification | 3,154 |
| Semantic lowering | Alias collection | 119 |
| Semantic lowering | Alias rewrite | 1,944 |
| Semantic lowering | Dead-instruction removal | 342 |
| Semantic lowering | Cleanup output verification | 2,999 |
| Semantic lowering | Observer orchestration | 248 |
| Target lowering | Runtime ABI elaboration | 82 |
| Target lowering | Target context | 643 |
| Target lowering | Analysis | 5,529 |
| Target lowering | Target VCode construction | 12,506 |
| Target lowering | Observer orchestration | 145 |
| Register allocation | Function view construction | 1,918 |
| Register allocation | Live ranges | 5,719 |
| Register allocation | Segment construction | 2,432 |
| Register allocation | Bundle formation | 3,257 |
| Register allocation | Bundle allocation | 25,780 |
| Register allocation | Home assignment | 2,113 |
| Register allocation | Operand assignment | 7,552 |
| Register allocation | Edge transfers | 75 |
| Register allocation | Edit resolution | 316 |
| Register allocation | Plan translation | 4,158 |
| Register allocation | Observer orchestration | 449 |
| Module | Preparation | 234 |
| Module | Orchestration | 1,481 |

## Conclusions

The remaining serial cost is not one hidden linker or embedding step. It is
concentrated in three compiler structures:

1. Semantic MachV is fully materialized and then verified twice during
   mandatory cleanup. The two verifier passes alone have a combined median of
   6,153 us; semantic construction adds 5,402 us.
2. The target repeats whole-function analysis and then materializes target
   VCode. Analysis costs 5,529 us and construction costs 12,506 us. This is the
   primary evidence for replacing snapshot traversal and reducing the number
   of complete intermediate representations.
3. Register allocation remains dominated by bundle allocation at 25,780 us,
   followed by operand assignment, live-range construction, and plan
   translation. `VCodeFunctionView` construction is measurable but only
   1,918 us, so removing that allocation alone cannot close the gap.

For context only, the preceding same-host investigation recorded Wasmtime
40.0.0 with cache and parallel compilation disabled at a 36.757 ms median
command-level compile time. Wasmtime was not invoked by these captures and is
not a Wasmoon test or CI dependency.
