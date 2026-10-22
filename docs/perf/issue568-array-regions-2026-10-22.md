# parse_double: verified numeric-array access regions

This follows [the logical loop-value work](issue568-loop-gc-values-2026-10-22.md)
for [#568](https://github.com/Milky2018/wasmoon/issues/568). That work was committed
as `a7874e12`; the following implementation is a separate local working-tree
change based on it. Neither result is a claim of CI acceptance or publication.

## Entry and lifetime contracts

Native `JITModuleContext` calls, including resumable/async entry, now use the
same argument validator as the interpreter before native execution. It checks
nullability, live object kind, concrete reference subtyping and the existing
function/continuation rules. A raw `ArrayRef` variant alone is not an array-kind
proof. The previous byte-array-to-word-array reproduction now fails with a type
error instead of entering the JIT. Compatible array subtypes remain accepted.
Raw integer reference indices must originate in the supplied Store; this raw
interface cannot infer provenance from an integer. Rooted embedding interfaces
remain the appropriate ownership interface.

An opt-in runtime projection returns a physical array payload only when its
actual live identity, array kind, immutable layout, requested numeric width,
zero element offset and absence of reference fields have been checked. It does
not trust a module-local type index as a physical-layout hint. Its narrow ABI
provides i32 length at offset zero and elements at offset 16; a C static assert
checks that ABI. No compiler offsets into heap tables or layout structs are
introduced. Wide host allocations, unsupported layouts, reference/v128 arrays
and runtime GC verification retain checked helpers.

The reusable Wasm native lowerer constructs and independently verifies private
access plans. It does not add public unchecked-pointer Wasm instructions or a
second native IR. Failure to prove a plan discards it. Verification also runs
when the caller disables generic IR validation:

- Ordinary regions follow forward single-predecessor CFG edges. Calls, polls,
  allocation, unknown operations and raw memory writes end their lifetime.
- A natural loop can reuse a preheader view only after an array operation has
  already executed there. Its remaining preheader suffix and every path around
  the loop must be free of safepoints/reentry, and side entries are rejected.
  The preparation must be emitted before every loop block. Missing prechecks,
  zero-trip nullable paths, calls and allocation retain local checked accesses.
- Array length and layout cannot change within these regions. Element values
  are never cached: aliases read the effects of intervening writes. Reference
  writes keep their existing barriers. Concurrent out-of-protocol heap mutation
  is outside the embedding contract.

The selector emits ordinary scalar/packed/float loads and stores after an
unsigned bounds check. An out-of-range index uses the original helper and its
trap. Unsupported views use that same path. Cached pointers and lengths never
survive a safepoint. Codegen revision 16 invalidates revision-15 cached artifacts.

Private negative tests forge invalid plans across calls, allocation, joins and
unchecked loops. Public regressions cover aliases, packed signed/unsigned
values, floats, legacy wide slots, null/bounds traps, zero-trip loops, poll-enabled
compilation, host reentry with moving collection, invalid reference kinds,
nullability and valid concrete subtypes. Both x64 and ARM64 selectors verify a
single preheader preparation for a complete array loop. ARM execution alone is
not x64 execution evidence.

## Same-source comparison

The [local receipt](issue568-array-regions-local.json) records the exact source
and binaries. Baseline is clean `a7874e12`, candidate is an explicitly dirty
working tree based on it, and both were freshly built with the same SDK.
The pinned Core revision, Wasm bytes, property seed, import isolation, result
predicate and 20000 cases are unchanged. All measured results are 1.
Each invocation uses a new cache. Wasmtime uses
`-C parallel-compilation=n -C cache=n`. Three samples alternate engine order.
These are cold CLI measurements, including compilation/startup:

| Cases | Baseline wall / user CPU | Candidate wall / user CPU | Wasmtime wall / user CPU |
| --- | ---: | ---: | ---: |
| 1000 | 1.143 / 1.117 s | 1.183 / 1.155 s | 0.399 / 0.389 s |
| 20000 | 6.129 / 6.074 s | 5.813 / 5.759 s | 2.448 / 2.437 s |

The full-case same-run improvement is **5.2%**, with **2.37x** remaining wall
ratio. The short case regresses about 3.5%; added preparation, fallback code and
compilation are not free. This is a modest throughput improvement and a checked
compiler/runtime contract, not a resolution of the performance issue.
Historical baseline timing was 5.966 s; the fresh control here is 6.129 s.
Only the paired current measurements establish this stage's speedup.

Separate full-case kernel-counter runs retire 127807301203 instructions in the
baseline, 122011417219 in the candidate and 60884501719 in Wasmtime: 4.5% fewer
instructions, still about 2.00x Wasmtime. RSS remains about 352 MB versus 72 MB.
The memory gap is not fixed. The measurements do not support attributing the
remaining gap to one helper, cache behavior or collector policy.

The initial straight-region experiments improved their own paired controls
but did not clearly improve the historical wall ratio. They are not substituted
for the final loop-aware measurements above. Broader speculative pointer caching
and removal of safepoints/barriers were not used.

## Validation and delivery

- Native 3005/3005 with regalloc, GC and barrier verification; wasm 1419/1419.
  Actual physical accesses also pass the native suite and final numeric region
  regressions with GC verification off. Negative raw-write proof cases pass
  on native and wasm after the full gates.
- Fresh isolated macOS ASan/UBSan 277/277, event loop and both ASan positive
  controls pass. GC verification is off in that run so physical accesses are
  exercised; barrier and regalloc checks are on. LSan is unavailable on macOS.
  The harness excludes MoonBit runtime objects and JIT machine code from
  instrumentation, as recorded in the receipt.
- Native interpreter, native JIT and actual wasm Core each pass 258 files and
  62563 assertions. Component interpreter and JIT each pass 59 files and
  1385 commands, with no skips. These runs use the frozen candidate sources;
  native JIT uses physical accesses with regalloc and barrier checks enabled.
- Strict native/wasm warning checks, info/fmt, module boundaries, generated
  MSVC bridges, whitespace and 178 Python tests pass; 54 existing platform
  skips remain. x64 selection/allocation is checked, not x64 execution.

The local receipt was captured before committing and pushing this stage. Historical
receipts remain unchanged; #568 remains in progress. All owned OS temporary
source, binary, cache and raw-report workspaces were removed. Only the compact
source-controlled design and receipt remain. No CI/merge/publication is claimed.
