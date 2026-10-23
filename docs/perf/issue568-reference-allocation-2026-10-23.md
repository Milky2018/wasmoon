# Typed reference-struct allocation

## Experiment and result

This followup starts at release commit
`7cf4fe9895a38e6315813eec9f28c2379aaab057`. It is local macOS ARM64 evidence
on an Apple M3 Max, not CI or release acceptance. Historical receipts remain
unchanged. The [JSON receipt](issue568-reference-allocation-2026-10-23.json)
contains individual samples, binary hashes, separate diagnostic counts and
validation provenance.

The previous original-workload profile identified typed allocation, allocation
root selection and checked views as substantial costs. The first hypothesis was
that reference structs unnecessarily enter the general allocation path even
when capacity, identity slots and canonical layouts are already available.

An isolated candidate changes only three decisions: permit reference fields in
the existing small-struct lowering, encode their reference bit in the layout
shape, and admit matching reference layouts in the existing reservation helper.
There is no change to the guest, allocator policy, collection threshold, root
protection or scheduling settings.

The exact asserted Core property remains pinned to
`7547b846d38de3efa5509cb1b74ffb7ed9a4a3d1`, with 20000 iterations and guest
SHA-256 `fb7bf21507c21de4ffb79126f94cc0846314bd0b03c33060a533f15afe441db1`.
Every measured run returns `1`. Five serial pairs alternate baseline/candidate;
each process uses a fresh artifact cache, with verification, cancellation and
cooperation disabled. No owned build, test or diagnostic process overlaps timing.
Uncontrolled background OS load remains a limitation.

| Median seconds | Released baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| Compilation | 0.752362 | 0.789557 | +4.9% |
| Invocation | 2.534273 | 2.344985 | -7.5% |
| Whole cold process | 3.623183 | 3.445651 | -4.9% |

Node 25.2.1 / V8 14.1.146.11-node.14 runs the same guest with
`--no-liftoff --no-wasm-lazy-compilation --wasm-num-compilation-tasks=1`.
Its five-run invocation median is 0.786453 seconds: the invocation ratio changes
from **3.22x to 2.98x**. This is an incremental improvement, not resolution of
#568 or evidence of an advantage over V8. Larger generated allocation branches
also have a measurable compilation cost.

## Causal control

Separate instrumented processes count entries to `gc_alloc_struct_slow` and
successful `gc_reserve_struct_fast_impl` reservations by local type. These
diagnostic binaries are never used for timing. Counts exclude arrays and the
separate wide-payload allocators.

| Counted struct allocations | Baseline | Candidate |
| --- | ---: | ---: |
| Slow helper | 14944141 | 1097548 |
| Fast reservation | 11487044 | 25333637 |
| Total | 26431185 | 26431185 |
| StringView (type 43), slow | 11803567 | 11616 |
| Decimal (type 244), slow | 104686 | 90 |

The counted allocation total is unchanged. The improvement replaces slow-path
root selection, payload staging and general policy entry for approximately
13.85 million allocations; it does not remove their identities, byte/object
charges or reference fields. Fast reservation still crosses the existing native
helper and performs quota and identity work. Checked GC views and digit-loop
machine code remain other bottlenecks established by the previous profile;
this experiment does not establish their post-change percentages.

## Lifetime and compatibility contract

- The canonical runtime descriptor must match the compiler's field count,
  width/reference shape and aligned object size. Reference fields use its
  existing tracing metadata; this does not duplicate a layout or GC graph.
- The reservation cannot grow, collect, reenter managed code or publish the
  partially initialized value to guest execution. Initialization emits only
  header/payload stores before forwarding the completed reference.
- Fresh initialization follows the existing typed allocator's barrier contract
  in this stop-the-world collector. Ordinary reference mutations retain their
  barriers. A moving/reentrant operation still invalidates physical borrows.
- Missing capacity/layouts, collection pressure, unsupported widths or more
  than sixteen fields, verification and injected failures retain the collecting
  slow path and its precise allocation-input roots.
- The interpreter and JIT share the same native storage, identities and quota
  admission. No new public API or FFI contract is introduced. Codegen revision
  19 invalidates cached revision-18 code; the JIT ABI remains version 8.

## Regression and validation

The new public two-target lowering regression fails before the implementation
with zero fast-reservation relocations. Both AArch64 and x64 now select fast
reservation **and** the collecting fallback for ordinary/default reference
constructors. This is target selection coverage, not x64 execution on ARM.

Public runtime tests at O0/O2/O3 cover packed fields, child and tagged i31
references, byte-quota denial without partial admission, injected persistent
failure, retry/reuse, null defaults, repeated pressure collection and a child
reachable only through its parent. Existing identity-quota, rollback, reentry,
native-entry and wide-layout regressions remain enabled.

Local validation passes:

- Native 3046/3046 ordinarily and with `VCODE_REGALLOC_VALIDATION=1`,
  `WASMOON_GC_VERIFY=1`, `WASMOON_GC_ASSERT_BARRIER=1`; wasm 1445/1445.
- Strict checks on both targets, `moon info`, formatting, module boundaries,
  generated MSVC bridges and Python 178 tests (54 existing platform skips).
- Fresh isolated ASan/UBSan 286/286, async lifecycle and resolver controls,
  and both ASan positive controls. Sources are explicitly dirty based on
  `7cf4fe98`; macOS does not provide Linux LSan acceptance.
- Core native interpreter, JIT and actual wasm each 258 files / 62563
  assertions, zero failures or skipped/unsupported cases.
- Component interpreter and JIT each 59 files / 1385 commands, no failures
  or skips, with the pinned wasm-tools 1.254.0.

Scratch source copies, diagnostic patches, binaries, builds, caches and logs
use one owned OS TemporaryDirectory and are removed after evidence extraction.
Only compact evidence and permanent regressions remain in the repository.
No commit, push, merge, version bump or publication is part of this followup.
