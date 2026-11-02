# Checked object views and native root links

Tracking: [ISS-721](../../issues/ISS-721.md) and
[ISS-722](../../issues/ISS-722.md).

## Native root ownership

The precise root set, definition stores, mask publication and stack-owned
32-byte frame are unchanged. An optional `InlineFunctionRootFrameLayout`
lets an embedding describe its execution pointer, current-invocation admission
word and function-frame head. Existing providers retain the complete helpers.

Wasmoon uses the existing `poll_controls` ownership word: push/attach publishes
it for the current activation, while nesting, parking and detachment withdraw
it from non-current activations. Generated entry code checks the environment,
execution and admission word before linking the same complete frame. Return
code additionally checks that the frame is the chain head. Every refusal uses
the original helper, including its trap and active-context resolution.

The source body's entry is distinct from this optional native prologue. Source
entry edges cannot re-enter the frame-link sequence. Calls, reentry, suspended
stacks, exception markers and cleanup continue to use the same frame chain.
No root is omitted or postponed, and no polling budget or callback changes.

## Object admission and invalidation

The heap keeps sixteen directly indexed, non-root hints for each object kind.
Each struct key contains the complete reference, canonical identity, prefix shape and field
span already accepted by the checked accessor. A reference-specific retirement
invalidates its matching entry. Payload movement, collection, rollback and other
existing global invalidation boundaries clear every entry. The verifier checks
every occupied entry; closing releases the entire heap-owned cache.

Array hints retain the complete reference and existing width-tagged opaque
view. A generated hit handles only the nontrapping, width-neutral metadata
projection. Actual accesses retain their null, bounds, width and checked
fallback behavior. Array hints share every existing invalidation boundary;
the verifier checks all occupied entries of both kinds.

`StructViewLayout` and `ArrayViewLayout` are additive, optional embedding
capabilities. Existing `InlineHeapLayout` constructors keep their original fields. The descriptor is
immutable and contains no shared mutable arrays. Generated hits repeat the
complete admitted key and read the current context's canonical mapping. Misses,
foreign nominal types, legacy layouts and mandatory verification retain the
same checked accessor. Physical borrow verification and address epochs remain
independent of these hints.

Expansion is limited to at most eight natural-loop sites per kind in functions
with 2..64 blocks, within the existing lowering budget. Leaf getters and larger
functions keep the shared accessor. Codegen revision 34 rejects older cached
code whose heap offsets or register assignments no longer match. Package
versions and VMContext ABI version are unchanged.

## Regression controls

An independent control disables the root-link opt-in and makes the call-free
path regression fail. Reversing the generated nominal-identity guard makes a
cached, equal-width foreign object enter a typed loop and fails the public
regression. Clearing only one hint makes the multi-object compaction/growth
regression fail. Restoring each implementation passes its original test.
Reversing the array reference guard changes the alternating loop's result from
48 to 36. Clearing only the first array hint fails its compaction regression.
Both controls use fresh independent builds, then pass after restoration.

The shared ordinary/sanitizer fixtures cover O0/O2/O3, twenty admitted objects,
compaction, payload growth and foreign nominal layouts. Existing subtype,
legacy, rollback, root snapshot, reentry, exception, continuation, cancellation,
quota, barrier and independent borrow regressions remain required.
Array fixtures additionally alternate colliding reference keys, prewarm a
separate leaf accessor and observe writes without retaining stale values.

## Measurement scope

These experiments freeze MoonBit SDK 20261028, unchanged downstream `ed848ac5`,
and the SDK's original generated Wasm. The official driver executes 8,384
synchronous tests; another 200 async selections have no execution in that Wasm
driver. This is a new matched dataset. Earlier SDK23 results for 7,971 tests and
the historical 13.42x ratio retain their original scope.

Each hot-module experiment keeps one separate warmup and five measured samples
per engine, rotates case/engine order and reverses order between rounds. Every
process compiles afresh, every sample and outlier is retained, and no build,
profiler or other benchmark runs during retained timing.

| Independent candidate | strconv | vector | edit-distance | sorted-map |
| --- | ---: | ---: | ---: | ---: |
| Current-invocation root links | -2.73% | -7.83% | -7.27% | -7.85% |
| Shared sixteen-entry cache | -0.05% | -2.22% | -19.01% | -4.75% |
| Cache plus unrestricted bounded hit expansion | -1.66% | -1.11% | -20.77% | -3.68% |

Cells are median paired whole-process wall changes against clean `4d486bb3`,
not ratios of separate medians. Root links improve all twenty pairs. Cache
results for strconv are mixed. Hit expansion includes +14.52%, +7.95% and
+13.62% slow samples; they remain in the dataset. Incremental gains must not be
summed to predict the combination.

A single complete serial screen (`moon test --target wasm-gc -j 1`) passes all
8,384 tests in each variant: official SDK28 19.713466 s, parent 253.287638 s,
root links plus shared cache 237.443934 s, plus unrestricted bounded hit
expansion 237.803562 s, and plus loop-only hit expansion 233.567269 s. This
screen selects a candidate; it is not an independent paired improvement
estimate. Final exact-head confirmation is recorded in PR #582.

Compiler diagnostics on the unchanged 10,662-function builtin input report
11,961,176 emitted bytes for the parent, 13,143,260 with root links plus the
shared cache, 14,024,040 with unrestricted bounded hit expansion and 13,306,792
with loop-only hit expansion. These deterministic code sizes explain why cold
cost belongs in the decision. Instrumented phase durations are diagnostic and
are not retained timing estimates.

After these root/struct changes, independent count-only instrumentation records
zero common-path root-frame helper calls in all four original hot modules.
Struct projection calls change from 570.6M/483.3M/539.4M/443.4M to
207.6M/409.4M/538.5M/409.0M; complete-check misses change from
133.4M/335.5M/371.5M/349.6M to 61.1M/210.4M/13.5M/187.3M. Instrumented
elapsed time is excluded. Root definition stores and masks remain intact.

Post-compiler sampling of that uninstrumented candidate attributes
572/4000, 719/4548, 543/2366 and 25/3187 main-thread leaf samples to the
remaining array projection helper. Installation can overlap this diagnostic
window; these are sample proportions, not whole-program time estimates.

A separate array experiment compares the root/struct control, sixteen array
hints, and those hints plus bounded loop hits. One warmup and five retained
samples per case/engine use the same original Wasm and assertions. The
predeclared threshold requires at least 2% geometric gain across case medians,
no case median regression above 1%, and another 1% incremental geometric gain
for generated hits. Independent final aggregate confirmation remains required.

| Array extension relative to root/struct control | strconv | vector | edit-distance | sorted-map |
| --- | ---: | ---: | ---: | ---: |
| Shared sixteen-entry array cache | -1.07% | -4.72% | -10.22% | +0.09% |
| Cache plus bounded loop hits | -4.12% | -6.72% | -11.51% | +0.50% |

Both candidates meet the hot-module threshold. Generated hits add a 1.61%
geometric gain over cache alone across these case medians. All five sorted-map
hit samples regress, including +1.01%; none is filtered. All 72 processes
preserve the original assertions and fresh empty caches. These incremental
effects are not summed with the preceding root/struct results.

Whole-process time includes startup, compilation, verification, preparation,
execution, GC, scheduling and teardown. `-j 1` serializes test executables; V8's
internal defaults are unchanged. These results establish no universal speedup,
pure guest-execution ratio or peak-memory improvement, and do not resolve the
remaining overall gap to the official runtime.

## Cross-target operand repair

The initial cd0b6ee3 Linux and Windows runs found an x64 allocation-verification failure
in the existing large sparse-mask regression. Its repeated-store instruction
had a Late address reload and an Early temporary assigned the same natural
register. The reload occurs before the whole instruction, so the local
assignments violate the declared phase contract. The same input reproduces by
cross-compilation on AArch64, beginning at 255 reference parameters.

Local assignment now repairs this overlap while preserving fixed/tied
readers, valid split regions and the complete allocation verifier. The
regression compiles both targets at O0/O2/O3. The original failing native
fixture and all existing allocator assertions remain intact. A broader gap
restriction was rejected after exposing an existing valid allocation that
could no longer obtain a register. Codegen34 separates changed allocation
decisions from revision33 caches. Interrupted revision33 aggregate timings
have no final performance conclusion; final measurements use the repaired
allocator in both the complete candidate and its root/struct control.
