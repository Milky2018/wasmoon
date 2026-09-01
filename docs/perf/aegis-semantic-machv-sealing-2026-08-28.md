# AEGIS-128L Semantic MachV Sealing (2026-08-28)

## Method

- Baseline attribution: `62c4f6f5`
- Workload: `examples/algorithms/aead_aegis128l.wasm`
- Host: Apple M3 Max, arm64, macOS 26.5.2 (25F84)
- Seven detailed, serial, cache-isolated final captures

Every process used a distinct `WASMOON_JIT_CACHE_DIR` and enabled schema-5
detailed metrics. No other corpus workload was run.

## Results

All values are microseconds.

| Run | Module compile | Semantic total | Construction | Input seal | Output seal | Code size |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 127,269 | 13,574 | 5,770 | 992 | 5 | 59,428 |
| 2 | 120,755 | 12,653 | 5,458 | 976 | 7 | 59,428 |
| 3 | 121,546 | 12,564 | 5,447 | 973 | 6 | 59,428 |
| 4 | 121,240 | 12,599 | 5,459 | 959 | 10 | 59,428 |
| 5 | 121,722 | 12,789 | 5,571 | 984 | 7 | 59,428 |
| 6 | 121,007 | 12,603 | 5,484 | 971 | 9 | 59,428 |
| 7 | 120,236 | 12,497 | 5,452 | 990 | 7 | 59,428 |
| Median | 121,240 | 12,603 | 5,459 | 976 | 7 | 59,428 |

The old cleanup input and output verifier medians were 3,154 us and 2,999 us,
or 6,153 us combined. Checked construction now rejects local ownership, type,
operation, terminator, root, and stack-map violations at mutation time. Its
single global CFG seal costs 976 us, and cleanup's proof-preserving output seal
costs 7 us. The combined cost fell to 983 us, an 84.02 percent reduction.

Semantic construction rose by only 57 us from its 5,402 us baseline, so the
removed verifier work did not move into construction. Semantic lowering fell
from the 17,717 us attribution baseline to 12,603 us, a 28.87 percent
reduction.

## Correctness boundary

`FunctionBuilder` retains typed construction errors and now tracks duplicate
roots and dense unique stack-map identifiers while mutating. Sealing checks
only whole-function completion, reachability, dominance, and exact GC roots.
Alias canonicalization replaces values only with dominating same-typed inputs;
root deduplication and dead removal preserve the sealed contracts, so cleanup
does not rescan its output. Standalone `Function::verify` and defensive cleanup
remain available for external functions and transformations.

Focused tests independently run the full verifier over sealed cleanup output,
including alias/dead removal and collapsed GC roots. Strict
`MACHV_REGALLOC_VALIDATION=1` native tests passed 2,681/2,681.

The final AEGIS `.cwasm` is byte-identical to the ISS-442 artifact, including
relocations and metadata, with SHA-256
`0c31ca17b8f04e9ecd0022eb185d367d7027d197ba83f87cd762a8e2f4639840`.
