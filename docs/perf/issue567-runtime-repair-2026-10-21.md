# Issue 567: Native regex execution repair

This is local implementation and measurement evidence on macOS ARM64, based on
`f06da25eca50f4de81552ac6a583e848fcd31d97`. Measurements were recorded from an
explicitly dirty working tree before the repair commit.
It is not Linux/Windows acceptance, a release, or a claim of general Wasmtime
performance parity. See the [source research](issue567-wasmtime-v8-research.md)
and [local receipt](https://github.com/Milky2018/wasmoon/blob/f31c1166d42da776e30841e08e6824f004585c7e/docs/perf/issue567-runtime-repair-local.json).

## Changes and retained contracts

Executable functions share one artifact-owned image, with 64-byte alignment.
Relocation uses the final function addresses; protection and publication occur
after the whole image is ready. Failure releases the staged image. Logical code
quota still charges linked bytes, excluding padding. Trampolines retain their
existing separate ownership. This removes per-function page expansion without
introducing a permanent global arena or changing executable permission policy.

Root scopes and their copied buffers are reused by the execution that owns
them. Only the active chain is scanned. Trap restoration returns popped scopes
to that execution's cache; execution teardown releases both chains. References
are still copied and protected at the same call boundaries. This does not
replace protection with incomplete active-stack-only scanning.

GC objects use immutable Store-canonical physical layouts: packed integers use
one or two bytes, i32/f32 four, i64/f64 eight, v128 sixteen, and references eight.
Allocation, field access and tracing share those layouts. Existing untyped
low-level allocation APIs retain their wide representation. Layout cache denial
does not invalidate canonical type identities and can fall back to that path.
Common subtype field prefixes preserve their offsets.

Live object identities have sparse reclaimable descriptor pages and an ordered
live traversal. Ordinary collection does not recycle logical identities or
change their quota/high-water contract. Sweep and compaction no longer traverse
all historical dead identities. The top-level page directory still grows with
the high-water identity; this is not an identity-reuse design.

Typed graph traversal uses an iterative native owner and query epochs separate
from collector marks. It returns only boundary references to the Store, which
continues to traverse exceptions, continuations and untyped objects. Public
`collect_roots` still materializes the transitive object set. Collection marks
are written only after successful complete discovery in the collection visitor;
rollback queries never collect or change marks. Incomplete discovery preserves
the existing conservative failure behavior. Parked workers, host reentry,
nested exceptions and temporary snapshot quota cleanup retain their contracts.

At precise native allocation safepoints, collection uses a 64 MiB minimum
allowance, then `live_bytes + max(live_bytes, 64 MiB)` after compaction, bounded
by the existing signed offset range. The physical allocation limit and quota
are still enforced. This is an amortized full-collection policy, not a nursery
or a generational collector. Low-level explicit-GC heaps remain explicit.

Instrumented JIT code inlines the no-callback countdown for the current
activation. A callback still takes the runtime path at every poll. Missing or
foreign activation state also takes that path; nested/parked activation changes
clear and rebind the fast-path pointer. No reachable cancellation poll is
removed. An unreachable loop emits its trap without constructing an invalid
poll CFG. Generic embeddings can retain the old runtime-call implementation.

`NativeJITContext.set_cooperative_quantum` and
`JITModule.set_cooperative_scheduling(enabled, quantum=1024)` configure future
invocations. Nonpositive quantum is rejected; active and parked invocations keep
their control snapshot. The default remains 1024. The artifact codegen revision
is `direct-vcode-11`, invalidating artifacts using the old poll protocol. There
is no new CLI flag or module version bump.

## Measurement method

The retained diagnostic probes are byte-identical to the supplied evidence.
Each returns `1` only when its expected regex result matches. Baseline and repair
use freshly built release CLIs, isolated caches, and cancellation/cooperation
disabled. `/usr/bin/time -l` includes compilation and invocation in a fresh
process. Wasmtime uses `-C parallel-compilation=n -C cache=n`; user CPU and wall
seconds are reported separately. This machine has 16 KiB pages.

The earlier single-variable controls establish why packing and root-buffer reuse
were selected. The production changes also alter heap layout and collection;
their combined result must not be presented as the sum of individual speedups.

| Probe | Baseline user CPU (s) | Repair user CPU (s) | Wasmtime user CPU (s) |
| --- | ---: | ---: | ---: |
| ordinary wasm, n=700 | 2.84 | 1.22 | not rerun |
| wasm-gc, n=700 | 8.45 | 5.38 | not rerun |
| ordinary wasm, n=2100 | 25.47 | 9.65 | 7.23 |
| wasm-gc, n=2100 | 118.62 | 51.08 | 45.69 |

The n=2100 GC probe's observed peak RSS fell from 6.65 GiB to 2.16–3.16 GiB.
The same functional implementation varies between those peaks across processes;
the exact allocator/placement contribution is unproven. Do not substitute the
best RSS for a general memory guarantee. The receipt records the final paired
run and its Wasmtime controls, including fixture hashes, values and wall times.

The final n=2100 ordinary/GC wall times are 9.70/51.49 seconds versus Wasmtime's
7.28/45.86. Their CPU ratios are 1.33/1.12 and wall ratios 1.33/1.12 respectively.
The GC repair trades some small-workload CPU for earlier collection: root-scope
reuse alone in the supplied diagnostic held much more heap memory. These are
combined throughput/memory results, not proof that threshold tuning alone helps.

The original, unshortened `string/regex_test.mbt` test 38 also completed with
all original assertions: Wasmoon 90.10 wall / 89.20 user seconds, Wasmtime
199.09 wall / 198.72 user seconds. Both executed the same extracted Wasm SHA256
`caeca33be09e708c12eb48eef9d5dd1eaa858709b546b3d589c9ecca89ab67be` and returned
`1`. Peak RSS was 3.52 GiB / 2.12 GiB respectively. The extraction replaces host
imports with uncalled trap stubs and the imported tag with a local tag, preserves
function indices and module initialization, and checks the original `Ok`
discriminant. It does not shorten `{256}`, the 2400-character input, or its
assertions. Each engine had the same 600-second diagnostic bound.

There is no same-harness pre-repair measurement for this largest test. The
historical downstream timeout used a different host/cooperative driver, so it
does not establish a 600-to-90-second speedup. The receipt records the exact
source file, function and Core revision to distinguish `regex_test.mbt` #38
from the unrelated `string_test.mbt` #38 initially selected by the harness.

## Regression and acceptance scope

Targeted tests cover compact image release/quota/failure phases, warmed scope
reuse under allocator denial, sparse descriptor reclamation, precise physical
sizes and scalar/vector values, packed signed loads, overlapping array copies,
subtype prefixes, graph cycles, signed i31, continuation edges, graph discovery
failure and denied layout preparation. Existing parked/active roots, native
snapshot rollback and actual cancellation/resumption tests remain enabled.

The unreachable-loop regression directly invokes the public IR verifier and
compiles O0/O2 variants. It fails when the reachability fix is removed, without
depending on `VCODE_REGALLOC_VALIDATION` being enabled by the environment.

Current local gates: strict native/wasm, info/fmt, native 2949/2949 with both
`VCODE_REGALLOC_VALIDATION=1` and `WASMOON_GC_VERIFY=1`, wasm 1389/1389, 175 Python
tests with 54 existing platform skips, module boundaries, generated MSVC bridge
consistency and strict compilation of 44 native C stubs. Fresh isolated local
ASan/UBSan covers 260 tests with both positive controls. MoonBit runtime objects
and generated JIT instructions retain the sanitizer runner's documented
instrumentation exclusions. LeakSanitizer is unavailable on macOS.

The final frozen-source run passed all 258 Core files and 62563 assertions with
zero failed/unsupported in both portable native and actual wasm hosts. Actual
CLI interpreter and JIT also each passed all 258 files and 62563 assertions with
both verification flags enabled. Test 38 passed separately as described above.

Cross-platform execution and Linux leak detection still require CI; ARM64
execution does not verify x64 execution. No temporary benchmark variants or
diagnostic environment switches are part of the production implementation.
