# Unified GC lowering and root transport for #568

This implements the source-grounded design in
[the three-engine comparison](issue568-three-engine-comparison-2026-10-22.md).
The baseline is `c7e407d5686a21dde271a240ca6f5b9a8f20352e`. This is local,
uncommitted macOS ARM64 work, not CI, x64 execution or Linux leak acceptance.
Historical research and intermediate receipts retain their original provenance.

## Compiler and runtime contracts

Wasm semantic effects distinguish logical memory writes from physical-address
invalidation. Unknown extensions, collection, reentry and heap replacement remain
conservative barriers. The semantic dialect rejects native annotations; the
native adapter checks their exact canonical effects and source contracts.

GC-to-memory lowering runs before target selection. A checked struct view admits
the actual Store type and exact width/reference prefix. Typed field offsets are
then ordinary address operations. Array views carry an exact element-width tag;
refinement selects direct numeric accesses only for compatible physical layouts.
Legacy slots, verification, large structs and unsupported vector/reference-array
accesses retain checked adapters. Reference writes retain their barrier.

Generic GVN and LICM use alias-region versions and bounded readable views. A
cheap entry guard permits first-iteration trapping invariants without executing
them on a zero-trip path. The physical-borrow must-analysis independently checks
all CFG paths and backedges and rejects pointer escape or use after invalidation.
This is a lifetime/provenance verifier, not a general proof of arbitrary pointer
bounds. Typed lowering supplies unsigned array checks and checked fallbacks.

Root transport uses a stack-owned function frame, slots and precise safepoint
masks. Stores occur at each root-bearing SSA binding; sibling-path aliases share
a slot but each binding publishes it. Ordinary guest calls update masks instead
of allocating/copying push/pop scopes. Enumeration is shared by active, detached,
parked and rollback paths. Exception handlers restore frame markers; normal and
tail exits unlink frames. This is a compiler-managed function-lifetime shadow frame, not
PC-indexed maps of every final machine register. Explicit low-level scope clients
retain their compatibility API.

Allocation metadata is decoded and validated before artifact publication. Root
selection borrows indexed descriptors; it no longer scans variable-size records
or allocates a selected-root array on successful allocation. Scalar structs use a
shared no-GC C reservation, preserving atomic quotas, identity registration and
failure controls. JIT code initializes header and scalar payload immediately,
with no intervening safepoint. Quota admission is intentionally not duplicated in
machine code. Unsupported allocation and collection/retry use the precise cold
allocator; allocation accounting is not removed by private scalar promotion.

Generic constant division uses signed/unsigned reciprocal lowering, preserving
zero and signed overflow traps. Bounded IR-cost leaf inlining replaces the
frontend's integer-opcode whitelist; effectful/calling/polling bodies stay calls.
Both target selectors consume the same typed memory/scalar IR. Native and wasm
interpreters still share the portable runtime and Store contract.

## Replaced mechanisms

| Removed implementation | Replacement |
| --- | --- |
| `wasm_milkir/optimize/gc_reads.mbt` | General alias/versioned GVN |
| `optimize/loop_reads.mbt`, `loop_values.mbt` | Generic LICM and guarded first-use placement |
| `native/array_access.mbt`, `array_regions.mbt` | Checked GC memory SSA and independent borrow verification |
| Repeated field/element projection helper calls | Exact checked object view plus target address operations |
| Compiled Wasm caller-scope root copying | Function-lifetime slots and precise liveness masks |
| Allocation-time root-map parsing and selected-root arrays | Load-time immutable descriptors and borrowed indexed operands |
| Tiny integer opcode whitelist | Bounded semantic leaf cost |

Existing semantic regressions were migrated with the deleted passes. Generic
loop-memory tests also lock down incomplete predecessor states, initial versus
backedge versions, unknown aliases, all multi-result definitions, zero trips and
header values that escape an entry guard.

## Acceptance and performance

Final measured results and source hashes are recorded with the local acceptance
receipt. Timings separate first invocation from cold process/compilation cost.
Wasmtime AOT process timing remains an upper bound on invocation, not an exact
invocation phase. V8 uses optimized synchronous compilation with one compilation
task; all engines run the identical property and retain its assertions.

The remaining throughput gap is not declared solved by this architectural work.
Linux LSan, Windows and actual x64 execution require platform CI. ARM execution
and cross-target verification do not establish those results.

## Frozen local result

See [the source-hashed acceptance and measurements](issue568-unified-gc-local-2026-10-22.json),
[the fresh sanitizer receipt](issue568-unified-sanitizer-local-2026-10-22.json), and
[the final ARM64 shift code and relocations](issue568-unified-gc-code-2026-10-22.md).
All five serial trials of the unchanged 20000-iteration property return `1`.

| Engine | Cold process median | First invocation median | Compile phase median | Cold peak RSS |
| --- | ---: | ---: | ---: | ---: |
| Wasmoon baseline c7e407d5 | 4.698 s | 3.780 s | 0.552 s | 335.6 MiB |
| Wasmoon candidate | 3.953 s | 2.536 s | 1.088 s | 335.9 MiB |
| Wasmtime 49.0.1 | 2.410 s | Not isolated | Not isolated | 68.3 MiB |
| Wasmtime precompiled process | 2.112 s | Upper bound only | Separate precompilation | 11.7 MiB |
| Node 25.2.1 / V8 14.1 | 1.280 s | 0.777 s | 0.449 s | 69.0 MiB |

Wasmoon invocation improves 32.9% and cold elapsed time improves 15.9%.
Compared with Wasmtime, cold elapsed time is still 1.64x. The ratio to Wasmtime's
precompiled-process upper bound is 1.20x, so this is not proof of a precise 1.20x
invocation gap. V8 invocation is still 3.26x faster. RSS has effectively not
improved. Process counters include compilation/startup: retired instructions
fall from 89.876 billion to 73.975 billion; cycles fall from 17.594 billion to
14.885 billion. They are not isolated guest-loop counters.

The generated native code total grows from 930020 to 954980 bytes (1365 compiled
functions in each measured compiler report). `right_shift` grows from 1168 to
1872 bytes and `left_shift` from 1316 to 2232; their allocated spill-slot counts
also increase. These are measured costs, not a claim of optimal generated code.
The machine-code receipt includes retained admission/fallback calls alongside
direct byte/word memory instructions and reciprocal multiply/shift sequences.

The first full comparison exposed a cold regression: approximately 2.85 s of
compilation, including 1.53 s in native lowering of a 14152-instruction generated
initializer. A single-variable expansion-budget counterfactual reduces compile
time to approximately 1.15 s without changing invocation time or results.
Functions over 1200 IR instructions now retain checked helpers. This bounds CFG
expansion rather than reducing checks. The final compile median is 1.088 s,
still higher than baseline. Other architectural improvements are measured as a
combined dependent design; the speedup is not attributed additively to individual
passes. Earlier stage receipts remain explicitly historical.

Final verification: native 3040/3040 both ordinarily and with regalloc/GC/barrier
verification; wasm 1443/1443; strict native/wasm, info/fmt, module boundaries,
generated MSVC bridges and 178 Python tests (54 existing platform skips) pass.
Fresh isolated ASan/UBSan passes 284/284, both positive controls and the event-loop
lifecycle gate. The sanitizer covers native stubs/shared storage, not emitted
JIT machine instructions or MoonBit runtime objects. Linux LSan is not available
on this host. Core interpreter/JIT/actual wasm each retain 258 files and 62563
assertions; Component interpreter/JIT each retain 59 files and 1385 commands,
with no failures or skips. All owned scratch workspaces are removed after
receipts are inspected. No work-owned scratch sources, logs, reports or caches
remain under `_build`; pre-existing historical receipts are preserved.
