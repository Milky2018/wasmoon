# Exception performance investigation: local evidence

This is the dirty macOS ARM64 working tree after `d9279052`. Nothing in this
receipt is a commit, push, CI result or platform acceptance. It supersedes the
performance implementation in [the first registry migration](../exception-registry-2026-10-16/README.md),
whose source manifest and measurements remain historical and unchanged.

## Findings and scope

The first migration introduced a real execution regression. The earlier short
CLI benchmark included startup, compilation and teardown; its reported 15%
capture overhead did not measure the loop itself. Isolating execution shows
much larger degradation, especially as the registry grows. This follow-up
repairs most of that regression, **not all of it**.

The initial state used an ordered `Map[Int64, ExceptionEntry]`, a managed entry
object and an RC external payload owner per snapshot. That changed a packed C
array into several separately allocated objects per identity. In a partial
107-sample profile, 58 stacks enter `ExceptionState::insert` and 41 descend into
Map insertion/growth, including linked-order reconstruction and RC drops.
This identifies a hot path, not a complete attribution of total runtime. The
old C binary exited before its sampler captured a stack, so it provides no
valid comparison profile. The raw migrated profile is retained here.

Repeated rethrow added integer hashing, managed projections and native/managed
calls around each lookup. Current lookup uses the monotonic identity to
estimate a slot, validates the entire identity and live bit, and falls back to
binary search for gaps. Old C lookup itself used binary search. A mutable hint
cache did not help the one-identity workload consistently and was removed.
Assembly also exposed a real extra call between lookup and a shared search
helper despite an inline hint; combining them removes that wrapper.

The resulting state has unboxed numeric metadata and one RC owner for physical
payload storage. There is no managed entry or external owner allocated per
snapshot. On this 64-bit target, each packed logical record is 16 bytes and
its native physical record is 40 bytes, versus the original native record's
56 bytes. These are record sizes, **not** total memory usage: buffers, roots,
allocator headers and capacity slack still exist. Native storage owns buffers,
root leases and quota references; MoonBit owns identity, admission, marks,
retirement and compaction. C does not read MoonBit's private struct layout.

Retirement batches tombstone compaction; all-survivor sweeps preserve capacity
headroom. Both metadata and physical buffers stay bounded by occupancy rather
than the historical number of IDs issued. Failed growth, payload or root
allocation rolls back quotas without publishing an identity. The previously
identified last-root adapter repair remains covered.

## Measurement protocol and results

`benchmark.py` makes 21 serial paired measurements after two warmups per
workload, with binary order shuffled using seed637. The guests check all clock
return codes and their final iteration count. They return both WASIp1 thread
CPU and monotonic nanoseconds around the loop. The table uses thread CPU
medians; full CLI wall times and every raw sample remain in `comparison.json`.
Builds, tests, profilers and other benchmarks did not run concurrently. Other
machine activity and CPU frequency are not pinned; small differences and
cross-batch comparisons should not be treated as universal speedups.

`baseline` is the saved packed C registry binary used in the preceding GC
migration; `before` is the exact binary recorded by the first exception
migration; `fixed` is the freshly installed CLI used by the final corpora.
The old C baseline also predates the last-root lease counter repair and the
private context factory pointer; its residual difference is not a pure language
comparison. The migrated-before and fixed binaries include those same safety
changes. All digests are saved. The final source manifest verifies the measured CLI
matches the current CLI and every copied sanitizer source matches this tree.

| Workload / iterations | Old C, ms | Migration before fix, ms | Fixed, ms | vs migration | vs old C |
| --- | ---: | ---: | ---: | ---: | ---: |
| snapshots / 20,000 | 2.09 | 3.57 | 2.46 | -31.3% | +17.4% |
| snapshots / 100,000 | 10.70 | 21.27 | 12.51 | -41.2% | +17.0% |
| snapshots / 300,000 | 30.30 | 59.41 | 35.28 | -40.6% | +16.4% |
| snapshots-word / 300,000 | 52.68 | 82.69 | 58.80 | -28.9% | +11.6% |
| rethrow / 200,000 | 18.54 | 19.32 | 18.95 | -1.9% | +2.2% |
| rethrow / 2,000,000 | 195.36 | 205.54 | 198.78 | -3.3% | +1.8% |

The 300k empty-snapshot case improves about 41% over the migration, but still
costs about 16% more than old C. With one i64 payload, the residual is about
12%. Two million rethrows improve about 3%, with about 2% residual overhead.
Small-loop results are noisier.

`rethrow-many-comparison.json` adds the same rethrow loop after creating 4096
snapshots before timing. It reuses and resets the existing loop local so that
adding a seed counter does not increase spill/frame size. The 2M-rethrow CPU
medians are old C 217.93ms, migrated 197.19ms and fixed 190.72ms: 3.3% faster
than the migration and 12.5% faster than historical C. This case benefits from
avoiding the old C registry's repeated binary search. Its samples are a separate
paired batch; do not subtract its absolute times from the single-entry batch.
The benchmark driver includes this case and supports `--workload rethrow-many`.
 Repeated earlier batches are saved as
intermediate records, with their original labels and binary digests; they are
not relabeled as measurements of the final source.

The unrelated 2M struct-allocation control checks its result sum and records
11 paired serial **whole CLI wall** samples separately in `word-control.json`:
135.98ms old C versus 136.92ms fixed (+0.7%). This is a separate timing metric,
not guest CPU time and not evidence of an ordinary-workload speedup.

To repeat with saved comparison executables on a platform supporting the
thread CPU clock:

```sh
python3 docs/evidence/exception-performance-2026-10-16/benchmark.py \
  --rounds 21 --output target/exception-performance.json \
  baseline=/path/to/old-cli before=/path/to/migrated-cli fixed=./wasmoon
```

## Rejected experiments and attribution limits

- Replacing the ordered Map with the official HashMap alone was insufficient.
  Packed metadata plus removing per-snapshot ownership allocations produced
  the substantial improvement. Individual percentages cannot be assigned to
  each subchange from differently laid-out executables.
- A same-executable intermediate ablation separately disables the tag cache,
  lookup hint or accounting. Its source patch and digests are retained.
  Disabling accounting is strictly a diagnostic control, never a production
  option. It did not establish accounting as the dominant cost. The hint
  showed no stable benefit in a single-identity registry. Layout caching
  avoids repeated map lookup; small timing differences remain noisy.
- A borrowed tag-mask view removed hot RC instructions but made measured
  performance worse, including the unchanged rethrow workload. It was
  reverted. Its typed FFI view and additional cache state are absent from the
  final source. Fewer RC instructions alone do not prove a speedup.
- Adding an inline hint did not reliably remove the native call. Assembly,
  rather than annotation text, exposed the remaining helper call.
- `excluded-during-build.json` is marked invalid: it ran during a build and
  mislabeled a preceding binary. It is excluded from all conclusions.

The remaining snapshot cost is real in these measurements. A further
same-executable control reserves 524288 records before invocation (the Store
constructs its `NativeExecutionState` before running the guest). For 300k empty
snapshots, thread CPU medians are 33.21ms normally, 32.93ms with metadata
reserved, 34.51ms with native storage reserved and 33.12ms with both reserved.
The rethrow negative control is 185.92ms normally versus 185.66ms with both
reserved. Up-front capacity reservation does not materially fix this case;
these results do not justify adding large initial reservations or segmented
storage. They do not establish that growth is free in every workload.

The same diagnostic executable repeats the **entire validated lookup** one,
two or four times per rethrow, preserving every identity/liveness check. The
2M-rethrow medians are 185.92ms, 195.42ms and 201.73ms. Extra lookup costs inferred
from these differences are roughly 2.6–4.7ns per call including the repetition
loop. This is not a pure FFI measurement or a subtraction of the old C lookup
cost, which was nonzero. It supports treating lookup as a small constant cost,
not attributing the complete remaining snapshot difference to FFI alone.
The raw samples and exact diagnostic patch/source digests are retained. No
capacity/repetition controls are present in production.

Further snapshot tuning must isolate the remaining synchronous insertion and
storage-access costs before changing ownership. A second native identity
registry would undo the single-owner design. The rejected borrowed-view
experiment and the ineffective reserve controls are concrete reasons to avoid
another unmeasured view, cache or storage abstraction.

## Correctness and limits

- Native **2734/2734**, including malformed/stale handles, sparse identity gaps,
  per-heap GC after unordered release, bounded retirement churn, capacity
  headroom, tag-cache invalidation, quotas, allocation rollback and reuse.
- Strict native MoonBit checking passes with warning73 and warnings denied;
  **43 native C stubs** compile with warnings denied. Platform-empty archive
  members still generate the existing macOS libtool notices.
- Fresh ASan/UBSan **173/173**, event-loop fixture and both independent ASan
  positive controls pass. Copied sources match. **macOS LSan is disabled**;
  this is not Linux leak acceptance or Windows Clang/MSVC validation.
- Core: **258 files / 62563 assertions per engine**.
- Component, both engines: stable **23 files / 845 commands**, async **24 / 153**,
  future **12 / 387**; no skipped commands.
- WASI03 HTTP-contract **110/110**, with the exact CLI digest in its receipt.
- Script tests **172**, with **54 platform skips**; module boundary and generated
  MSVC bridge checks pass.

Two targeted mutations establish meaningful tests. Removing compaction fails
both bounded-storage and sparse-slot expectations. Removing full identity
validation accepts a malformed even token as slot26. After restoring the
source, all three white-box registry tests pass again. The public behavior
regressions and isolated sanitizer tests cover the ownership consequences;
private capacity/slot properties require white-box observation.

ISS-637 remains in progress for platform acceptance and residual exception
performance. Continuation migration, ISS-634's upstream build repair, toolchain
changes and publication are outside this performance slice.
