# parse_double: nontrapping views from produced array references

This follows the [verified array-region stage](issue568-array-regions-2026-10-22.md),
committed and pushed as `5fa50157` after `a7874e12`. The local evidence below was captured in a working tree based on `5fa50157`,
before committing this followup; it is not CI acceptance or publication.
The [receipt](issue568-produced-array-views-local.json) preserves sources,
binaries, all timing samples, counters, phase measurements and validation.

## Diagnosis and contract

Fresh sampling still concentrated in checked array helpers. A temporary,
isolated address-mapping probe identified `Decimal.left_shift` and
`Decimal.right_shift` as important guest callers. Neither that instrumented
binary nor its timing is used as performance evidence.

In `left_shift`, a reference-valued struct read was already hoisted before the
loop. However, the first array operation remained inside the loop. The physical
planner required an executed array operation in the preheader, so it could not
reuse a view of that reference. Earlier first-use length caching preserved traps
but did not make a physical view available before the cycle.

The projection is now a total, nontrapping query: absent heaps, null references,
invalid objects, incompatible layouts and verification mode return null. It
still checks actual live object kind, physical stride and absence of reference
fields. Each real array access retains its unsigned bounds check and original
checked fallback, including null/bounds traps.

A preheader reference-valued `struct.get` can therefore prepare a view from its
completed result, even when that result is nullable and the loop might execute
zero times. The holder operand is not the produced array. The generic dialect
adapter exposes completed results and replaces its separate completion flag
with that result state. It does not expose target instructions or heap offsets.

The independent verifier checks the producer/result identity, unique preheader,
source emission order, all paths around the loop and the complete suffix after
the preparation point. Calls, allocation, polls, reentry, raw writes and unknown
effects still end the borrow. No pointer crosses a safepoint, and no element
value is cached. Unsupported objects retain the previous accessor behavior.

Disabled embeddings and functions without eligible numeric array operations now
skip physical-plan CFG/proof work. Codegen revision 17 rejects revision 16.

The new private producer-plan regression failed before the repair. Negative
cases cover calls, allocation and raw writes after the producer. Public runtime
regressions exercise nullable fields, zero-trip loops, actual loads/stores,
null/bounds traps and cancellation-enabled compilation. Both ARM64 and x64
selectors check a single preparation for both origin forms; this is not x64
execution evidence.

## Same-source measurements

The pinned Core property, Wasm bytes, seed 37, six spellings, 20000 cases and all
guest assertions are unchanged. Every result is 1. Baseline is clean `5fa50157`;
candidate is explicitly dirty at that base. Both were freshly built with the
same SDK. Each invocation gets a new cache, and Wasmtime 49.0.1 uses
`-C parallel-compilation=n -C cache=n`.

An initial final-source three-sample run showed scheduling waits: one candidate
invocation took 6.660 s wall but 4.923 s user CPU. That entire run remains in the
receipt. A subsequent seven-sample alternating-order confirmation, without a
source or binary change, gives these medians:

| Engine | Cold wall | User CPU | Wall / Wasmtime |
| --- | ---: | ---: | ---: |
| Baseline `5fa50157` | 6.089 s | 5.995 s | 2.50x |
| Candidate | 4.931 s | 4.873 s | 2.03x |
| Wasmtime | 2.435 s | 2.423 s | 1.00x |

This is a **19.0% paired wall reduction**, with approximately **2.03x** remaining
cold wall ratio and **2.01x** user-CPU ratio. Historical 2.37x and the fresh
baseline 2.50x are different measurement sets, not a single ablation.
The three-sample 1000-case control improves from 1.196 to 1.092 s wall, versus
0.401 s in Wasmtime. These are cold CLI measurements, including compilation,
installation and startup, not a warm execution-only benchmark.

Separate full-case kernel-counter runs retire 121424051555 baseline instructions,
89892569960 candidate instructions and 60858773129 Wasmtime instructions: about
**26.0% fewer instructions**, still **1.48x** Wasmtime. RSS is unchanged at about
336 MiB in both Wasmoon binaries versus 70 MiB in Wasmtime. The memory gap is
not repaired by this compiler change.

One phase-metrics diagnostic run reports invocation time falling from 4.893 to
3.863 s, compile time from 0.612 to 0.571 s and load/preparation from 0.313 to
0.275 s. These single trials separate costs but are not the timing medians.

In separate three-second stack samples, array get/set/projection leaves decrease
from 331/362/197 to 86/96/7. Those are samples, not event counts or an exact
partition of the speedup. The remaining visible costs include checked struct
reads, typed allocation, precise allocation-root selection, root scopes and
memory movement. Counters also show a remaining cycles gap larger than the
instruction gap; these measurements do not establish a specific cache/TLB cause.

## Validation and delivery

- Native 3007/3007 with regalloc, GC and barrier verification; another
  3007/3007 with GC verification off to exercise physical accesses.
- Wasm 1420/1420; strict native/wasm warning checks, info/fmt, boundaries,
  generated MSVC bridges and whitespace passed. Python 178 tests passed with
  54 existing platform skips.
- Fresh isolated macOS ASan/UBSan 278/278, event loop and both ASan positive
  controls passed. Physical access mode was exercised with barrier and regalloc
  checks enabled. LSan is unavailable on macOS; MoonBit runtime objects and JIT
  machine code are excluded by the existing harness.
- Core native interpreter, native JIT and actual wasm each passed 258 files and
  62563 assertions. Actual wasm reports zero unsupported assertions. Component
  interpreter and JIT each passed 59 files/1385 commands, with zero skips.
- The independent build copy matched the frozen 815-file functional source
  manifest before and after execution. Local receipts retain dirty provenance;
  no Windows, Linux LSan or platform CI acceptance is claimed.

The prior stage was committed and pushed. This receipt captures the followup
before its separate commit/push; those operations do not change its dirty-source
provenance. #568 remains in progress. Owned OS temporary sources, builds,
binaries, profiling data and caches were removed after recording the compact
receipt. No PR, merge, package publication or toolchain change occurred.
