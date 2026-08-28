# AEGIS-128L Verification-Carrying Target VCode (2026-08-28)

## Revisions and method

- Validation split: `c6235b17`
- Sealed target construction: `c27ae86b`
- External-entry hardening: `61f845f4`
- Final state: checked production builder plus the revisions above
- Host: Apple M3 Max, arm64, macOS 26.5.2 (25F84)
- Workload: `examples/algorithms/aead_aegis128l.wasm`
- Seven detailed, serial, cache-isolated captures per measured state

Each process used a distinct `WASMOON_JIT_CACHE_DIR` and enabled schema-5
detailed metrics. No other corpus workload was run.

## Verifier attribution

Before sealing, target VCode validation had a 4,905 us median. The nested
metrics attributed 2,650 us to target-neutral CFG, dominance, operand, and
metadata checks, and 2,184 us to the ISA instruction scan. Optimizing only one
of the scans could not meet the 75 percent reduction gate.

## Sealed selection results

| Run | Module compile | Target total | VCode construction | VCode sealing | Code size |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 134,757 | 11,995 | 7,075 | 0 | 59,428 |
| 2 | 129,587 | 10,972 | 6,863 | 2 | 59,428 |
| 3 | 126,598 | 10,688 | 6,710 | 1 | 59,428 |
| 4 | 125,873 | 10,666 | 6,712 | 0 | 59,428 |
| 5 | 126,092 | 10,693 | 6,689 | 0 | 59,428 |
| 6 | 126,633 | 10,589 | 6,618 | 1 | 59,428 |
| 7 | 137,758 | 11,748 | 7,401 | 2 | 59,428 |
| Median | 126,633 | 10,693 | 6,712 | 1 | 59,428 |

The old validation median fell from 4,905 us to zero on the trusted path. Its
replacement sealing event had a 1 us median. Checked construction rose from
6,155 us to 6,712 us because it now rejects local edge, metadata, clobber, and
completion violations at mutation time. The 557 us increase is only 11.36
percent of the removed verifier cost, so equivalent work did not move into
construction. Target lowering fell from 15,036 us to 10,693 us, a 28.88
percent reduction.

## Correctness boundary

The exhaustive target selector now returns a private `ConstructedFunction`
capability from verified semantic MachV. Its `CheckedBuilder` rejects local
edge, metadata, clobber, and block-completion violations before sealing. Only
that capability can create the opaque `SelectedFunction` accepted by
`compile_selected`. Generic builder output cannot mint either state.
Standalone `lower`, `verify_vcode`, and `compile` retain the complete common
and ISA verifiers, with focused tests for malformed checked construction and
external VCode on both targets.

The final AEGIS artifact was byte-identical to the ISS-442 baseline. Both have
SHA-256
`0c31ca17b8f04e9ecd0022eb185d367d7027d197ba83f87cd762a8e2f4639840`.
All seven code-size vectors matched the baseline, including the 59,428-byte
total and 16,036-byte function 56.

Strict `MACHV_REGALLOC_VALIDATION=1` native tests passed 2,681/2,681. The
warning-73 check, generated interfaces, formatting, and module-boundary audit
also passed.
