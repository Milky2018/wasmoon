# parse_double: private GC fields and small integer calls

Subsequent work and current accepted measurements are recorded in the
[heap helper followup](issue568-heap-helpers-2026-10-22.md). The measurements
and receipt in this document remain historical compiler-stage evidence.

This continues [#568](https://github.com/Milky2018/wasmoon/issues/568) after the
[first GC access repair](issue568-gc-access-2026-10-22.md). The first repair's
receipt is historical and remains unchanged. The same pinned Core revision,
original Wasm bytes, seed, import isolation, success predicate and 20000-case
property are used here. The input is not rebuilt in release mode to hide its
boxed locals.

## Cause established by the next experiments

The fixed guest represents `Decimal.right_shift`'s read index, write index and
accumulator as three single-field GC structs. They do not escape the function.
Incrementing an integer therefore performs heap reads and writes. Calls to
`Byte.to_int64` and `UInt64.to_byte` contain only an extension or a wrap/mask,
but still require an ordinary guest call and caller root registration.

An instrumented execution of the complete property counted:

| Operation | First repair | Compiler followup |
| --- | ---: | ---: |
| Scalar struct reads | 3145488883 | 728958873 |
| Scalar struct writes | 1564763875 | 18696736 |
| Scalar array reads | 407647868 | 407647868 |
| Scalar array writes | 405228155 | 405228155 |
| Array length queries | 242237762 | 242237762 |
| Root scope pushes | 630119278 | 76855638 |
| Copied root words | 2515778050 | 138076419 |

Maximum root-scope depth remains 15. These are diagnostic counters, not clean
performance timings. The followup counter build precedes the final callsite
source-location metadata addition; its guest operations are unchanged by that
metadata-only addition. Both executions return exactly `1`.

Disassembly also found that Apple Clang merged the original fixed-size write
branches into a variable-length `memcpy` call. Distinct truncated scalar
temporaries keep widths 1/2/4/8 as ordinary stores without requiring aligned
or aliasing-unsafe pointer casts. The 16-byte path is unchanged.

## Repair boundaries

The Wasm optimizer promotes only entry-created, single-field I32/I64 structs
whose references have direct matching field-zero accesses and no other uses.
Calls, returns, copies or phi arguments carrying the reference reject the
candidate. Loops and merges carry the integer value as SSA block parameters.
The original effectful allocation remains: failure, allocation admission and
quota behavior are not erased. Packed, reference, floating-point and vector
fields, non-entry allocations and unsupported CFG shapes remain ordinary GC
operations. Candidate count and added block parameters have fixed work bounds.

The frontend supplies small integer bodies from the exact validated module,
keyed by linked function index. Imports are excluded. The optimizer verifies
callee IR, signatures and an integer-only scalar body of at most eight
instructions. It rejects calls, polls, memory, globals and references, and
bounds expansion to 256 sites per caller. Callee lookup visits only functions
actually called by the current caller. Cloned operations retain callsite
source locations. The same embedding environment produces templates, so
enabled entry cancellation checks prevent inlining rather than disappearing.

These transformations run at O2/O3 in the shared Wasm optimizer. O0/O1 and the
low-level NativeCompiler contract remain unchanged. CLI, Component, preflight
and explore supply the same module metadata. Codegen revision 13 rejects older
cached code. Generic MilkIR only gains a checked block-parameter construction
operation; it does not acquire Wasm GC semantics or runtime layout offsets.

After private writes disappear, GC read forwarding runs again because those
writes previously invalidated possibly aliasing field facts. Runtime barriers,
root protection and allocation/collection policy remain in force.

An isolated two-entry object-address/layout cache was slightly slower than its scalar
write control and is not included. An activation heap-field view saved a
smaller amount but added lifetime state; it is also not included. Neither is
needed for integer promotion or scalar inlining.

## Measurement and remaining work

The [followup receipt](issue568-local-scalars-local.json) separates final cold
samples, kernel instruction/cycle counters, sampling, diagnostic operation
counts and intermediate experiments. Every final benchmark invocation has a
fresh Wasmoon cache; Wasmtime uses `-C parallel-compilation=n -C cache=n`.
All success predicates and property assertions remain enabled. Performance
trials disable diagnostic verification flags for both Wasmoon variants;
correctness gates enable regalloc, GC and barrier verification.

Final accepted-source cold medians, three samples per engine and case count:

| Cases | First repair wall / user CPU | Followup wall / user CPU | Wasmtime wall / user CPU |
| --- | ---: | ---: | ---: |
| 1000 | 2.157 / 2.130 s | 1.181 / 1.157 s | 0.376 / 0.369 s |
| 20000 | 29.759 / 29.671 s | 9.360 / 9.309 s | 2.423 / 2.414 s |

The full wall ratio falls from 12.28x to 3.86x; throughput improves 3.18x over
the first repair. All nine complete-case invocations return exactly `1`.
Intermediate controls included 25.81 s after distinct scalar writes, 13.83 s
after integer-field promotion and 10.43 s after short-call inlining, before
the second GC forwarding pass. Their phase-local cache states differ; they
are directional experiments, not an additive decomposition of the final
cold-cache medians.

Separate full-case kernel-counter trials report 701341467356 retired
instructions before this followup, 219774404416 after it, and 60850378704 in
Wasmtime. The followup executes 3.61x as many instructions and uses about 1.12x
as many cycles per instruction as Wasmtime, yielding 4.04x total cycles in
that separate trial. This supports instruction inflation as the main remaining
gap. It does not rule out load dependencies or identify cache/TLB contributions.

The remaining uneliminated array operations total 1055113785, and struct reads
still total 728958873. Those operations still cross the platform C ABI, resolve
the active heap and stable identity, validate bounds/layout and execute the
access. Sampling and retired instruction counts are recorded separately;
helper samples alone cannot distinguish ABI instructions from dependent loads
or cache stalls. No instruction-cache or TLB attribution is inferred from a
flat sample.

The final three-second sample's leading active leaf symbols are
`gc_struct_get_impl`, `gc_array_set_impl`, `gc_array_get_impl`, the macOS TLS
getter and `gc_array_len_impl`. Root-copy and collection symbols are much
smaller after the compiler changes. The idle `__sigwait` helper thread is
excluded when interpreting this list. The remaining work is a shorter checked
native GC access path with a sound layout/safepoint contract, rather than a
lower collection threshold or another root-buffer allocation scheme. #568
remains open; this result does not establish Wasmtime parity.

The comparison uses fresh current-toolchain native CLIs executing the same pure
guest. It does not relabel the issue's historical published-0.17.1 embedding
numbers as this baseline. Embeddings that own MilkIR optimization must opt into
the shared Wasm optimizer and exact-module scalar callee metadata; the low-level
compiler does not silently turn O0 into O2.

## Validation

Public regressions first failed with two remaining private field accesses and
one remaining integer call. They now cover loop-carried SSA, branches with
existing arguments, escaping references, O0/O1, non-entry allocations,
effectful callees, malformed callee IR before mutation, linked/import indices,
cancellation checks and callsite source locations. Native O0/O2/O3 regressions
also execute the boxed integer loop and preserve its result. A resource-budget
test injects persistent allocation failure and verifies it still traps after
promotion, then verifies recovery and quota release.

Final native tests pass 2986/2986 with all three verification flags; wasm passes
1412/1412. Fresh isolated macOS ASan/UBSan passes 270/270 and both positive
controls. macOS does not establish Linux leak detection or Windows execution.
Sources are explicitly dirty on main `55657fb2`, and the receipt records the
copied functional source digest. Core passes 258 files / 62563 assertions in
native interpreter, native JIT and actual wasm. Component passes 59 files /
1385 commands per native engine with no skipped files. All owned temporary
source/build/log/cache workspaces are removed after verification. No commit,
push, CI acceptance or publication is implied by these local results.
