# Residual parse_double compilation and execution profile

## Scope and provenance

This is local macOS ARM64 evidence on an Apple M3 Max. The checkout is a dirty
working tree based on `c7e407d5686a21dde271a240ca6f5b9a8f20352e`, including the
previous unified-GC implementation. It is neither clean-commit nor CI acceptance.
The paired [JSON receipt](issue568-residual-profile-2026-10-23.json) records the
measurements, diagnostic counts, binary hashes and validation.

The Core input is pinned at `7547b846d38de3efa5509cb1b74ffb7ed9a4a3d1`.
The isolated 20000-iteration guest has SHA-256
`fb7bf21507c21de4ffb79126f94cc0846314bd0b03c33060a533f15afe441db1`.
Guest assertions remain enabled and every measured invocation returns `1`.
Cancellation/cooperation and verification instrumentation are disabled for timing.

Node is 25.2.1, with V8 14.1.146.11-node.14. Its optimized synchronous comparison
uses `--no-liftoff --no-wasm-lazy-compilation --wasm-num-compilation-tasks=1`.
The native processes use a fresh artifact cache each time. Five runs per engine
alternate serially; no owned build, test or profiler runs concurrently with them.
Uncontrolled background OS load remains a limitation. Profiling and diagnostic
logging runs are separate from these timing samples.

## Compilation: repeated placement, not register allocation

A detailed pre-change capture attributes the regression as follows. Values are
summed function-stage milliseconds; `baseline` is the original commit and
`prior unified` is the working tree before this iteration.

| Stage | Baseline | Prior unified |
| --- | ---: | ---: |
| Frontend optimization | 83.9 | 69.2 |
| Native lowering | 106.6 | 673.1 |
| Register allocation | 200.6 | 217.4 |
| Frame planning | 47.2 | 47.2 |
| Emission | 75.4 | 64.9 |

Within native lowering, target construction changes only from 102.3 to 111.6 ms;
orchestration grows from 4.3 to **561.5 ms**. A temporary phase probe attributes
**486.4 ms** to guarded placement and its cleanup. Input/output validation and
the independent borrow verifier together take about 56 ms in that capture.
Compiler CPU samples also show optimizer analysis and allocation work.

The old native preparation loop reruns guarded LICM followed by O2 up to sixteen
times whenever any instruction moves. LICM hoists cheap constants; final scalar
rematerialization sinks the same single-use constants again. Instruction motion
therefore keeps reporting progress even without a new CFG guard.

The new work-count regression fails before the repair with **18 whole-function
acyclic rewrite runs**. The repair rebuilds placement analysis only when an entry
guard or preheader changes the CFG, and performs scalar cleanup once afterward.
The regression now bounds rewrite runs to four, without a timing assertion.

A single-variable comparison of this repair reduces compilation from about
1.145 to 0.733 s while invocation remains about 2.57 s. In a final detailed
capture, native orchestration is 186.0 ms, native lowering 307.3 ms and register
allocation 232.7 ms. Register allocation is still substantial, but was not the
cause of the compilation doubling. Compilation still exceeds the original
commit because physical-memory preparation and its validation are additional work.

## Execution: actual installed code and dynamic queries

A diagnostic counter after the placement-convergence repair, before external
entry merging, records
**106286268 calls to `gc_struct_data_impl`** for the original 20000-iteration
guest. Actual artifact installation ranges map each return PC to its guest
function and call offset. Compatibility/preflight function tables do not describe
the installed compact code and are not used for this attribution.

Selected counts:

| Function | Struct-view calls |
| --- | ---: |
| `parse_decimal_from_view` (460) | 19919827 |
| `Decimal.left_shift` (454) | 14519194 |
| `StringView.fold_digits` (478) | 13203850 |
| `Decimal.shift_priv` (452) | 6409666 |
| `Decimal.to_double_priv` (451) | 5895968 |

One call in `left_shift`, at byte offset 1628 before the entry repair, executes
**9975102 times**. Its prepared IR has a checked struct view inside the second
digit loop. That loop has two external entry edges, including the first loop's
zero-trip path. LICM cannot find a unique preheader, so it leaves the query inside
the loop even though no moving/reentrant operation occurs in that loop.

The repair creates a normal SSA preheader, merging original edge arguments.
Guarded placement then moves the check only onto the continuing path. The header's
zero-trip exit still bypasses it. A work/placement regression fails before this
repair and passes after it; public interpreter/JIT comparisons cover both initial
values, zero trips with null, actual null traps, and writes to another field.
Existing trap-order, same-field alias, moving-call and physical-borrow checks stay
enabled. A separate three-pair comparison improves invocation about 3%; the final
five-pair improvement is 2.4%.

### Original-workload CPU attribution after the repairs

A separate two-second `sample` capture, at 1 ms intervals starting 1.3 seconds
after launch, obtains 1663 main-thread samples during the original guest's
invocation. Only installation metadata is logged, before invocation. It does not
add a hot-call logger. Exclusive counts sum to 1663; all 555 JIT-exclusive samples
map to ranges from that same process, rather than a different ASLR run.

| Exclusive location | Samples | Main-thread share |
| --- | ---: | ---: |
| JIT machine code | 555 | 33.4% |
| Struct-view helper | 295 | 17.7% |
| Typed object allocator | 155 | 9.3% |
| Array-view helper | 86 | 5.2% |
| Fast struct reservation | 50 | 3.0% |
| Slow struct allocation | 49 | 2.9% |
| Allocation-root selection | 47 | 2.8% |
| Collection seeds | 41 | 2.5% |
| Function-root frame enter + leave | 63 | 3.8% |
| Heap sweep | 36 | 2.2% |

These are statistical shares of the sampled window, not an exact decomposition
of the entire invocation or a prediction that removing one helper saves its full
share. Exploratory 100000-iteration captures are separate; their collection mix
must not be substituted for this original-workload capture.

Of the 555 JIT-exclusive samples, 281 are in `left_shift` and 137 in `right_shift`.
Hot PCs include loop branches, digit loads, arithmetic, spill reloads and stores.
A sampled instruction is not proof of its isolated latency or cache-miss cause.

## Machine-code comparison and remaining design costs

Both engines compile the same indexed guest functions. Wasmoon's prepared IR,
allocated VCode, code object and machine bytes are captured, together with V8's
actual optimized code using `--print-wasm-code-function-index=453` and `454`.
The matching native helper is also disassembled from the executable.

V8's left-shift code uses direct tagged object addresses. For example, its first
scalar-box allocation contains the following inline bump sequence:

```asm
ldr   x9, [x8]             ; allocation top
add   x11, x9, #0x18
cmp   x11, x10            ; allocation limit
b.hs  slow_allocation
add   x10, x9, #0x18
str   x10, [x8]           ; publish new top
add   x8, x9, #1          ; tagged result
stur  x6, [x8, #-1]       ; map/header
stur  w4, [x8, #15]       ; scalar payload
```

V8 **also retains and updates these scalar boxes** in this capture. It would be
incorrect to attribute the difference to V8 eliminating every such allocation.
Wasmoon initializes admitted objects directly, but its reservation, stable-ID
registration, quota handling and slow allocation still cross C boundaries.

V8's arithmetic includes a shifted-operand add and fused multiply-subtract:

```asm
smulh x14, x11, x13
asr   x14, x14, #2
add   x14, x14, x11, lsr #63
msub  x11, x14, x15, x11
```

The corresponding Wasmoon remainder sequence uses separate shift/add and
multiply/subtract instructions, with loop-carried values also reloaded from spill
slots. V8's printed function additionally includes inlined callees and unrolled
regions; function size or flat function-name profiles alone are not comparable
work counts. Wasmoon's left-shift body grows from 2232 to 2264 bytes with the
entry repair, while improving runtime: code size alone does not explain speed.

The struct helper's disassembly confirms a stable-ID page/offset lookup, live-kind
and field-count checks, canonical type admission, and layout-prefix checking
before returning the opaque view. The identity lookup is already C-inline; it is
not a hidden out-of-line identity helper. Explicit non-null context arguments
also bypass TLS context lookup. Blaming these calls uniformly on TLS would be
incorrect. The remaining per-view admission and mapping work is real, however.

The next substantial targets are therefore:

1. A compiler-visible allocation reservation/commit contract that permits an
   inline fast path while preserving identity, quotas, failure injection, roots,
   rollback and slow collection. Deleting unused allocations without addressing
   those observable contracts is not a valid shortcut.
2. Interprocedural effects and admission facts, so a moving safepoint requires a
   physical remap rather than repeated full logical admission where that can be
   proved. Unknown or reentrant host boundaries must remain conservative.
3. Numeric-loop instruction selection and spill/control-flow costs, including
   fused multiply-subtract and redundant compatibility branches. These require
   separate controlled measurements; their full speedup is not established here.

No unchecked pointer cache, type-check removal, relaxed quota, root-mask weakening
or benchmark-specific special case is part of this repair.

## Final serial comparison and validation

| Engine/variant | Compile median | Invocation median | Cold process median |
| --- | ---: | ---: | ---: |
| Prior unified working tree | 1.117129 s | 2.564252 s | 4.006603 s |
| This iteration | 0.736170 s | 2.503547 s | 3.557189 s |
| V8 optimized synchronous | 0.443468 s | 0.773941 s | 1.272601 s |

Compilation improves **34.1%**, invocation **2.4%**, and cold process wall time
**11.2%** in this comparison. The remaining invocation ratio is **3.24x**. The
previous 3.26x figure was from a different sample set; it is not evidence of a
large execution improvement in this iteration. GitHub #568 remains open work.

Current validation: native 3043/3043 with register-allocation, GC and barrier
verification enabled; wasm 1445/1445; strict checks on both targets; info/fmt;
module boundaries; generated MSVC bridge check; Python 178 tests with 54 existing
platform skips. Fresh ASan/UBSan passes 284/284, with both positive controls
detected. macOS does not provide the Linux LSan acceptance gate.

Core native interpreter, native JIT and actual wasm interpreter each pass 258
files and 62563 assertions without failure/unsupported. Component interpreter and
JIT each pass 59 files and 1385 commands with zero failures/skips. Scratch sources,
builds, profiles, caches and generated test HTML are removed after verification.
No commit, push, remote CI, merge or publication is claimed by this receipt.
