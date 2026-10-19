# Exception insertion cost investigation

Local macOS ARM64 investigation of the dirty working tree after `d9279052`.
This supplements the [previous performance report](../exception-performance-2026-10-16/README.md).
No new runtime optimization survived this investigation. Every temporary probe
and candidate is removed from production; source and CLI restoration are checked
in `source-manifest.json`. This is neither CI nor Windows/Linux acceptance.

## What the evidence establishes

The remaining gap is reproducible against a C baseline with the new heap-root
lease counter and private context factory layout. Those safety changes explain
only a small part of the historical difference. In a fresh 21-pair batch,
300k empty snapshots cost 28.93ms in matched C versus 33.94ms in the current
implementation; i64 snapshots cost 50.67ms versus 55.61ms. Two million rethrows
cost 183.52ms versus 190.72ms; with 4096 pre-created identities current lookup
is faster, 195.17ms versus 224.39ms. See `matched-baseline.json`. These are guest
thread CPU medians, not startup-inclusive CLI wall times.

There is no longer an allocation per logical entry or an RC payload wrapper
per entry. Each snapshot appends 16 bytes of unboxed MoonBit metadata and 40
bytes of native physical storage. Historical C appended one 56-byte record.
The new path has two publication locations and additional dependent accesses,
not an increase in the combined record bytes. Native payload/root allocations
remain real costs in both implementations. Default unbound quotas do not run
the atomic admission operations.

The path is native capture -> borrowed managed callback -> validation/layout
cache/admission -> native payload construction -> managed numeric publication.
The adapter retains state once. The callback does not increment/decrement state
per invocation; its stack request never escapes. Generated code does increment
and decrement the temporary owned mask around the borrowed FFI argument.

The insert assembly has a 64-byte managed frame, and the native append function
has a 160-byte frame on this target. Native append saves registers across
allocation/root calls and copies its 40-byte temporary into the physical array.
Managed publication loads the Array owner, its buffer, length and capacity,
writes a 16-byte numeric entry, then updates length and the next identity. These
are observable instructions, not a hardware cache-miss measurement.

## Matched request and callback controls

An isolated harness performs 300k native insertions, verifies the last snapshot
outside timing, and separately selects no heap/real heap and empty/i64 payload.
`probes.json` records 21 shuffled serial pairs after two warmups:

| Insertion | Matched C, ms | Current, ms | Difference per insert, ns |
| --- | ---: | ---: | ---: |
| Empty, no heap | 2.70 | 5.32 | 8.72 |
| Empty, root lease | 10.73 | 15.53 | 16.00 |
| i64, no heap | 6.00 | 9.65 | 12.16 |
| i64, root lease | 14.75 | 19.18 | 14.75 |

The historical arena handle is an RC wrapper around a pointer, whereas the new
bridge is itself the external object. The first preliminary old-C harness
mistakenly treated the wrapper as the arena and aborted. That run is discarded;
the measured harness unwraps it **before** timing. It was a harness defect,
not a runtime failure. Neither test execution time nor these per-insert values
should be subtracted from a different benchmark batch.

A second, single-executable diagnostic separates operations. `decomposition.patch`
is relative to the restored sources identified by the manifest. Its modes are
intentionally incomplete operations, **not valid runtime alternatives**:

- Normal insertion retains validation, identity advancement, logical publication,
  physical append and ordinary post-timing snapshot verification.
- Direct physical append uses synthetic monotonic IDs and verifies native count,
  tag and payload outside timing; it omits managed registry policy.
- Managed-only insertion makes physical append return success without allocating.
- Minimal C and managed callbacks have the same signature and compute `tag+count`.
  The native caller still constructs and validates a borrowed request.
- No logical publication omits only `entries.push`; identity advancement and
  physical append remain. No lookup is attempted on this incomplete registry.

The skipped-operation modes have no ordinary snapshot assertion and never run a
GC traversal. They exist only to locate costs. All assertions remain enabled for
normal runtime modes. A real MoonBit array, constructed before timing and dropped
after timing, supplies the direct-append mask.

From `decomposition-metadata.json`, medians converted to ns per insertion:

| Operation | Empty, no heap | Empty, lease | i64, no heap | i64, lease |
| --- | ---: | ---: | ---: | ---: |
| Complete | 10.44 | 36.90 | 21.86 | 49.83 |
| Physical construction only | 4.66 | 31.42 | 15.97 | 43.79 |
| Managed policy/publication, physical append suppressed | 7.89 | 8.84 | 8.60 | 7.52 |
| Complete except logical publication | 9.12 | 34.53 | 18.95 | 46.72 |
| Minimal managed callback | 0.99 | 0.99 | 0.99 | 0.99 |
| Minimal C callback | 0.99 | 0.99 | 0.99 | 0.99 |

This rejects a large intrinsic penalty for a managed `FuncRef` call with borrowed
state. The work performed by the callback matters. Omitting logical publication
removes approximately 1.3-3.1ns in this batch, including growth/length work; the
rest of the difference between physical-only and complete includes validation,
mask lifetime, request passing and state preserved across native construction.
Do not sum the rows: inlining, live registers, allocator behavior and memory
access overlap differ between these controls. In particular, this instrumented
binary's absolute timings differ from the separate isolated-pair batch. Neither
is a measurement of pure call latency in the production JIT path.

## Rejected optimizations

`controls.json` tests three independently selectable changes in **one CLI binary**:
borrowed mask view instead of a temporary owned mask; direct construction in the
uncommitted native slot instead of a stack copy; direct storage pointer in the
request instead of `request -> arena -> storage`. All eight combinations retain
normal validation/admission and guest checks. Across 21 shuffled rounds their
small changes are inconsistent across empty/i64 capture and the rethrow negative
control. None explains or reliably removes the residual gap. No view, flag or
extra request field remains in production. The earlier capacity-reservation
controls are documented in the preceding report; this investigation does not
reinterpret them as a growth fix.

Moving quota acquisition and rollback into small managed helpers shrinks insert
assembly from roughly 1KiB to roughly 0.5KiB, but keeps its 64-byte frame. Two
separate-binary batches suggested a 3-4% empty-capture gain and less than 1% i64
gain. A same-binary control with the same State layout and entry wrapper does not
establish that gain. Per-round paired median CPU changes and descriptive 95%
bootstrap intervals (`quota-paired-summary.json`, positive means slower) are:

| Workload | Paired median | Interval |
| --- | ---: | ---: |
| Empty snapshots | +1.18% | -2.95% to +2.76% |
| i64 snapshots | -0.46% | -2.86% to +0.77% |
| Rethrow negative control | -0.73% | -2.08% to +0.38% |

All intervals include zero. Ratios of separate medians can even point in a
different direction from the median of paired ratios; reporting the former alone
would overstate this candidate. The helpers are reverted rather than adding an
unproven optimization.

## Limits and decision

The evidence locates additional **work** in managed validation/publication and
preserving state across physical construction. It does not assign every remaining
nanosecond between instruction scheduling, stack traffic, cache misses and code
placement. Minimal callbacks and incomplete-operation ablations do not establish
that the entire production guest gap is the sum of those costs. A 30M-snapshot
profile captured stacks in both binaries; dynamic JIT frames are unresolved and
sampling attribution around epilogues is coarse. Five-million-snapshot preliminary
profiles completed before sampling and contain no comparative stack evidence;
they are not used.

Do not claim the remaining regression is fixed, or move identities/admission back
into C to make the old monolithic implementation easier to inline. Likewise, do
not add a shared private MoonBit/C struct layout, bit-packed ownership protocol,
or two-phase publication solely on these small measurements. A further structural
optimization needs a representative, semantically complete same-executable test
showing a stable gain and preserving failure rollback/GC before it is retained.
ISS-637 remains in progress. The known remaining gap and missing exact hardware
attribution are explicit, rather than presented as a completed optimization.

## Reproduction and artifact identity

All measured loops run serially, with two warmups, 21 measured rounds and shuffled
order (seed637). Builds, tests and profilers run separately from timings. CPU
frequency, scheduling and unrelated machine load are not pinned. Binary hashes,
raw samples and guest clock values are retained; different batches are not pooled.
The CLI fixture/driver remains in the preceding report directory.

`storage-controls.patch`, `quota-controls.patch`, and `decomposition.patch` are
independent temporary instrumentation patches, not cumulative patches or changes
to apply to production. The first two apply to the restored working-tree source
hashes in the manifest. The third also adds a temporary whitebox harness. Its
`run-decomposition-metadata.py` runner expects that native release test executable
under `target/exception-insert/decomposition-build`. The other runners similarly
refer to their ignored build directories. `run-probes.py` expects an old-C and a
current harness; its implementation is the ordinary insertion branch of the
same probe helper, with the old wrapper unwrapped before timing.

`matched-c-baseline.patch` applies to an independent archive of `d9279052`, not
the dirty migrated tree. It adds the same heap counter/factory layout and removes
the old arena's premature borrowed-pointer clears. It is a diagnostic comparator,
not a replacement for current ownership. Baseline/diagnostic source and executables
remain under the ignored target directory; the receipts retain their hashes.

After removing every temporary source probe, the current C and MoonBit exception
files match their pre-investigation backups byte for byte, and the installed CLI
matches the original measured binary. No new code or binary is delivered by this
follow-up. Fresh local checks after restoration are recorded in `validation.json`.
