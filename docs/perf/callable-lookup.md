# Store callable lookup

Tracking: [ISS-681](../../issues/ISS-681.md), part of
[PR 582](https://github.com/Milky2018/wasmoon/pull/582).

## Attribution and design

Two CPU samples identify table-call resolution, callable type lookup and
Store-to-executable lookup in the original randombytes corpus guest. They do
not support the initially suspected `random_get` byte-copy cost. Disposable
counters find about 26.44 million queries of each callable view, requiring
about seven type-search and six pointer-search steps per call. Counter runs
provide attribution, not performance measurements.

The actual 60-function view has Store addresses
`0,6,7,10,11,12,17,40,54..105`. Direct position probes based on zero or the first
key miss this sparse prefix and regress the case by 2.9% / 5.8%; both experiments
were removed. The retained design explicitly represents holes.

MoonBit constructs a Store-address-to-existing-record-ordinal index alongside
each sorted view. It admits an interval only when its span is at most twice
the input population and fits Int32; otherwise queries retain binary search.
Zero slots mean absent keys; duplicates select the original first record.
This guest needs 106 slots in each index, 848 bytes total before array headers.
Arbitrarily distant public keys cannot force an unbounded dense allocation.

Queries read the current identity or pointer through the ordinal. There is no
cached call target, new execution protocol or public runtime interface.
Replacing keys republishes their index with the same RC-owned native view;
in-place identity updates remain visible. Views retain index storage when the
MoonBit registry owner leaves scope. Clearing and finalization release it.
Bounds, null, subtype, registration, Store isolation and table mutation checks
remain in their existing paths. Wasm builds omit the native-only index.

## Measurements

Five alternating serial cold pairs compare independently frozen release
binaries on macOS ARM64. Parent is `0c91fb89`, SHA256 prefix `045b10ecdb04`;
candidate prefix is `3120a077bdf5`, also matching the final validation CLI.
No build, profiler or other workload runs concurrently. Original corpus inputs
and iterations are unchanged; each process exits successfully.

| Invocation | Parent | Indexed | Reduction |
| --- | ---: | ---: | ---: |
| randombytes | 654.051 ms | 449.788 ms | 31.2% |
| metamorphic | 2.631541 s | 2.542212 s | 3.4% |
| stream | 5.425154 s | 5.432634 s | effectively unchanged |

Randombytes cold process wall time is 702.998 -> 496.209 ms; compiler-only
medians are 37.936 / 36.036 ms. No general compiler speedup is claimed.
Use the release CLI with `WASMOON_RUN_METRICS_FILE` and a separate empty
`WASMOON_JIT_CACHE_DIR` for every sample, alternating baseline/candidate order.
The invocation timer includes host calls; whole-process wall includes startup
and teardown. Keep samples and caches in automatically removed OS temporary
directories. These are local paired gains, not an engine-wide ranking.

## Validation boundary

Ordinary and register-allocation/GC/barrier-verified native pass 3113/3113;
wasm passes 1464/1464. Public metadata tests cover holes, first duplicates,
identity/pointer replacement, changed origins, sparse maximum-Int32 keys,
clearing and retained views after owner teardown. A structural test protects
the dense-storage bound. Existing actual indirect-call regressions remain.
Strict checks, boundary/MSVC-bridge audits, 44 C stubs and 180 Python tests
(54 existing platform skips) pass. Fresh isolated macOS ASan/UBSan passes
318 tests, event loop and both ASan controls on explicitly dirty parent-based
sources. Linux LSan and actual Windows/x64 execution remain separate CI gates.
The final release CLI has the same measured binary hash. Core passes258 files /
62563 assertions and Component59 files /1385 commands per engine, zero skips,
with register-allocation, GC and barrier verification enabled.
