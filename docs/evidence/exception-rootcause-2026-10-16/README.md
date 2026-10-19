# Exception construction: root cause and minimal repair

Local macOS ARM64 investigation of the dirty working tree after `d9279052`.
This follows the [insertion investigation](../exception-insertion-2026-10-16/README.md).
The final runtime change is only [an independent root-registration output variable](before-to-final.patch).
It adds no fast path, ownership mode, ABI entry point, compiler annotation or
linker requirement. Linux LSan and Windows Clang/MSVC are **not** accepted by
these local receipts. No commit or remote delivery is claimed.

## Established compiler problem

The native constructor passes `&entry.root_registration`, a member of its pending
40-byte record, to an external function. Apple Clang 21 at the normal release
`-O2` settings consequently materializes the entire record on the stack. It
writes the quota-charge fields late, then loads/copies the record to its final
array slot. The problem is the address-exposed aggregate and its write/read
dependency, not an allocation of a MoonBit object for each logical entry.

The repair receives the registration in a separate pointer and assigns that
pointer to the pending record after successful registration. This leaves all
validation, allocation, payload copying, root binding, quota values, publication
order and failure cleanup intact. `gc_heap_register_parked_roots` publishes no
registration on failure; it frees its partial allocations before returning.

`compiler-proof.json`, the two `*-exact-append.ll` files and `*-exact.asm`
are compiled from the exact pre-change and final production C sources:

| Generated constructor | Before | Final |
| --- | --- | --- |
| Aggregate stack allocation | One 40-byte record | None |
| Pointer output stack allocations | One | Two |
| Fixed 40-byte publication memcpy in LLVM IR | Present | Absent |
| AArch64 frame | 160 bytes | 128 bytes |

Variable-sized payload copying remains necessary and remains present. This is
not a claim that the function has no stack traffic or no memory copies.

## Controls separating causes

All measured batches run serially, with two discarded warmups and 21 shuffled
paired rounds, seed 637. No build, tests, debugger, profiler or other benchmark
runs concurrently. Guest clock errors and iteration counts are checked. Timing
excludes compilation, startup and final teardown. Counter intervals include the
fixed boundary-call envelope. CPU frequency and core residency are not pinned.
Bootstrap intervals describe these local batches, not every supported machine.

1. **Actual operation counts.** The archived LLDB breakpoint logs show ten
   insert callbacks and ten native appends for ten captures, with no repeated
   layout-cache miss or lookup. Ten rethrows perform ten lookups and only one
   initial capture, which precedes timing. Debugger times are not measurements.
2. **One function, one address, unchanged frame.** The `same-site-control.patch`
   diagnostic conditionally omits only redundant late zero-charge writes in
   the unmetered case. Nonzero charges still take the original writes; the
   whole operation and ordinary guest assertions remain enabled. Both modes
   use the same native function and 160-byte frame. Paired median cycle changes
   are -4.84% [-7.98, -3.08] for empty capture and -4.76% [-6.28, -3.40] for i64;
   rethrow is -0.02% [-2.30, +2.23]. Thus differing function placement or shorter
   register lifetimes alone cannot explain this effect.
3. **Minimal repair, complete operations.** `minimal-control.patch` compiles
   original and repaired constructors into one executable, retaining the same
   managed state and caller. Paired median cycle changes are -9.16%
   [-10.36, -6.31] and -7.82% [-8.65, -5.54]; rethrow is +0.41% [-0.61, +2.09].
   The independent LLVM proof establishes which materialization disappeared.
4. **Placement sensitivity.** A historical expanded candidate changed only
   construction, yet separate builds moved rethrow timings. A diagnostic
   order file fixes 50 common function addresses; aligning libc stubs removes
   their residual displacement. Nine hot rethrow helpers then have identical
   instructions and addresses. The successful lookup path is also identical;
   its bounds-panic call target alone differs. `aligned-hot-code.json` therefore
   reports `false` for the *whole* lookup body, not a successful-path difference.
   The aligned rethrow cycle interval is [-1.32, +2.45]%, and the many-identity
   interval [-1.70, +2.64]%. These diagnostic linker controls are not in production.

The diagnostic JSON retained historical generic labels: `empty_fast` in the
minimal-control file means the independent output variable for **all** payload
sizes. In the same-site file it means redundant-zero-write omission. That file's
generic `method` text incorrectly says distinct constructors; its archived patch
establishes that both modes execute the **same** constructor. Neither diagnostic
mode exists in the final runtime. The aligned `candidate` is the rejected
expanded candidate, not the final minimal implementation.

No cache-miss, branch-miss or store-forwarding event counter was collected. The
IR, disassembly and same-site control establish the avoidable memory dependency;
they do not identify the processor's exact stall mechanism or apportion every
saved cycle to one hardware event. Volatile scalar copies did not fix the
problem. Earlier capacity and minimal-callback experiments also do not justify
calling the entire difference an allocation problem or pure FFI overhead.

## Final normal release measurements

The normal `./install.sh` build was completed before freezing the final binary.
`final-cli.json` uses those executables directly, without interposition or
diagnostic relinking. The old C comparator includes the matching last-root
counter and private context-factory layout repair; its source patch is in the
preceding investigation. It is not the unsafe pre-repair baseline.

Thread CPU medians, milliseconds; the percentage is the ratio of medians:

| CLI workload | Pre-fix migration | Final minimal repair | Matched old C | Final vs pre-fix |
| --- | ---: | ---: | ---: | ---: |
| 300k empty captures | 32.741 | 28.292 | 27.306 | -13.6% |
| 300k i64 captures | 54.421 | 50.522 | 49.231 | -7.2% |
| 2M rethrows, one identity | 179.011 | 173.097 | 175.151 | See placement control |
| 2M rethrows, 4096 identities | 176.926 | 173.838 | 205.180 | See placement control |

Do not credit a constructor change with improving the timed rethrow algorithm.
The many-identity lookup advantage over old C predates this repair: the managed
implementation validates a constant-time ID estimate before its binary fallback,
whereas old C always searches. A one-entry rethrow has about 23 extra retired
instructions per iteration versus old C, while many-entry lookup avoids enough
search instructions to win. No single-entry special case is introduced.

`final-cli-counters.json` independently samples `proc_pid_rusage` V4 instructions
and cycles at the guest thread-clock boundaries using a child-only dyld interpose
library. Its paired cycle intervals also exclude zero for both capture workloads.
The interpose library changes no production source or persistent environment.
`counters-probe.c` calibrates the counter against a known volatile loop; the
unsuccessful Xcode CPU Counters trace is not used as evidence.

## Store path and residual work

CLI `run` uses a lazy standalone, untraced arena for these fixtures, with an
unknown-tag conservative mask. Store-bound WAST registers the owned instance,
enables tracing and supplies a known tag layout. The observer logs establish
the actual values: Store empty capture has an immortal empty mask; Store i64
has a counted one-element mask. The old CLI mask-RC experiment therefore did
not measure the dynamically owned Store mask and cannot be generalized to it.

`final-store-counters.json` measures the strict JIT WAST pipeline, with normal
release executables. The supplied WAST fixtures check the final result and have
no skips. Two `spectest.print_char` calls delimit the region; the child-only
`putchar` interposer counts calls, ignoring their C argument. Exactly two calls
are required. The independent character-routing bug is tracked in ISS-640;
these fixtures do not claim to validate that builtin's argument routing.

| Store workload | Pre-fix, ms | Final, ms | Matched old C, ms |
| --- | ---: | ---: | ---: |
| 300k empty captures | 42.167 | 37.611 | 37.982 |
| 300k i64 captures | 53.000 | 48.849 | 48.281 |

Final versus pre-fix paired median CPU changes are -11.01% [-11.68, -9.75]
and -8.24% [-9.20, -5.73]. Do not pool absolute CLI and Store times: the WAST
runner uses its strict JIT compilation path and adds native boundary calls.

There is still small residual work relative to C, rather than a claim of zero
overhead. In the uninstrumented CLI batch final empty/i64 medians are 3.6%/2.6%
above matched C. Store medians are -1.0%/+1.2%; paired Store empty differences
include zero. Paired i64 Store change is +0.68% [+0.13, +1.57]. Ratios of
medians and medians of paired ratios are different statistics; all raw samples
and the calculation are retained.

The remaining concrete path differences are visible in generated code:

- One synchronous borrowed managed callback handles insertion, followed by one
  physical-construction call. The native bridge retains state **once**, not
  once per insertion. A callback request does not outlive the native call.
- Known nonempty masks have an owned temporary retain/release around the
  borrowed physical call. The CLI empty mask is immortal; removing that RC
  branch cannot remove its capture cost.
- Logical ID/liveness metadata is published into a MoonBit Array, followed by
  the ID increment, separately from native physical publication. It writes
  16 bytes plus the 40-byte native record: the same combined 56 bytes as old C,
  with two owners/publication locations and extra bounds/state accesses.
- The native record remains physically indexed; no second C identity registry
  or logical lookup was added. Full ID/liveness validation remains authoritative.

The final counter batches show approximately 58–66 additional retired
instructions per capture versus matched C, depending on the path and payload.
These are the complete-path differences, not a per-FFI-call estimate. Earlier
publication ablations locate measurable work in the extra numeric publication,
but deliberately incomplete ablations cannot be added up to explain every
remaining nanosecond. Exact hardware-stall attribution is not established.

The maintainability decision is to keep the simple, validated ownership boundary
and the small compiler-friendly repair. Expanded leaf fast paths, a cleanup
split, `noinline`, volatile operations, register-lifetime tricks and production
linker ordering are not retained. There is no evidence that a new data structure,
moving policy back into C or adding another native registry is warranted.

## Validation and provenance

- `moon info`, `moon fmt`, strict native check with warning 73 enabled: pass.
- Native tests: 2735/2735. Strict C: 43 stubs, warnings denied.
- Fresh macOS ASan/UBSan: 173/173; both ASan positive controls detected.
  Linux leak detection is not available in this local run; `leak_detection=false`.
  MoonBit runtime objects and JIT code remain documented instrumentation exclusions.
- Core: 258 files / 62563 assertions per engine, all pass.
- Component JIT: 59 files / 1385 commands across all three suites, no skips.
- Added a public regression for empty payloads across growth, root/tracing modes,
  budget failure rollback, repeated release, monotonic reuse and terminal clear.
  Omitting the registration assignment fails that regression; restored source passes.
- The sanitizer's copied exception sources match the final production sources.
  The root CLI and frozen measured final binary have the same SHA-256.

`source-manifest.json` records source/binary hashes and the dirty source base.
The historical receipts remain historical. This batch does not repeat unrelated
WASI HTTP or script tests, and does not close ISS-637's platform acceptance.

To repeat the ordinary release comparison, rebuild with `./install.sh`, freeze
each executable outside its build directory, and run the earlier `benchmark.py`
with `--rounds 21` and named `before=... fixed=... matched_c=...` arguments.
Compiler-proof commands are recorded in `compiler-proof.json`; append
`-S -emit-llvm SOURCE -o OUTPUT` to emit IR, or `-c SOURCE -o OUTPUT` then
`otool -tvV OUTPUT` for assembly. `summarize.py` only recomputes statistics
from the archived samples. Diagnostic build commands are historical local
receipts, with absolute source/build paths; do not run them against a different
generated MoonBit caller or silently substitute current sources for the frozen
pre-change inputs.
