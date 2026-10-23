# Issue 568: the same decimal loops in Wasmoon, Wasmtime and V8

Research only. No production source, compiler pass, runtime policy, dependency,
toolchain, test expectation or benchmark workload was changed. Nothing was
committed or pushed. The purpose is to decide an architecture before making
another optimization patch.

Evidence:

- [Measurements, controls, counters and profile](issue568-three-engine-comparison-2026-10-22.json).
- [Actual optimized IR and ARM64 code for functions 454 and 453](issue568-three-engine-loops-2026-10-22.md).
- [Matching V8 source chain and contracts](issue568-v8-source-comparison-2026-10-22.md).
- [Current Wasmoon design and caller inventory](issue568-wasmoon-design-audit-2026-10-22.md).

## Baselines and experimental boundaries

| Item | Exact baseline |
| --- | --- |
| Wasmoon | `c7e407d5686a21dde271a240ca6f5b9a8f20352e`, clean archived source, fresh release CLI |
| Wasmtime | Installed 49.0.1, source `46c23a87dac1465986a8ad53ba6a7ae49372857b` |
| V8 | Node 25.2.1, V8 `14.1.146.11-node.14`, official matching Node source `4cac2b94bed4bf02810be054e8f63c0048c66564` |
| Host | Apple M3 Max, ARM64, macOS 26.7 |
| Core input | Revision `7547b846d38de3efa5509cb1b74ffb7ed9a4a3d1` |
| Original Wasm SHA256 | `16bcf1f9c694573d1fb5f80ed0d44686a130f9f91d501eeeb2697544eca79dc4` |
| Isolated property SHA256 | `fb7bf21507c21de4ffb79126f94cc0846314bd0b03c33060a533f15afe441db1` |

The existing property isolator retains seed 37, 20,000 cases, six spellings and
all assertions, and exposes `probe`, whose successful result is 1. All measured
invocations returned 1. The original single-property isolation and import
replacement are unchanged. This is the same guest in every engine, not a new
hand-written array microbenchmark.

Wasmtime parallel compilation and its cache were disabled. Each Wasmoon
measurement had a new cache directory. Diagnostic/verification environment
flags were absent. Measurements ran serially, with engine order reversed on
alternate rounds. The table contains medians of five new processes per engine.

V8 code extraction and primary timing explicitly selected the optimizing tier:
`--no-liftoff --no-wasm-lazy-compilation --wasm-num-compilation-tasks=1`.
Bounds checks and stack checks stayed enabled; ordinary inlining, peeling and
unrolling stayed enabled. A default-tiered Node control also returned 1
(one invocation, 0.775 seconds); it is not the five-sample primary baseline.
The actual Node binary has **pointer compression disabled**. Earlier research
against another V8-main revision is not evidence about this binary.

### Separate startup from execution

| Measurement | Median wall seconds | Scope |
| --- | ---: | --- |
| Wasmoon | 4.876 | Fresh process, parse, validation, instantiate, compile, prepare, invoke |
| Wasmoon invocation | 3.932 | Existing CLI phase timer around `call_with_context`, including its runtime work |
| Wasmtime | 2.492 | Fresh CLI process, compile, instantiate and invoke |
| Wasmtime precompiled | 2.183 | Fresh CLI process loading the same CLI-produced artifact, instantiate and invoke |
| V8 optimized compilation | 0.458 | Synchronous `WebAssembly.Module` |
| V8 first invocation | 0.801 | `instance.exports.probe()` after compilation and instantiation |

Wasmoon's compile phase is 0.579 seconds and JIT load/GC preparation is 0.290
seconds. Its current cold ratio is **1.96x** Wasmtime, not an invariant 2.37x.
The precompiled Wasmtime number still includes loader/instance/process costs:
it is an upper bound on invocation time, not an exact invocation timer. The
Wasmoon invocation is therefore at least about 1.80x that Wasmtime invocation
under these measurements, and about 4.91x the V8 optimized first invocation.
Do not compare Wasmoon's cold time with V8's invocation time as an engine ratio.

An attempted exact-version C API phase timer was rejected for the primary
comparison. The verified official C API archive defaults to DRC, whereas this
CLI defaults to copying. Deserializing the CLI artifact reports the collector
mismatch. Its 5.65-second first invocation is a different collector control,
not a replacement for the CLI baseline. No library was installed globally.

Single fresh-process counter runs, including compilation, reported:

| Engine | Retired instructions | Cycles | Peak RSS |
| --- | ---: | ---: | ---: |
| Wasmoon | 89.98 billion | 18.02 billion | 336 MiB |
| Wasmtime | 60.87 billion | 8.98 billion | 68 MiB |
| V8 optimized | 19.12 billion | 4.78 billion | 70 MiB |

These are whole-process counters, not per-loop or invocation-only counts.
Their cycles/instruction difference is real but does not identify individual
cache, TLB, branch-prediction or instruction-latency contributions.

## Follow one actual iteration

Function 454 is `Decimal.left_shift`. Function 453 is `Decimal.right_shift`.
Their identity comes from the input's name section and function indices, not
from a similar benchmark in another checkout.

The first left-shift loop computes:

```text
digit = digits[read_index]
acc += i64(digit) << shift
quotient = signed_divide(acc, 10)
digit_to_write = acc - quotient * 10
--write_index
if write_index < digits.length:
    digits[write_index] = byte(digit_to_write)
else if digit_to_write != 0:
    decimal.trunc = true
--read_index
acc = quotient
```

The second loop drains the accumulator. Right shift has no corresponding
signed divide-by-ten: its main digit loop shifts out a byte and computes
`(acc & mask) * 10 + next_digit`. Its evidence is important because a
divide-by-ten explanation cannot explain all of both functions.

### Optimized IR: what really survives

| Concern | Wasmoon optimized MilkIR | Wasmtime optimized CLIF | V8 optimized Turboshaft |
| --- | --- | --- | --- |
| Decimal field reads | Typed Wasm extensions, including loads outside loops and lazily cached values | Ordinary typed loads with explicit alias regions, traps and offsets | Ordinary tagged-base loads after earlier typed GC analysis |
| Private integer `MutLocal` objects | Field values promoted to SSA block parameters, but three allocations retained | Three allocations retained, private field accesses remain memory operations | Three allocations retained, some private field memory operations remain |
| Packed digits | Array extensions until native selection; projected-view plan inserted separately | Byte loads/stores, explicit bounds/object-address checks | Byte loads/stores and unsigned bounds checks |
| Division by ten | Generic `sdiv` survives | `smulhi`, shift and sign correction | Signed multiply-high, shift and sign correction |
| Byte conversion | Tiny scalar conversion inlined | Normal call to function 688 (`Byte.to_int64`) in the digit path | Inlined |
| Surrounding helpers | `new_digits` and `trim` remain calls | Remain calls in the default configuration | Both appear in the actual inlining records for 454 |

This corrects an attractive but false story: the other engines do **not**
eliminate every private allocation in this example. Wasmoon's existing scalar
promotion is useful. Its problem is that the representation around it still
hides allocation/access behavior from the general compiler.

The Wasmtime CLIF was emitted after `compile_maybe_cached`; it is not merely
the unoptimized Wasm translation. V8 graph data was captured after
`V8.TFTurboshaftWasmOptimize`. Its machine code includes peeled/unrolled
variants and inlined helpers; static function sizes or static call counts
cannot be compared as if they were per-iteration dynamic counts.

### Machine code: concrete differences

In Wasmoon's function 454, the steady digit path at offsets `0x448..0x484`
includes the following actual instructions:

```asm
sxtw x0, w0
ldr  w2, [sp, #0x50]
sxtw x1, w2
lsl  x0, x0, x1
add  x0, x24, x0
mov  w1, #10
cbnz x1, division_nonzero
brk  #4
cmn  x1, #1
ccmp x0, #1, #0, eq
b.vc division_no_overflow
brk  #5
sdiv x24, x0, x1
mov  w1, #10
mul  x1, x24, x1
sub  x0, x0, x1
```

The zero and signed-overflow checks are valid for a generic divisor but are
statically unnecessary for the known constant 10. Native lowering has already
lost the opportunity to use that fact. This is not GC overhead.

V8's corresponding arithmetic at `0x3b0..0x3bc` is:

```asm
smulh x14, x11, x13  // x13 = 0x6666666666666667
asr   x14, x14, #2
add   x14, x14, x11, lsr #63
msub  x11, x14, x15, x11  // x15 = 10
```

Wasmtime also uses `smulh` and sign correction. Both retain the guest's signed
rounding behavior. This is a candidate for generic arithmetic legalization,
not a decimal-specific pattern and not removal of divide traps globally.

For the digit load/store, Wasmoon's fast path does reach `ldrb` and `strb`.
It nevertheless retains a capability/bounds branch to a C helper fallback,
separate address calculations, a multiply by element width 1, and some
spill/reload traffic. A lazy-length initialized flag adds another branch.
Decimal field writes, including the truncation flag, still call a C accessor.
The second accumulator loop can also fetch the Decimal field and array length
through helpers. These costs cannot all be described as one helper per digit:
some are once per loop, some occur on the truncation path, and others are
fallbacks. The attached CFG/code preserves these distinctions.

V8's steady loop at `0x378..0x3f8` uses direct tagged-base field loads,
`ldrb/strb`, unsigned bounds checks, multiply-high division and a backedge
stack check. There is no ordinary C field/array accessor call on that loop.
It still writes/reads private `MutLocal` fields and checks the stack; it is not
a check-free idealized loop. Right shift similarly uses direct byte accesses
and `madd` for the accumulator update, including unrolled variants.

Wasmtime's copying-collector code directly loads/stores fields and bytes, but
has heap-offset conversion, bounds/internal-corruption checks and the tiny
conversion call in its digit path. The call's actual stack map records four
i32 root slots. Wasmoon already beats it at eliminating that particular tiny
call, yet loses elsewhere. This is why copying an engine wholesale or applying
one more local peephole is not a sufficient plan.

## GC references, allocation and roots are distinct costs

| Contract | Wasmoon now | Wasmtime 49 copying | This V8 binary |
| --- | --- | --- | --- |
| Guest heap reference | 64-bit tagged stable identity; sparse ID pages resolve payload | Compact u32 heap offset/i31 | 64-bit tagged heap pointer; no pointer compression |
| Moving collection | Update identity-to-payload mapping; raw projections expire | Update live offset root slots and object edges | Update tagged live slots/objects through root and body descriptors |
| Numeric field layout | Packed typed Store layouts, plus legacy wide objects | Static canonical layout offsets | Static canonical layout offsets |
| Successful allocation | C helper with type/identity/quota work and precise-root selection | Generated bump/top-limit/header fast path; cold GC helper | Generated allocation top/limit fast path; cold builtin |
| Ordinary guest-call roots | Spill/copy live encoded words, push scope, call, pop | Allocated root slots plus PC-indexed stack maps | Allocated tagged slots plus PC-indexed safepoint maps |
| Suspension/reentry | Explicit activation/parked/input roots and arena edges | Frame/continuation/host roots | Frame/stack-switching/host roots |

Wasmoon's packed layout and native descriptor tracing already exist. The old
claims that every numeric field occupies 16 bytes, every traversal scans all
historical object IDs, or every graph edge is decoded by MoonBit no longer
describe this head. Current code uses typed layouts, a live-object list, sparse
identity pages and native graph expansion. A new plan must build on that work.

Likewise, the current explicit-heap scalar accessors do not each perform a TLS
lookup. They still resolve identity, inspect layout and cross a C call. Older
TLS wrappers are a separate caller inventory. Avoid adding an imaginary TLS
charge to every generated load.

### Two root transports remain

1. `CallerRootScopeAbi` stores live words to a stack buffer, calls push, emits
   the guest call, keeps roots live, and calls pop. Runtime scope objects and
   buffers are reused, but stores, copy, list operations, ABI clobbers and two
   calls remain. Ordinary non-safepoint field helpers do not also pay a root
   scope automatically.
2. Allocation helpers have another precise-root operand buffer and v2 map.
   `gc_select_alloc_roots` walks variable-size records to select the safepoint,
   allocates a selected-root array with `malloc`, and frees it after allocation.
   This is still on successful allocation paths with nonzero roots.

These allocation maps do not walk all caller frames by return PC. Merely
observing that Wasmoon has stack maps is not a justification for deleting
caller root scopes now.

A separate 3-second sample, starting about 0.95 seconds after launch, captured
2,516 main-thread samples. Exclusive top-of-stack counts include:

| Symbol/group | Samples | Share of this main-thread window |
| --- | ---: | ---: |
| `gc_struct_get_heap_impl` | 297 | 11.8% |
| Array get/set/length helpers | 191 | 7.6% |
| `gc_struct_set_heap_impl` | 41 | 1.6% |
| `gc_heap_alloc_typed` | 204 | 8.1% |
| `gc_select_alloc_roots` | 104 | 4.1% |
| Root push/pop helpers and internals | 213 | 8.5% |

The call tree also places allocator/free and `mach_absolute_time` samples
under allocation-root selection/cleanup. That clock cost is seen inside the
system allocator, not evidence of a guest poll. JIT PCs are unsymbolized in
this sample. These exclusive sample shares establish current activity; they
are neither dynamic invocation counts nor additive removable percentages.

### Useful controls and limits

- Disabling **only V8 Wasm inlining**, retaining its optimized tier and checks,
  raises median invocation from 0.801 to 1.510 seconds (three controls).
  This is a causal effect in V8, not a prediction of Wasmoon's future speedup.
- Enabling Wasmtime `-C inlining=y` gives 2.612 seconds cold (three controls),
  versus 2.492 default. More inlining is not automatically beneficial; compile
  time, code growth and profitability matter.
- Selecting Wasmtime DRC gives 6.270 seconds cold versus 2.492 copying, with
  the same guest/result. Collector configuration is material and must be
  pinned in future comparisons.
- Separate trace-enabled processes report 450 V8 scavenges (5.191 ms summed
  reported pauses, including startup/compilation) and 33,546 Wasmtime copying
  collections. The latter trace ends with a 128 KiB GC heap and about 34 KiB
  live data. Trace output and its overhead were excluded from timing samples.
  Collection count by itself is not a measure of collection cost. No new
  Wasmoon collection counter was instrumented here.

The remaining gap is now tied to observable mechanisms: helper-heavy field
access, a late fragmented lowering CFG, per-allocation root selection,
ordinary-call root transport, a non-inline allocation fast path, limited
inlining and missing generic arithmetic/address optimization. There is no
honest per-mechanism causal percentage for Wasmoon without future isolated
implementations. In particular, SDIV or ID indirection alone has not been
shown to explain the full gap.

The initial ranked hypotheses were access/ABI overhead, allocation/root work,
arithmetic/CFG quality and startup mixing. All four have evidence above. Two
stronger versions are rejected: the current root-scope path does not allocate
on every push, and this Node binary does not gain its advantage from compressed
references. No result licenses assigning the entire gap to TLS, GC, SDIV or
register allocation alone.

## The architectural defect

Wasm type/layout facts, logical alias facts, native address lifetime and root
transport are represented in different layers with repeated conservative
allowlists. Generic MilkIR sees Wasm extensions as unknown effects; native
selection later manufactures per-access fast/fallback diamonds. General GVN,
LICM, address folding and register allocation consequently see either too
little information or a CFG that was expanded too late to optimize globally.

V8 keeps typed GC operations through its GC analysis, then lowers to ordinary
memory operations and runs another general optimization stage. Its high-level
GC pass forwards struct fields and array lengths, **not array element loads**.
Wasmtime exposes layout, alias regions and collector behavior directly while
building CLIF. Neither relies on recognizing one particular producer function
to decide whether a byte load may use an object address.

Relevant primary sources:

- [V8 typed GC lowering](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/wasm-lowering-reducer.h#L237-L423)
  and [effect contracts](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/operations.h#L672-L754).
- [V8 GC alias/load analysis](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/wasm-load-elimination-reducer.h#L612-L647),
  [pipeline](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/pipeline.cc#L3144-L3213)
  and [constant division](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/turboshaft/machine-optimization-reducer.h#L2637-L2698).
- [Wasmtime GC lowering and alias regions](https://github.com/bytecodealliance/wasmtime/blob/46c23a87dac1465986a8ad53ba6a7ae49372857b/crates/cranelift/src/func_environ/gc.rs),
  [copying allocation](https://github.com/bytecodealliance/wasmtime/blob/46c23a87dac1465986a8ad53ba6a7ae49372857b/crates/cranelift/src/func_environ/gc/copying.rs#L97-L219)
  and [root walking](https://github.com/bytecodealliance/wasmtime/blob/46c23a87dac1465986a8ad53ba6a7ae49372857b/crates/wasmtime/src/runtime/store/gc.rs#L674-L810).
- [V8 root-map construction](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/compiler/backend/register-allocator.cc#L4770)
  and [Wasm frame scanning](https://github.com/nodejs/node/blob/4cac2b94bed4bf02810be054e8f63c0048c66564/deps/v8/src/execution/frames.cc#L1685).

## One replacement design, not another set of recognizers

### 1. Put semantic facts in one compiler-owned contract

Keep validated reference category, nullability and canonical layout/type facts
available through Wasm optimization. A side table/context is sufficient; it
does not require adding every Wasm type to generic MilkIR. Generic operations
must nevertheless receive a structured extension-effect contract or ordinary
lowered operations with equivalent semantics.

The contract separately describes reads/writes to logical locations, traps,
allocation/collection, reentry, suspension and heap-base replacement. Unknown
imports/extensions remain conservative. There is no single reusable `safe`
boolean. Required distinctions:

| Fact/value | What invalidates it |
| --- | --- |
| Checked non-null stable GC identity | Invalid admission/identity replacement, not an ordinary numeric store |
| Cached mutable field value | A possibly aliasing write or unknown writing call |
| Array length | Identity destruction/replacement; element stores cannot resize it |
| Resolved physical object/payload address | Collection, heap relocation/rebind or reentry capable of either |
| A live logical root | Last use, escape ownership and suspension lifetime, not merely return from one helper |

### 2. Lower GC operations before final target selection

Use a Wasm-specific GC lowering boundary, with a runtime layout/access policy,
before streaming to target VCode. Lower checks and projections into explicit
SSA operations and ordinary typed loads/stores. Feed the resulting whole
function through common value numbering, alias-aware load forwarding, check
domination, LICM and scalar/address simplification before register allocation.

Initially retain stable-ID guest references. Make ID-page resolution visible
to the optimizer and share a projection within a proved no-move interval.
Represent raw addresses as borrowed/derived values; verify that they do not
cross a moving safepoint or unsafe reentry. Reference-valued stores still use
the existing barrier; numeric stores do not need one.

This can remove a C helper from a trusted numeric field access without first
changing host identity, rollback or interpreter semantics. Direct-pointer or
compact-offset guest references remain a later ABI/collector decision with
their own controlled experiment, not a prerequisite for stack maps or direct
loads.

Static offset admission must cover host-created values, imported calls,
tables/globals, host returns and resumed execution. Existing wide objects may
share a semantic type with packed objects. Until those entry contracts are
closed, select a checked representation once at admission/region entry, or
keep a deliberate legacy fallback. Never assume a module's declared type
alone proves the physical layout of every current embedding object. Preserve
mutable alias identity when normalizing representation.

### 3. Replace root copying with allocated root locations

First predecode/validate allocation maps at artifact load and pass an indexed
root-slot view; successful allocation must not linearly parse the map or
allocate a selected-root array. This is independently useful and does not
pretend to solve caller-frame discovery.

Then produce safepoint maps from **final allocated locations** and index them
by function/return PC. A function's live roots can stay in ordinary mapped
spill slots instead of being copied into a second scope buffer at every call.
The first implementation may map the same stable-ID words used today.

Frame lifetime must work for normal calls, tail calls, builtin calls, traps,
active reentry, detached outer activations and parked/resumed/cancelled stacks.
Use a function-lifetime linked-frame descriptor if necessary while proving
PC/frame walking; do not silently drop a root category. Root visitors should
share one enumeration contract, with transport adapters for each execution
state. Incomplete discovery continues to forbid reclamation.

Exception/continuation arena payloads remain graph edges, not unconditional
roots. The transaction exception journal still owns phased rollback and
escaped managed identities/quotas. Root-map migration does not replace that
lifetime contract.

### 4. Put allocation and ordinary scalar optimization on the fast path

Expose a bounded inline allocation fast path: layout/size, quota admission,
available payload/identity capacity, header initialization and slow-path
safepoint are explicit. Fast allocation must preserve object/byte quotas,
identity mapping, failure/trap semantics and the interpreter's shared heap.
Do not introduce a second independent JIT object store.

Do not delete retained `MutLocal` allocations merely because their fields
became SSA: allocation failure, accounting and resource admission are
observable in current APIs. A later escape-analysis change needs an explicit
contract for virtual allocation/accounting. Inline allocation is useful even
when such elimination is disallowed.

Add generic constant-divisor legalization and constant-specific trap folding,
plus multiply/add/sub address folding and direct compare-to-branch selection.
Use the same semantic tests on both targets, including signed minimum values,
negative operands, zero and -1 divisors. Make inlining cost/size/effect driven,
rather than adding another decimal/helper-name whitelist. Keep compile time
and code size in the acceptance data; the Wasmtime control rejects the idea
that enabling more inlining is an unconditional win.

## Deletion and migration list

These are replacement targets, not authorization to remove them before their
correctness obligations have another owner.

| Current mechanism | Replace with / deletion condition |
| --- | --- |
| `optimize/gc_reads.mbt` field cache | Location/type-aware common load forwarding; delete its independent invalidation logic |
| `optimize/loop_reads.mbt` custom hoisting | Common check domination, null facts and LICM with precise effects |
| `optimize/loop_values.mbt` initialized-flag/extra-phi cache | Shared lazy/guarded placement and memory facts; preserve zero-trip and first-execution trap ordering before deletion |
| `native/array_access.mbt` and `array_regions.mbt` producer/CFG recognizers | SSA object projection plus checked index/address and borrow-epoch verifier; no producer-specific exception |
| Repeated `forward_gc_reads -> generic -> hoist -> generic -> cache -> generic` choreography | A deliberate typed-analysis/lowering/general-optimization pipeline with shared facts |
| C struct/array access calls in proved guest numeric paths | Ordinary typed memory operations; retain compatibility/debug/unsupported paths behind one adapter |
| Per-access view/fallback diamonds | One representation selection/projection where needed, common optimized loads/stores inside its dominated interval |
| Allocation-time v2 scan and selected-root `malloc/free` | Load-time decoded indexed slot descriptors; then allocated-location maps |
| Normal guest-call `CallerRootScopeAbi` push/copy/pop | Final-location safepoint maps or a proved function-lifetime frame; delete only after active/parked/reentry/tail/trap parity |
| Independent native-root copying/enumeration implementations | Shared visitor/ownership contract with explicit providers; keep all root/edge categories and conservative failure |
| Checked generic SDIV for a statically nontrapping constant divisor | Generic constant arithmetic lowering; retain generic checks for remaining divisors |
| Narrow integer-only scalar-call workaround | General bounded inliner when it covers the same contracts and actual callers |

**Keep:** validation, Store/type admission, compact physical layouts, live-object
traversal, stable host identity, quota/trap semantics, reference write barriers,
parked/reentrant roots, snapshot token identity and phased rollback, failure
controls and independent verification. Public low-level wide/TLS wrappers
cannot be deleted until their callers have been inventoried/migrated. Sparse
ID pages are not obsolete just because a different engine uses pointers.

## Delivery order and gates for a later implementation

1. Establish semantic/effect and representation-admission contracts. Acceptance:
   no unknown path becomes trusted; imported/host/table/global/resume values,
   null/trap ordering, aliases, packed/wide objects and both target lowerings
   retain behavior. Keep the same measured guest and code excerpts as baseline.
2. Implement GC-to-memory SSA lowering and general optimization, replacing the
   specialized read/view passes. Acceptance: the steady digit paths lose C
   field/array calls on supported layouts, with explicit bounds/trap behavior;
   raw projections fail verification if they cross moving safepoints/reentry.
3. Replace allocation operand-map parsing/copy allocation, then caller root
   transport. Acceptance: allocation-time selection performs no temporary
   allocation; actual native execution proves active, parked, nested exception,
   heap-only edge, reentry, tail-call, resume/cancel and incomplete-root cases.
4. Inline the successful allocation path and broaden scalar optimization/
   inlining without changing accounting. Acceptance: object/byte failure and
   subsequent quota reuse still match; compare invocation, startup, RSS,
   instructions and compile/code-size costs separately.

Each stage needs focused public regressions, relevant internal negative
verifiers, native/wasm checks, the existing root/rollback/quota tests, full
Core 258-file/62,563-assertion parity, sanitizer/leak controls and actual ARM64
and x64 execution. A source/code dump on ARM64 is not an x64 execution result.
Performance acceptance must use serial engine runs, exact artifacts/configs,
paired cold and invocation measurements, and no weakened assertions, checks,
warnings, budgets or deadlines. Repeat the broader corpus to catch traded
regressions; do not optimize only these two functions.

No speedup from this proposed architecture has been measured. The evidence
supports replacing the hidden/duplicated contracts and runtime transport;
it does not establish that any one change will reach or beat V8/Wasmtime.
Implementation is intentionally deferred for review of this design.

## Reproduction of code extraction

The exact property is produced by the existing
`scripts/benchmark_parse_double_gc.py:isolate_property` with count 20000.
Validate its SHA256 before using these commands. A stale root CLI symlink
must not replace a freshly built executable from the pinned revision.

```sh
wasmtime compile -C parallel-compilation=n -C cache=n \
  --emit-clif "$scratch/clif" -o "$scratch/probe.cwasm" "$scratch/probe.wasm"
wasmtime objdump --filter left__shift --bytes --stack-maps "$scratch/probe.cwasm"
wasmtime objdump --filter right__shift --bytes --stack-maps "$scratch/probe.cwasm"
"$fresh_wasmoon" explore "$scratch/probe.wasm" --func 454 \
  --stage opt-milkir --stage allocated-vcode --stage mc
"$fresh_wasmoon" explore "$scratch/probe.wasm" --func 453 \
  --stage opt-milkir --stage allocated-vcode --stage mc
node --no-liftoff --no-wasm-lazy-compilation --wasm-num-compilation-tasks=1 \
  --trace-turbo --trace-turbo-graph --trace-turbo-filter='*left__shift*' \
  --trace-turbo-path="$scratch/v8-ir" \
  --trace-turbo-cfg-file="$scratch/graph.cfg" \
  --print-wasm-code --print-wasm-code-function-index=454 \
  "$scratch/probe.js" "$scratch/probe.wasm" 1
```

This V8 build actually traces other Wasm functions despite the Turbo filter;
extract the two named function JSON files and remove the remaining scratch
output. The ordinary Node timing driver, without trace flags, is:

```js
const fs = require('node:fs');
const bytes = fs.readFileSync(process.argv[2]);
let start = performance.now();
const module_ = new WebAssembly.Module(bytes);
const compile = (performance.now() - start) / 1000;
start = performance.now();
const instance = new WebAssembly.Instance(module_);
const instantiate = (performance.now() - start) / 1000;
const rows = [];
for (let i = 0; i < Number(process.argv[3] || 1); ++i) {
  const cpu = process.cpuUsage();
  start = performance.now();
  const value = instance.exports.probe();
  const wall = (performance.now() - start) / 1000;
  const used = process.cpuUsage(cpu);
  if (value !== 1) throw new Error(`Unexpected property result: ${value}`);
  rows.push({ value, wall, user: used.user / 1e6, sys: used.system / 1e6 });
}
console.log(JSON.stringify({ compile, instantiate, rows }));
```

All temporary source archives, fresh builds, caches, binary/IR captures,
profiles, upstream downloads and drivers belong in an OS TemporaryDirectory
and must be removed after extracting the bounded research records. None belong
in `_build`/`target` or the source tree. Only the linked research notes, compact
measurement JSON and the two-function generated-code appendix are retained.
