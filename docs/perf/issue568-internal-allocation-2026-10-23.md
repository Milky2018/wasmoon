# Internal struct admission and generated allocation

This is local implementation evidence for ISS-671 / GitHub #568, based on
`7cf4fe9895a38e6315813eec9f28c2379aaab057` with an explicitly dirty working tree.
It supplements, and does not relabel, the earlier reference-allocation and
numerical-target receipts. The [JSON receipt](issue568-internal-allocation-2026-10-23.json)
contains source/binary hashes, raw samples, counter controls and validation scope.

## Retained implementation

Eligible typed struct reservations now generate machine instructions for the
successful allocation path. All refusal branches precede mutation. The path
checks the current heap, live debug policy, absence of bound byte/object quota
reservations, current local-to-canonical mapping, exact canonical layout, payload
capacity, collection threshold, payload offset range and prepared identity
capacity. It then publishes payload/identity/live-list accounting and initializes
the complete header and fields without a call, safepoint, growth or reentry.
Reference fields retain canonical tracing metadata and the existing fresh-object
initialization contract. Collection, verification, injected failures and budgeted
Stores use the original shared allocator and precise roots. There is no duplicate
atomic quota policy in generated code.

The embedding supplies `offsetof`-derived native layout metadata to the generic
compiler. Reusable compiler modules import no Wasmoon runtime implementation.
Codegen revision 20 invalidates old artifacts; the JIT ABI remains 8.

A heap-owned exact-object hint avoids repeated full struct admission for the
same reference, canonical identity, shape and field count. Each request still
resolves the current context/heap and current canonical type mapping. Subtype,
legacy and verification cases keep their full checks. The hint is not a root,
lease or owner, and never caches field values. Retirement, type changes, payload
growth, compaction and heap close invalidate it. Heap ownership avoids context
replacement/address-reuse ambiguity and follows the existing exclusive-mutator
contract.

Stable-identity bookkeeping makes generated allocation larger than a plain bump.
Unbounded expansion made a generated initializer grow from 137484 to 209820
machine-code bytes and register allocation from 28.7 to 73.5 milliseconds in a
separate diagnostic run. The retained implementation limits expansion with a
per-function cost budget of 512 (128 + four per field for each eligible
allocation). Larger functions retain the shared no-GC reservation helper.

The runtime also prepares a capacity-only identity window after shared
registration. Within the window, the identity page and live-list slot already
exist; advancing both counts together preserves that guarantee. This removes
repeated capacity/page traversal from generated allocation without reserving an
identity, allocating an object or precharging quota. Sweep, compaction and
rollback invalidate the window. Debug heap verification checks its invariants.

## Measured outcome

Five serial rounds alternate engine order, use fresh per-process caches and
assert result 1 on every run. Times below are medians, in seconds. The Wasmoon
baseline disables this turn's generated allocation and admission-cache changes
while retaining the preceding pending optimizations. The final binary contains
the bounded allocation path, prepared window and exact-object hint.

| Measurement | Baseline | Current | Optimized V8 |
| --- | ---: | ---: | ---: |
| Compilation | 0.806084 | 0.885581 | 0.454163 |
| Invocation including guest host calls | 2.230239 | 2.062075 | 0.782378 |
| Cold process wall | 3.125770 | 3.044945 | 1.288899 |

Invocation improves 7.54%, compilation costs 9.86% more, and cold process wall
improves 2.59%. The execution and compilation ratios to optimized V8 remain
**2.64x and 1.95x**. The requested 1.05x / 1.5x budgets are **not met**. This is
an incremental execution improvement with a measured compilation tradeoff.

Wasmtime's corresponding serial, cache-disabled cold process median is
2.494111 seconds. Its command includes compilation, loading, instantiation and
execution; it is not an isolated invocation measurement and cannot establish
the residual execution ratio to Cranelift.

A subsequent [phase-separated measurement](issue568-wasmtime-phases-2026-10-23.md)
uses a CLI-compatible Wasmtime API harness to measure compilation and invocation
directly. Its fresh samples supplement this historical batch rather than mixing
absolute times across measurement rounds.

The pinned guest comes from Core commit
`7547b846d38de3efa5509cb1b74ffb7ed9a4a3d1`, the same asserted 20000-iteration
property used in the earlier reports. Original artifact SHA-256:
`16bcf1f9c694573d1fb5f80ed0d44686a130f9f91d501eeeb2697544eca79dc4`;
isolated probe SHA-256:
`fb7bf21507c21de4ffb79126f94cc0846314bd0b03c33060a533f15afe441db1`.
V8 uses Node 25.2.1 / V8 14.1.146.11-node.14, with Liftoff/lazy compilation
disabled and one Wasm compilation task. Wasmtime 49.0.1 uses serial compilation
and no cache. Wasmoon timing removes verification/diagnostic flags. This host
is macOS ARM64. Unrelated background activity was not stopped; all raw samples,
including noisy samples and rejected variants, remain in the receipt. No owned
build, test or profiler overlaps the acceptance timing rounds.

## Causal controls and rejected changes

Separate untimed, privately instrumented pre-window controls find:

| Counter | Baseline | Generated allocation | With exact-object hint |
| --- | ---: | ---: | ---: |
| Struct-view helper requests | 84061688 | 84061688 | 84061688 |
| Full admissions avoided by hint | 0 | 0 | 49653990 |
| C no-GC reservation requests | 25358414 | 11247619 | 11247619 |
| Slow allocation requests | 1097548 | 1097548 | 1097548 |

These controls identify 14110795 removed reservation-helper calls and about
59.1% fewer full struct admissions. The view helper still crosses the C ABI
84061688 times; the hint has not removed this residual cost. These are separate
counter builds, not timing results or exact final-window counters.

A constructor-result physical-view prototype passed semantic tests but removed
no view-helper requests on the original guest. It was deleted from production.
Unbounded allocation expansion and a larger 1200-cost expansion budget were
also rejected in favor of bounded code growth. Their samples remain labeled
separately and are not substituted for final-source acceptance.

The lifecycle regression is independently sensitive to cache invalidation:
removing only compaction invalidation in an isolated copy reads sentinel 99
instead of the surviving object's 17. Restoring invalidation passes both
regressions. Tests also cover growth, writes, nominal incompatibility, rollback,
close, page boundaries, accounting, transitive references, quotas and debug
configuration changes after compilation.

## Validation and limits

- Native: 3064/3064 with `VCODE_REGALLOC_VALIDATION=1`,
  `WASMOON_GC_VERIFY=1`, `WASMOON_GC_ASSERT_BARRIER=1`.
- Ordinary runtime fast-path package: 192/192; wasm: 1456/1456.
- Fresh isolated macOS ASan/UBSan: 292/292, both ASan positive controls detected.
  Dirty source is recorded. LSan is unavailable; emitted JIT instructions and
  MoonBit runtime objects are outside this sanitizer's instrumentation.
- Core: portable native, actual wasm, native JIT, and verification-enabled native
  JIT each pass 258 files / 62563 assertions, with zero failed/unsupported.
- Component: the unchanged exact stable-0.2, async-0.3 and future-gated suites
  each aggregate to 59 files / 1385 commands in interpreter and JIT, no skips.
- Strict native/wasm checks, info/fmt, module boundaries, generated MSVC bridges,
  whitespace and Python 178 tests (54 existing platform skips) pass.
- Both target selection paths are tested. This host does not establish x64
  execution, Windows acceptance or Linux LSan acceptance.

All owned source copies, builds, reports, caches and logs are deleted after
recording these results. `_build` contains only Moon outputs. No commit, push,
PR action, merge, publication or release is performed by this checkpoint.
