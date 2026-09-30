# Compiler priorities and rejected scalar-cursor experiment

Date: 2026-09-29. Source: `9ef491a115f30062581ba9a9f9a700b0e58fbada`. Tracking: ISS-598.

## Current profile

Three instrumented full-public-compile captures per input, optimization level 2. Values below are medians in microseconds, computed after summing each stage across functions in each capture. These are hotspot estimates, not speedup estimates. Full fixture compilation and instrumented stage totals have different boundaries/overheads; they must not be treated as an exact additive accounting identity.

| Input | Functions | Full compile | Optimize | Lower | Regalloc | Emit | Bundle allocation (inside regalloc) |
|---|---:|---:|---:|---:|---:|---:|---:|
| onetimeauth | 53 | 37001 | 9870 | 5240 | 11461 | 2185 | 3764 |
| aegis | 63 | 54231 | 14648 | 7689 | 16701 | 3174 | 5866 |
| moonbit | 409 | 104481 | 24900 | 14522 | 25979 | 8309 | 8152 |
| rust | 280 | 111543 | 27529 | 15029 | 30448 | 6326 | 9435 |

The two C workloads share a large libc-shaped function, so they are not two independent compiler stress shapes. The MoonBit tracker module and Rust P1 readdir module add different function-size distributions. Exact inputs and hashes are in the archive; the Rust input is a cached build, not a claim of fresh upstream correctness validation.

Register allocation remains roughly one quarter to one third of complete compilation; bundle allocation is its largest subphase. Acyclic optimization is the largest optimizer pass. `allocate_vcode` and its child phase durations are nested and must not be added together. These measurements prioritize investigation; they do not demonstrate that any particular rewrite is profitable.

## Candidate and rejection

The occupied-range index already has successor links. The candidate replaces its at-most-one-element cursor array with an integer sentinel, removing Option/array bookkeeping and obsolete private scratch. It preserves allocation policy and traversal order. The patch is archived and **fully reverted** from production source.

Strict native checks and all 71 regalloc tests passed, including seek/end boundaries, eviction and splitting. Both complete-compilation rounds used 21 AB/BA pairs per workload. The second round reverses workload order. All artifacts are byte-identical across before/after samples. This is 336 timed compilations plus 16 warmups; there was no concurrent profiling/build activity.

| Input | Round 1 change [95% interval] | Round 2 change [95% interval] |
|---|---:|---:|
| onetimeauth | +0.055% [-0.404, +0.212] | +0.252% [+0.017, +0.637] |
| aegis | +0.033% [-0.127, +0.592] | +0.174% [-0.448, +0.891] |
| moonbit | +0.208% [+0.074, +0.741] | -0.349% [-1.003, +0.226] |
| rust | +0.008% [-0.622, +0.357] | -0.272% [-0.723, -0.018] |

There is no repeatable benefit across rounds. Some intervals favor a small regression. The candidate fails the complete-compilation gate, so no CLI speedup is claimed and no full external suite was run for this rejected patch. Shorter code alone is insufficient justification for retaining a performance change. Dedicated allocation-counter equivalence was not established; artifact identity is the evidence actually collected.

The next justified investigation is algorithmic work inside bundle allocation (probe/scan/conflict costs), or acyclic optimization, using the distinct input shapes above. This report does not pre-approve an implementation or claim a reduction in the overall performance gap. There is no new production optimization in this change.

Evidence: [raw profiles, both rounds, validation logs and rejected patch](compiler-priorities-2026-09-29.json.gz).

## Final baseline validation

After restoring all candidate source files byte-for-byte, `moon info`, `moon fmt`, `moon check --target native --warn-list +73 --deny-warn` and all 2605 native tests pass. Logs are archived. This verifies the unchanged production baseline, not an accepted optimization.

ISS-580 and ISS-585 are closed using successful cross-platform [run 36374528719](https://github.com/Milky2018/wasmoon/actions/runs/36374528719), whose tested commit contains both fixes. A fresh full [run 36517870026](https://github.com/Milky2018/wasmoon/actions/runs/36517870026) at `9ef491a1` additionally passes Linux AMD64, Linux ASan/UBSan, macOS ARM64 and Windows MSVC. Windows Clang is still in progress at this report snapshot; this is not a claim that the fresh run is entirely green.
