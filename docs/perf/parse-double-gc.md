# parse_double GC compiler checkpoint (#568)

## Current contracts

- Wasm effects distinguish logical writes from physical-address invalidation.
  Unknown calls, collection, reentry and heap replacement remain conservative
  barriers. Raw/imported references require actual Store type/layout admission;
  a module type alone does not establish the object's physical representation.
- Checked GC-to-memory lowering precedes target selection. Generic alias-versioned
  GVN and guarded LICM replace the old GC read/loop/array recognizers. An
  independent borrow analysis rejects physical pointer escape and use across
  invalidation, including backedges. Null/bounds traps and reference-write
  barriers remain observable; unsupported layouts retain checked helpers.
- Compiled guest calls use function-lifetime root slots and precise safepoint
  masks instead of allocating/copying caller scopes. Every root-bearing SSA
  binding publishes its slot. Active, detached, parked and rollback enumeration
  share the same contract; incomplete discovery forbids reclamation. These are
  shadow frames, not PC-indexed maps of final machine registers.
- Allocation descriptors are validated and indexed at load time. Eligible typed
  structs reserve and initialize through bounded generated code with no call,
  safepoint or reentry between admission and initialization. All refusal branches
  precede mutation. Quotas, verification, injected failures, growth and collection
  retain the shared allocator and precise-root fallback.
- A heap-owned exact-object admission hint is neither a root nor an owner. It
  includes canonical identity, shape and field count; current context mappings
  are still checked. Retirement, type changes, payload growth, compaction and
  close invalidate it. Sweep, compaction and rollback invalidate prepared
  identity capacity too. No cached field value survives an aliasing write.
- Expansion budgets bound large-function compile cost; unsupported functions
  retain helpers. Constant division and bounded leaf inlining preserve traps,
  effects, source locations and allocation accounting. The CLI snapshots type
  definitions together with recursive groups. Artifact codegen revision is 31;
  JIT ABI is 8. Native and wasm interpreters keep their shared Store/runtime.

## Guarded control values (October 26)

Budget-protected loops retain the original slow polling loop and charge each
header/inlined poll at its original position. A successful guard now returns
both its condition and the admitted invocation-control pointer. Charges must
consume that exact SSA result. The independent CFG proof rejects missing,
foreign, forged, block-parameter-carried, stale and over-consumed controls;
unknown mutation, reentry and collection revoke the proof. Each charge still
checks disabled/exhausted budgets and stores the remaining countdown. This
removes repeated execution/control/callback lookup without changing callbacks,
cooperative yields, fuel, roots, physical-borrow lifetime or the helper ABI.

Actual ARM64 code for Decimal right/left shifts (functions 453/454) was captured
from Wasmoon, V8 12.9.202.13-rusty and Wasmtime 49.0.1 using the same original
module. Constant division was already strength-reduced. V8 and Wasmtime use
direct object addressing; Wasmoon retains checked admitted views and an explicit
cooperation protocol. Machine-code size is not a timing attribution.
The V8 code-event probe uses the SDK's V8 version, not a rebuilt SDK runner.

Against parent `5b699ce8`, two independent alternating five-pair rounds on the
unchanged ten-call input (`44bcb057bbd6ebaa86e96dc912b2d9e01002659d72e2fb76afda97b8e14acc5c`)
find median paired whole-process reductions of 6.12% and 5.92%. All ten pairs
improve, including the retained 0.74% first-round outlier; process RSS is flat.
A subsequent independent four-engine round on the normalized final sources
finds a weaker 4.89% paired reduction, with all five pairs faster. This final
result is retained without a replacement run. Ten-call process medians are
2.618 s (parent), 2.490 s (final), 0.431 s (official SDK V8), and 1.348 s
(Wasmtime); final/reference ratios of medians are 5.77x and 1.85x respectively.
These measurements include compilation, execution, GC and teardown. They do
not establish a pure-guest speedup or a universal CPU gain. The matched 4.94 MB
compiler API round excludes input I/O and encoding: enabled 6.587 to 6.567 s,
plain 6.020 to 5.982 s, with essentially flat process RSS. The enabled round
retains a +5.03% paired outlier and mixed samples; no compiler speedup is claimed.

One matched Decimal charge path shrinks from 17 to 6 executed instructions
while retaining its budget assertion; struct/array helper and full-poll call
sites are unchanged. Two longer diagnostic execution samples change only the
wrapper repeat count from 10 to 100; all 1389 other function bodies and original
assertions are byte-identical. Projection-entry leaf shares are 26.39/26.57%,
with a separate struct-slow leaf share of 4.75/4.26%. The two Decimal JIT bodies
account for 33.21/32.48% of main-thread leaf samples. Cancellation's inclusive
7.97/8.38% already includes root-copy work (4.99/5.11%); overlapping shares must
not be summed or treated as a wall-time decomposition. The earlier checkpoint
tables below retain their separate inputs and scopes.

## Reproduce measurements

Use Core revision `7547b846d38de3efa5509cb1b74ffb7ed9a4a3d1` and build its
`internal/strconv` wasm-gc tests. The original `strconv.blackbox_test.wasm`
SHA-256 is `16bcf1f9c694573d1fb5f80ed0d44686a130f9f91d501eeeb2697544eca79dc4`.
The retained runner isolates the existing seed-37, 20,000-case asserted property
and requires every engine to return `1`; it does not replace it with a microbenchmark.

```sh
python3 scripts/benchmark_parse_double_gc.py \
  --artifact /path/to/strconv.blackbox_test.wasm \
  --wasmoon /path/to/fresh/release/wasmoon \
  --count 20000 --samples 5
```

This runner measures cold whole-process wall/CPU time, not isolated invocation.
It uses fresh caches, serial alternating engine order, and Wasmtime
`-C parallel-compilation=n -C cache=n`. Compare like phases in the same round;
never compare cold process time with another engine's invocation timer.
Use auto-cleaned OS temporary directories for profiles, dumps, caches and raw
samples; do not commit them or put them under `_build`.

## Final historical measurements

Local macOS ARM64, 2026-10-23, dirty working tree based on `7cf4fe98` before
checkpoint commit `45611d6c`. These are historical observations, not new
measurements of the current head. Five serial fresh-process samples per engine
returned `1`; verification flags were disabled only for timing. The isolated
probe SHA-256 was `fb7bf21507c21de4ffb79126f94cc0846314bd0b03c33060a533f15afe441db1`.

| Same-round comparison | Wasmoon compilation | Reference compilation | Wasmoon invocation | Reference invocation |
| --- | ---: | ---: | ---: | ---: |
| Optimized V8 | 0.885581 s | 0.454163 s | 2.062075 s | 0.782378 s |
| Wasmtime Copying GC API, separate round | 1.074480 s | 0.333068 s | 2.344665 s | 2.368019 s |

V8 was Node 25.2.1 / V8 14.1.146.11-node.14, with
`--no-liftoff --no-wasm-lazy-compilation --wasm-num-compilation-tasks=1`.
Wasmtime was 49.0.1, source `46c23a87dac1465986a8ad53ba6a7ae49372857b`,
serial, uncached, with Copying GC. Its API harness and CLI produced identical
native text and accepted each other's artifacts. `Module::new` was the compile
boundary and `Func::call_async` the invocation boundary; Wasmoon's compile phase
excluded parse/validation and code loading. Compiler boundaries therefore differ.
Absolute times from the two rounds must not be combined.

The V8 ratios remain **2.64x invocation / 1.95x compilation**, missing the
requested 1.05x / 1.5x budgets. The separate Wasmtime round finds **0.99x
invocation / 3.23x compile timer**, specific to this workload and these API
boundaries. Further throughput work is deferred in ISS-661 / ISS-671; #568 stays
open. Remaining costs include C ABI crossings for checked views, GC/identity
bookkeeping and compiler preparation. A general CFG-inlining prototype and
unbounded allocation expansion were rejected for their compilation cost.

## Regression and validation boundary

Retained tests cover raw/mismatched layouts, null/bounds traps, aliasing and
zero-trip loops, pointer invalidation, root binding/parking/reentry/tail calls,
nested exception rollback, quotas/failure injection, and admission-cache lifetime.
Removing compaction invalidation reproduced a stale read (99 instead of 17).
Both target selectors are verified; ARM execution alone does not establish x64.

The local implementation checkpoint passed native 3064, wasm 1456, fresh macOS
ASan/UBSan 292 with both controls, Core 258 files / 62563 assertions per lane,
and exact Component suites 59 files / 1385 commands per engine. Those local
sources were dirty, and macOS could not establish LSan acceptance.

After the independent bottom-reference encoding repair, exact commit `40389c3e`
passed all six jobs in [CI run 39934979350](https://github.com/Milky2018/wasmoon/actions/runs/39934979350):
both Windows inventories 3068 tests / 63 packages with expected=executed,
Linux sanitizer 292 with LSan and all positive controls, portable native/actual
wasm each 258 files / 62563 assertions, and all four native TLS isolation gates.
This is functional/platform acceptance, not remote performance measurement.
Intermediate reports, embedded harnesses, raw samples and IR/machine-code dumps
were removed from the maintained tree; their absence does not strengthen these
historical measurement claims.
