# GC collection coordination (ISS-636)

Local macOS ARM64 evidence, 2026-10-19. ISS-638 was committed first as
`6637ad6c5e65170d05b729aec0385c038ba7919c`; the new collection changes remain
uncommitted on the same feature branch. No push, PR or new platform acceptance
is represented by this directory. The installed stable toolchain is unchanged.

## Changes and ownership

The earlier allocation retry policy already lives in MoonBit. This follow-up
removes the remaining C prepare/finish/abort protocol and the C-retained visitor
closure. One private MoonBit `CollectionState` owns the visitor and same-heap
collection guard. Both native collection and transaction rollback enter that
coordinator. C retains only its RC state owner, a synchronous closed callback,
physical heap operations and a cached precision view.

The coordinator holds one visitor throughout a cycle. Preparing roots, choosing
abort or commit, sweeping auxiliary owners and completing the visitor use that
same snapshot. Clearing or replacing a binding applies to the next cycle.
Native marking mode likewise stays fixed until completion. Same-heap recursion
is rejected before entering another visitor phase; different heaps have
independent state. The native request pins its heap through both collection and
rollback, even if a visitor closes the embedding owner.

The protocol helper is non-raising and returns all outcomes to one cleanup
point. `collection-generated.txt` records the actual final release outer
coordinator: no `moonbit_malloc` or defer environment is present. The request is
a borrowed `#external` stack address, never an owned/finalized object. Callbacks
return before any native trap or stack transfer. The physical root arrays and
the visitor's expanded result use ordinary MoonBit RC ownership.

The native precision view occupies existing padding before the allocation
policy pointer. `sizeof(GcHeap)` remains 160 bytes; data, object-table and
allocation-policy offsets remain 0, 24 and 144. There is one additional managed
coordinator per heap. No per-object storage or JIT context field is added.
Private native tests now receive a heap through the same MoonBit constructor;
the raw physical constructor is private to its C file. Public `.mbti` interfaces
are unchanged. The implementation stays in the physical handle's owning
package because its constructor and methods share private collection state.

See the [full ownership inventory](../../native-runtime-policy.md).

## Before/after regressions

`regressions-before.log` runs the first three public API fixtures against the
old implementation, with three failures:

- Clearing the visitor during phase 0 leaves phases `[0]`, missing finish.
- Replacing it during phase 0 leaves the original at `[0]`; abort goes to the
  replacement rather than the visitor that prepared the collection.
- Same-heap recursive collection succeeds instead of returning failure and can
  reclaim an object that belongs to the outer collection's roots.

The final shared fixture file has six tests, executed by both ordinary native
and isolated sanitizer runs:

1. Finish the captured visitor after unbinding, for collection and rollback.
2. Abort the captured visitor after replacement, preserve objects on failure,
   and use the new visitor on a later successful collection.
3. Reject same-heap recursion without reclaiming outer roots.
4. Retain the heap and captured visitor when its owner closes during either
   collection or rollback.
5. Permit collection of a different heap inside a visitor.
6. Preserve precise marking after unbinding: an integer resembling a reference
   must not become a new conservative edge halfway through the cycle.

Three temporary controls remove snapshot use at finish, the collection guard,
or delayed precision-mode updates. Each independently makes its targeted test
fail. `negative-controls.json` and `negative-*.log` record those expected
failures and the restored six-test success. No mutation remains in production.
The source hashes below match the final fresh sanitizer copies.

## Final local validation

| Check | Result | Receipt |
| --- | --- | --- |
| Info/fmt/strict native warning check | Pass, no public interface change | Reviewed source/interface diff |
| All native tests | 2744/2744 | `native-final.log` |
| Strict C warning gate | 43 stubs | `strict-c.log` |
| Fresh ASan/UBSan | 181/181, both ASan controls detected | `sanitizer-*.log`, `sanitizer-summary.json` |
| Python scripts | 172 tests, 54 platform skips | `script-tests.log` |
| Core WAST, both engines | 258 files, 62563 assertions per engine | `core-wast.log` |
| GC differential | 17 files pass in interpreter, JIT, stress+verify and smaller-heap lanes | `gc-differential.json` |
| Components stable/async/future-gated, both engines | 59 files, 1385 commands per engine; no skips | `component-*.log` |
| Wasmtime misc stack-switching, both engines | 46 files/75 assertions per engine; 92 passes, zero skips/errors | `wasmtime-stack.json` |

`sanitizer-summary.json` says `source_dirty=true`, `build_reuse=fresh`,
`leak_detection=false` and LSan `not_applicable`. This is macOS ASan/UBSan,
not Linux leak detection or Windows compiler acceptance. Existing empty-object
`libtool` diagnostics remain; the strict C gate denies source warnings. No
warning, sanitizer or test rules were weakened. Expected negative CLI messages
in the native log are separate from its final zero-failure count.

`source-manifest.json` binds the final code, binary and sanitizer source copies.
The saved before binary matches ISS-638's final fresh release receipt, whose
changed-source hashes were checked against commit `6637ad6c`. Both install and
sanitizer runners use fresh private build directories. Presentation trailing
whitespace is trimmed in archived text logs; source hashes and numerical data
are preserved. The ordinary incremental dependency problem remains ISS-634.

## Performance

Normal release binaries, serial measurements with no concurrent build, test,
debugger, profiler or other benchmark. `measure.py` uses 21 shuffled paired
rounds after two warmups, seed 636. Two native `putchar` call boundaries capture
thread CPU time and process retired instructions/cycles around guest execution,
excluding loading, compilation and teardown. The counter ignores the known
ISS-640 character-argument defect and requires exactly two boundary calls.
Every run independently checks the expected arithmetic result with WAST
`assert_return`. No core/frequency affinity or hardware cache event is measured.

CPU medians in milliseconds. Change and confidence interval describe paired
ratios; they need not equal the ratio of the two aggregate medians.

| Workload | Before ms | Final ms | Paired change | Bootstrap 95% interval |
| --- | ---: | ---: | ---: | ---: |
| word-2000000 | 93.697 | 93.659 | +0.08% | -1.09% to +0.67% |
| wide-1000000 | 24.527 | 24.898 | +2.55% | -0.84% to +4.92% |
| wide-30000 | 511.438 | 511.732 | +0.02% | -2.06% to +0.87% |


All three final paired CPU intervals contain one. These samples do not
establish a resolved speedup or slowdown, and are not a cross-platform promise.
`collection-counts.json` comes from separate diagnostic runs, not timed samples:
ordinary word/wide loops execute zero collections in both versions; the forced
wide loop executes 29999 collections and reclaims 29999 objects in both, with
identical root totals and debug-output hashes. Its environment is
`WASMOON_GC_FAIL_ALLOC_EVERY=2`; normal benchmarks clear that injection.

`performance-with-defer.json` deliberately retains the intermediate result:
normal allocation time was roughly 4–5% higher, while forced collection was
approximately unchanged. Generated code revealed a per-collection defer
closure, which was removed by a non-raising helper. The intermediate precision
flag also grew the native heap to 168 bytes; moving it into existing padding
restored 160 bytes. The ordinary loops execute zero collections, so their
intermediate timing difference cannot be assigned to the defer allocation.
The final build does not reproduce that timing separation. No hardware-level
placement cause has been proven; instruction counts remain nearly equal. No
layout tuning flags or duplicate native coordinator were added.

Raw final samples, binary/fixture hashes and paired bootstrap intervals are in
`performance-final.json`. Reproduce with separately saved release binaries:

```sh
clang -O2 -dynamiclib store-boundaries-dylib.c -o /tmp/gc-boundaries.dylib
python3 measure.py /absolute/before /absolute/after . \
  /tmp/gc-boundaries.dylib /tmp/gc-performance.json
```

The old retry-policy slice was accepted by PR #541 CI. These new state,
callback and rollback paths still require Linux ASan/UBSan/LSan and Windows
Clang/MSVC acceptance. ISS-636 remains in progress for that final criterion.
