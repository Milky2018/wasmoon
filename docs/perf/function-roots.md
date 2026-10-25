# Function roots and compiler expansion

Tracking: [ISS-697](../../issues/ISS-697.md).

A valid2048-object initializer on306daad has4098 MilkIR instructions but produces
25.580MB of machine code,47.360MB of serialized artifact and2,089,994 reloads.
Fresh CPU sampling and phase metrics identify register allocation and redundant
reload emission, rather than parsing or source optimization. The problem is
representation at the lowering boundary: roots are already stored once in a
registered function shadow frame, yet call metadata forwards them again as SSA
roots. Targets append KeepAlive uses that demand registers after every call.

For ordinary calls with an admitted frame, lowering still publishes every mask
word and checks every root definition. It then omits duplicate SSA root transport,
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
The remaining large-initializer profile is dominated by live-range calculation
through mask-writer CFG loops. Any later mask optimization must preserve complete
unknown-predecessor writes and invalidate knowledge on returns-twice control flow;
it is independent work, not included in these results.
