# Function roots and compiler expansion

Tracking: [ISS-697](../../issues/ISS-697.md), [ISS-698](../../issues/ISS-698.md),
[ISS-703](../../issues/ISS-703.md).

A valid2048-object initializer on306daad has4098 MilkIR instructions but produces
25.580MB of machine code,47.360MB of serialized artifact and2,089,994 reloads.
Fresh CPU sampling and phase metrics identify register allocation and redundant
reload emission, rather than parsing or source optimization. The problem is
representation at the lowering boundary: roots are already stored once in a
registered function shadow frame, yet call metadata forwards them again as SSA
roots. Targets append KeepAlive uses that demand registers after every call.

The initial transport change published every mask word and checked every root
definition for ordinary calls with an admitted frame. It then omits duplicate SSA root transport,
retaining source, site and argument metadata. Ordinary program uses determine
register liveness. Generic caller-scope lowering, returns-twice rejection, tails
and noreturn handling retain their prior contracts. Runtime active/parked root
enumeration and transaction rollback already read the registered frame. This is
not removal of rooting, physical-borrow rules or strict register validation.

A before-fix builder regression observes duplicate[22] transport instead of[];
afterward it also checks retained call-site identity and the root definition
store. A public96-object initializer performs full GC in every nested allocating
call, checks all payloads and reclaims all objects after return atO0/2/3. Forcing
actual mask bits to zero makes it trap; restoring the source passes. Both-target
selection checks keep the collecting fallback and function-frame enter/leave.

Fifteen alternating cold pairs on macOS ARM64 give median compiler microseconds:

| Input | Before | After | Paired change95% interval |
| --- | --- | --- | --- |
| parse_double |812673 |779876 |−4.58% to−3.44% |
| regex GC2100 |396053 |381566 |−3.89% to−2.93% |
|2048-object initializer |7378319 |2119388 |−71.52% to−71.14% |

Whole-fixture initializer RSS falls2.764→1.206GB; artifact size47.360→1.384MB.
The prototype phase profile has4084 reloads and0.529MB of machine code. Three
crypto controls show no stable compiler gain, unchanged RSS and exact artifact
bytes after normalizing only the manifest revision. GC machine code intentionally
changes, so codegen22 rejects21 caches; the artifact format and native ABI remain
unchanged. Compilation excludes artifact encoding, while RSS/wall cover the whole
fresh compiler fixture. These measurements do not establish invocation speedups.

A separate single-annotation UsePosition value-type experiment is rejected after
15pairs/six inputs: mostly flat compilation with higher RSS in several controls.
The next independent profile attributes the remaining large-initializer cost to
live-range calculation through mask-writer CFG loops.

## Repeated word stores

A sparse-mask builder emits 129 terminated blocks for one logical source block.
Each run of equal mask words used a generic CFG loop, making unrelated live roots
participate in artificial cycles. A block-local known-mask cache was rejected:
allocation diamonds invalidate its facts and the real artifact stayed unchanged.

The product-neutral `StoreRepeated64` operation instead selects one target VCode
instruction. Both emitters generate a bounded local machine-code loop using three
independent early register definitions and a late address input. There are no
hidden scratch registers, calls or safepoints. Positive, nonwrapping constant
ranges and operand contracts are verified independently; callers own the range
and lifetime, as with ordinary stores. Entry zeroing uses the same operation.
Complete masks are still written at every safepoint, including zeros from unknown
predecessors. Codegen 23 rejects 22 caches; the native ABI and artifact format stay
unchanged.

A public test keeps 320 opaque references through full GC, clears alternating
references and checks all remaining payloads at O0/2/3. Collections reclaim zero,
then 160, then 160 after return. Omitting the final word retains 16 unwanted roots
and fails. Unsafe x64 input timing is rejected before emission. These controls
are restored exactly. Both-target selection tests complement actual native
execution; local ARM execution alone does not establish x64 execution.

Fifteen alternating cold pairs per input, against the preceding frame-transport
commit, give the following compiler-only medians (microseconds):

| Live objects | Before | After | Paired change, 95% interval |
| --- | --- | --- | --- |
| 512 | 121949 | 96979 | −21.81% to −20.39% |
| 1024 | 491105 | 300102 | −39.17% to −38.09% |
| 2048 | 2116963 | 1109544 | −48.07% to −47.53% |

Whole-fixture 2048-object RSS falls from 1.206 to 0.600 GB. Its serialized artifact
grows from 1.384 to 1.398 MB, about 1%, because allocated machine loops materialize
explicit temporaries. Parse/regex and three crypto controls show no stable compile
change; crypto artifacts are byte-identical after normalizing only codegen 22/23.
This is 240 fresh measured processes across eight inputs, with deterministic
artifacts within each variant. The earlier loop-only ablation gives similar
results; using the same instruction for entry zeroing avoids a separate linear
prologue. These compiler measurements alone do not establish invocation gains.

## Invocation and engine controls

Five alternating samples across twelve asserted cases compare the numeric-segment
parent, frame transport and repeated-word commits in 180 fresh processes. The
2048-object initializer repeated 64 times changes 4.243→3.238→3.282ms invocation:
about 23% combined improvement, primarily from frame transport. Parse is flat;
regex700/2100 improves about 1.3/1.0% combined. Other array/graph controls do not
establish broad invocation gains. A 40ms static-reference-array control costs
about 1.2% more, with a wide interval; retain that small cost explicitly.

Three fresh samples of each public 128/512/2048-object fixture pass on Wasmoon,
Wasmtime49.0.1 copying/serial compilation, and V814.1.146.11 eager/single-worker.
For 2048 objects, whole-process wall is 1.132s Wasmoon, 0.717s Wasmtime and 0.376s
Node/V8; whole-process peak RSS is 603/321/183MB. Wasmoon compiler time is 1.108s
and V8 WebAssembly.Module time 0.327s; those boundaries differ in validation.
Wasmtime CLI supplies no isolated invocation phase in this experiment. These
are cold compiler-heavy controls, not collector-only RSS or Node startup gains.
[Unused live-set materialization](compiler-liveness.md) is optimized separately.


## Block-local mask knowledge

The earlier mask-cache prototype offered no stable gain because allocation
slow/join diamonds repeatedly discarded known state. After the separately
[bounded shared reservation expansion](allocation-expansion.md), longer straight
blocks make that state useful. The new capability is explicit: a function-frame
ABI may promise that helpers, collectors, reentry and parked-stack transport
preserve compiler-owned mask bytes. The default is false, retaining full writes.
Wasmoon opts in because its frame nodes expose const mask pointers; enter/leave
only link headers. Both target planners reserve non-overlapping stack objects
for the whole function, independently of their final SSA-address uses.

Within one such block, omit only mask words whose complete desired value is
already established. Always publish initial zeros and every root-slot definition.
An unknown CFG entry or a returns-twice continuation discards all previous mask
knowledge; the next update writes the full mask. Repeated changed runs keep the
bounded-word lowering. No call or safepoint observes a partial update. Generic
providers keep their old behavior. Codegen25 rejects24; format12/ABI8 stay intact.

Four compiler-trace regressions cover repeated/boundary words, unknown loop
predecessors, rewinds and default providers. Omitting either invalidation makes
its dedicated trace fail; runtime GC fixtures are separate positive coverage.
Full native3181 ordinarily and with all verification flags, Wasm1479 and strict
checks pass locally; clean integration/platform acceptance is independent.

Fifteen cold pairs against ba167840 improve 512/1024/2048-object compilation
21.6/17.7/14.0%. The largest compiler median is439.448→377.838ms (paired95%
interval −14.85% to −13.56%), whole-fixture RSS84.3→64.7MB and artifact
0.794→0.685MB. Parse compilation improves about0.95%; regex and three crypto
controls establish no further compiler gain. Crypto artifacts are identical
after only manifest24/25 normalization.

Five interleaved three-version invocation samples compare before the reservation
bound, that bound alone, and mask knowledge. For64 repetitions of2048-object
initialization, medians are3.233→5.488→3.882ms. Mask knowledge recovers about29%
of the bound's invocation cost, but the final version still costs about19% over
the earlier fast expansion (paired95% interval +17.28% to +22.63%). The128/512
controls similarly remain16/21% slower overall. Parse changes about−0.28%; both
regex sizes' combined intervals include no change. These are compiler-resource
and throughput tradeoffs, not a universal runtime speedup.
