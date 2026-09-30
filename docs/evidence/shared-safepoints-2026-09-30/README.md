# Shared safepoint metadata

This change follows the module-shaped layout implementation in the same working
tree. The immediate baseline binary was copied before editing to
`/tmp/wasmoon-safepoint-before/wasmoon`; it is the candidate measured in
[the previous report](../module-context-layout-2026-09-30/README.md), not a fresh
build of b141554a. Neither candidate is claimed to be a committed revision.
All execution measurements are local macOS ARM64.

## Implementation and boundaries

Empty metadata on an unallocated context succeeds without allocating the dense
native table. Rebinding an existing entry to empty still releases its payloads.
The native facade prepares immutable payloads once per LoadedArtifact; contexts
retain one shared descriptor owner via MoonBit RC. The descriptor owner is a
managed opaque type with a C finalizer, not a C-side reference-counting system.
Mutable input offset arrays are snapshotted. Descriptors and payloads remain at
stable addresses, and context destruction releases the retained owner.

The portable artifact/loader package remains free of native ownership. The root
facade LoadedArtifact now wraps that verified value and its prepared metadata;
`loaded.verified()` supplies the portable value to JitCodeInstaller::install.
This is an API type boundary change for callers that previously passed the root
facade value directly into the portable installer. Existing facade inspection
methods and load_artifact's optional decode limits remain available.

Per-function compatibility setters copy shared descriptors to a private owner
before mutation, retaining their payloads. Metadata binding requires that the
target context has no active or suspended execution. Another context may remain
parked and continue using the original immutable owner. Invocation owners retain
their contexts; this change does not alter that lifetime protocol.

The table ends at the last function with metadata, and no owner is prepared for
an entirely empty set. Artifact function indices that cannot form a nonnegative
signed extent are rejected before native preparation. Generated code and
persisted artifact encoding are unchanged by this stage.

## Allocation accounting

The private context remains 216 bytes. The target here is metadata beyond it.
The existing native descriptor is 32 bytes on this platform. Previously each
context allocated F descriptors, even for an all-empty set with defined functions.
Now an all-empty set has no descriptor allocation. Nonempty sets share one owner
per loaded artifact; let H be the highest metadata-bearing function index + 1.

The shared owner requests `32*H + 24` bytes including its two Int32 control fields,
MoonBit's 8-byte RC header and 8-byte finalizer pointer. The new native facade
wrapper requests another 24 bytes (two pointers and an RC header). These figures
exclude allocator rounding and unchanged context/resource/code storage.

| F=1,000 (H=1,000 in nonempty examples) | Before | After | Scope |
| --- | ---: | ---: | --- |
| One instance, no safepoints | 32,000 B | 24 B | Descriptor storage plus new facade wrapper |
| Ten instances sharing one loaded artifact, no safepoints | 320,000 B | 24 B | Same scope |
| One instance, nonempty safepoints | 32,000 B | 32,048 B | Descriptor storage plus new shared owner/wrapper |
| Ten instances sharing one loaded artifact, nonempty safepoints | 320,000 B | 32,048 B | Same scope |

Nonempty blob/offset payloads are additionally shared rather than regenerated
for each context. Their size depends on actual safepoints and is not included
in the table. Compatibility rebinding intentionally creates a private copy;
the multi-instance saving assumes the normal immutable artifact path. A
zero-function artifact previously had no descriptor table and now adds the
24-byte facade wrapper. This is not a claim that every single-instance workload
uses less total memory.

Regression tests observe descriptor allocation absence and pointer identity,
including 1,000 empty bindings, invalid context capacity, input mutation,
creator-scope exit, copy-on-write while another activation is parked, resume,
clearing, and finalization under sanitizers. The arithmetic above is allocation
accounting, not a process RSS measurement or an instrumented whole-program heap
profile.

## Validation and timing

Final native tests: 2,630/2,630. Strict MoonBit warning checks and 39 strict C
translation units pass, as do the existing dependency and lifetime audits.
Core WAST passes 258 files / 62,563 assertions per engine; misc passes 692 with
72 script-only entries and no failures/timeouts. Component JIT stable/async/future
pass 845/153/387 commands. P1 capabilities passes 116 with two not applicable.
ASan/UBSan passes 79 tests, event-loop lifecycle and both positive instrumentation
controls. MoonBit runtime objects and JIT-generated instructions are not covered
by that instrumentation. Linux/Windows and remote CI were not run.

Timing uses independent binaries, serial fresh-process cold caches, alternating
paired samples and separate diagnostic runs. All four inputs produce identical
before/after artifact hashes; no artifact-difference override was used. Correctness
work completed before sampling. The final A/B run has 13 pairs per workload and
three diagnostics; A/A has nine pairs and one diagnostic. Negative changes mean
faster. Paired ratios need not equal ratios of separately computed medians.

| Workload | Paired wall-time change | Bootstrap 95% interval | A/A median |
| --- | ---: | ---: | ---: |
| 1,000 leaf functions | +2.54% | [-1.69%, +9.89%] | -0.94% |
| auth | -0.34% | [-0.59%, +2.23%] | -0.14% |
| aead_aegis128l | +0.36% | [+0.07%, +0.66%] | +0.22% |
| sign2 | +0.41% | [-0.10%, +0.55%] | +0.28% |

**No speedup is established. AEGIS has a small positive timing difference in this
run, and an earlier run also measured +0.66%; it is not dismissed as noise.**
A/A uncertainty and machine drift limit attribution; they do not justify
subtracting the A/A median as a correction. Code hashes match, but host binary
and allocator placement can still differ. Diagnostic phases are separate samples
and metadata preparation moved from instance loading to artifact preparation;
comparing only one phase would therefore be misleading. Root cause remains open
in ISS-604. The 1,000-function fixture takes about 7.4 ms and has wide relative
noise; its clear allocation reduction is not a measured latency improvement.

The first benchmark attempt used a void-returning fixture, which the existing
runner rejected for lacking a numeric guest metric despite exit status zero.
Its 28 fixture rows failed harness validation. They are retained in
initial-benchmark.json.gz and excluded from the final result. The corrected
fixture returns constant 1; final benchmark/control have zero failed rows.

Reproduction (after building the compared binaries):

```sh
gzip -dc leaf-1000.wat.gz > /tmp/safepoint-empty-1000.wat
wasm-tools parse /tmp/safepoint-empty-1000.wat -o /tmp/safepoint-empty-1000.wasm
python3 scripts/benchmark_startup.py --before /path/to/before/wasmoon \
  --wasmoon ./wasmoon --output /tmp/safepoint-compare \
  --repetitions 13 --diagnostics 3 /tmp/safepoint-empty-1000.wasm \
  examples/algorithms/auth.wasm examples/algorithms/aead_aegis128l.wasm \
  examples/algorithms/sign2.wasm
```

The binary hashes, input hashes, commands and raw timing/phase rows are retained
in benchmark.json.gz and control.json.gz. source-sha256.json.gz identifies the
candidate sources; baseline-tracked.patch.gz records tracked pre-optimization
changes over b141554a. The earlier layout report records its untracked layout
sources. No remote delivery or clean-worktree claim is made.
