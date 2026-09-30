# MoonBit-owned callable registry

Date: 2026-09-29. Tracking: ISS-605. Baseline: `2c0b2997cba96f0acd4cb82b0c010b765721a9fc`.

## Scope and ownership

MoonBit owns the parent, address, identity and original-position arrays. It decides whether to rebuild, sorts changed addresses with the standard library and updates identities in place when addresses are unchanged. Unsigned address ordering and first-duplicate semantics are preserved. C retains RC references to three typed array payloads in a small native view; it performs no registry allocation, copy or sorting outside that managed view itself. Native queries still use binary search without callbacks into MoonBit.

The managed JITContext type and its callable binding declaration now live with the context C stub in jit_ffi. Contexts retain their local type/tag arrays instead of copying them into malloc buffers. The existing higher-level Array-taking binding still copies caller input into those FixedArrays, preserving input isolation. Lower-level FixedArray bindings explicitly share storage. Store mutation and guest execution remain serialized; this is not a concurrent snapshot protocol.

All C-retained borrowed references are incremented before the old references are released. The native-view finalizer releases array references; context teardown releases the view and mappings. The view does not point back to the MoonBit registry. A context can outlive the MoonBit registry record safely. Replacement retains its public Bool result for compatibility, but now uses MoonBit allocation and has no separately recoverable native malloc failure. This is an intentional failure-contract change.

The context owner remains 440 bytes and its generated-code prefix remains 128 bytes. Full context/activation ownership migration is outside this change and remains tracked by ISS-602.

## Measurement method

Local macOS arm64, MoonBit 0.1.20260920 / moonc v0.10.14+7d59c7ec9. Before/after runs alternate order. Publication and query probes retain 15 pairs after one warmup; guest workloads retain 31 pairs. Tables show batch medians (publication divided by 1,000), plus the median paired percentage change and a percentile bootstrap interval. These intervals describe this session, not cross-machine guarantees.

Publication calls the real public MoonBit API 1,000 times per mode with 256 parents and 2,048 unordered entries. Query probes use the exact extracted C lookup body and each version's headers against a real MoonBit-created registry, 200,000 mixed hit/miss queries per batch with a verified checksum. This is an extracted-helper microbenchmark, not a whole-runtime query measurement. Construction is outside the query timer.

Guest measurements use the pinned and rebuilt CLI executables, the existing 10-million-call indirect WAST fixture, and AEGIS. Every retained AEGIS sample reports a warm cache hit. No build or test workload overlaps the retained final samples. An earlier AEGIS run overlapped a late check and was discarded in full; its raw samples are archived separately. Initial publication measurements are also retained.

### Publication

| Mode | Before per call | After per call | Paired change [95% interval] |
|---|---:|---:|---:|
| Unchanged | 3.921 us | 2.905 us | -23.51% [-28.38%, -20.64%] |
| Parent update | 3.987 us | 3.195 us | -19.58% [-21.50%, -16.48%] |
| Identity update | 4.050 us | 2.963 us | -26.94% [-29.37%, -25.67%] |
| Address update | 51.224 us | 58.343 us | +14.43% [+12.30%, +15.63%] |

Address-changing publication is slower. Moving sorting policy into MoonBit does not remove its cost, and the standard sorter allocates temporary objects. Unchanged-address paths avoid temporary interleaved arrays and repeated native copying. No custom sorting algorithm was introduced.

### Native query

| Entries | Before batch | After batch | Paired change [95% interval] |
|---|---:|---:|---:|
| 4 | 0.483 ms | 0.449 ms | -7.23% [-13.75%, -4.13%] |
| 64 | 3.029 ms | 2.867 ms | -6.52% [-13.83%, -2.32%] |
| 1024 | 5.265 ms | 4.704 ms | -10.68% [-18.63%, -6.76%] |
| 16384 | 8.886 ms | 7.008 ms | -21.87% [-23.54%, -19.85%] |

### Guest execution

| Workload | Before | After | Paired change [95% interval] |
|---|---:|---:|---:|
| indirect | 233.262 ms | 235.459 ms | -0.09% [-1.19%, +1.35%] |
| aegis | 801.030 ms | 789.118 ms | +0.45% [-0.71%, +1.32%] |

Small guest differences should not be promoted to an overall runtime speedup or an explanation of the previous context-placement observations.

## Allocation accounting

A separate system-allocator probe instruments generated MoonBit code, the MoonBit runtime C sources and registry stubs. It counts requested bytes, including MoonBit object/array headers and finalizer storage. It excludes libc-internal allocations, allocator metadata, resident pages and fragmentation; it is not a production-allocator RSS or timing benchmark. Caller input is identical (66,624 live bytes) at the initial checkpoint.

| Measurement | Before | After |
|---|---:|---:|
| Registry persistent requested bytes, excluding caller input | 33,832 | 33,920 |
| Initial publication peak including caller input | 134,264 | 100,544 |
| Allocations during initial publication, including registry construction | 5 | 796 |
| Allocations during unchanged replacement | 2 | 0 |
| Allocations during identity replacement, excluding caller tuple mutation | 2 | 0 |
| Requested bytes remaining after owner release | 0 | 0 |

Persistent storage increases by 88 bytes per nonempty registry in this probe. Both versions retain 16 bytes per callable entry and 4 bytes per parent. The new 32-byte native view, MoonBit registry record and four array headers account for the increase relative to the old 24-byte native registry. The position array stays owned only by MoonBit; it is not retained by the native view. Thus a context outliving the registry need not retain the sorting index.

The 796 initial allocations expose standard-sort temporary allocations, despite the lower peak. This change improves the ownership boundary and repeated publication behavior; it does not reduce every memory metric. Per-context local/tag arrays likewise retain their MoonBit headers, while eliminating the temporary-array-to-malloc copy. Context-size savings are not claimed.

## Validation

- Strict MoonBit native check, warning 73 enabled and warnings denied.
- 2,611 native tests; 66 ASan/UBSan tests with instrumentation proof.
- 38 C stubs compiled with warnings denied; module boundary audit passed.
- Core WAST: both engines passed 258/258 files, 62,563 assertions each.
- Async 0.3 component WAST: 24/24 files, 153 commands, no skips.
- Tests cover shared updates, independent registries, subtype/tag maps, rebinding, repeated clear and native contexts outliving MoonBit owners.

Cross-platform CI is recorded separately in ISS-605. Raw measurements, probe sources, source/binary hashes and validation logs are in [the evidence archive](moonbit-callable-registry-2026-09-29.json.gz).
