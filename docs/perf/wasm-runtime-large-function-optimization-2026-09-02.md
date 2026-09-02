# WebAssembly Runtime Large-Function Optimization Survey

Date: 2026-09-02

## Question

Wasmoon currently runs its e-graph pass only when the whole-function MilkIR
instruction count is below 300. This report asks:

1. Which WebAssembly runtimes are strong choices in different deployment
   categories?
2. How do they control optimizer cost for large functions or modules?
3. What should Wasmoon copy, and what should it avoid?

There is no meaningful universal "best runtime" without fixing the workload,
host, cold-start constraints, security model, and required Wasm proposals. The
category labels below therefore describe architectural strengths, not a single
benchmark ranking. This is a source survey, not a new benchmark run.

## Current Wasmoon Policy

At O2 and O3, Wasmoon first performs mandatory cleanup and then calls
`use_egraph_for_instruction_count`. A function with 299 instructions can enter
the e-graph, while a function with 300 instructions cannot. The skipped function
still receives classic folding, GVN, DCE, CFG, and loop passes, but loses all
e-graph-only algebraic rewrites. See
[`opt_driver.mbt`](../../modules/milkir/opt_driver.mbt).

The policy was a valid compile-time emergency brake: Wasmoon's current e-graph
build copies every admitted pure expression in the function into a second
representation before extraction and dominance-scoped elaboration. However,
total function instruction count is only an indirect proxy for that work. It
also creates a sharp code-quality discontinuity at an unrelated boundary.

## Category Leaders and Their Cost-Control Strategies

| Category | Strong representative | Relevant strategy |
| --- | --- | --- |
| Browser lifecycle and peak throughput | V8, JavaScriptCore/WebKit | Interpreter or baseline code first; optimize hot functions later |
| Standalone/server embedding and security | Wasmtime/Cranelift | One bounded optimizing pipeline; optional baseline backend, AOT, and cache |
| Selectable compile-time/throughput trade-off | Wasmer | Choose Singlepass, Cranelift, or LLVM per engine configuration |
| Embedded and small-footprint deployments | WAMR | Interpreter, Fast JIT, LLVM JIT, AOT, lazy compilation, or multi-tier JIT |
| LLVM-based edge/AOT deployment | WasmEdge | Interpreter/JIT/AOT modes and LLVM optimization levels |
| Pure-Go, no-CGo embedding | wazero | Interpreter or compact SSA compiler plus compilation cache |

### Wasmtime and Cranelift

Wasmtime defaults to Cranelift, while Winch is a separately selected low-latency
baseline compiler. Wasmtime does **not** currently start a module in Winch and
automatically tier it to Cranelift: a module is compiled with one strategy or
the other. Its official guidance recommends Winch and caching for low compile
latency, and Cranelift for faster generated code
([fast compilation](https://docs.wasmtime.dev/examples-fast-compilation.html),
[fast execution](https://docs.wasmtime.dev/examples-fast-execution.html),
[no automatic Winch-to-Cranelift tiering](https://docs.wasmtime.dev/stability-platform-support.html#compiler-support)).

Cranelift is the closest comparison to Wasmoon's e-graph. At every non-`None`
optimization level, `Context::optimize` invokes the e-graph pass; the current
driver has no whole-function instruction-count cutoff
([source](https://github.com/bytecodealliance/wasmtime/blob/bf330493f4352546ee2a3435eeb85d75d6328f1b/cranelift/codegen/src/context.rs#L160-L198)).
Instead, it bounds expensive work at the point where it can grow:

- at most 5 rewrite results retained from one ISLE call;
- at most 5 enodes in one e-class;
- rewrite depth limited to 5;
- 500 units of multi-extractor fuel per top-level rewrite.

These limits are visible in the current
[`egraph/mod.rs`](https://github.com/bytecodealliance/wasmtime/blob/bf330493f4352546ee2a3435eeb85d75d6328f1b/cranelift/codegen/src/egraph/mod.rs#L128-L165)
and are enforced while adding alternatives
([source](https://github.com/bytecodealliance/wasmtime/blob/bf330493f4352546ee2a3435eeb85d75d6328f1b/cranelift/codegen/src/egraph/mod.rs#L360-L457)).
The pass remains function-scoped: it keeps a side-effect skeleton, performs
dominance-scoped GVN, applies local rewrite limits, extracts, and elaborates
pure expressions back into the CFG
([pass overview](https://github.com/bytecodealliance/wasmtime/blob/bf330493f4352546ee2a3435eeb85d75d6328f1b/cranelift/codegen/src/egraph/mod.rs#L74-L123)).

Cranelift therefore degrades **the amount of exploration**, not whether an
otherwise eligible function receives the optimizer at all. This is the most
direct model for replacing Wasmoon's threshold.

### V8

V8 uses Liftoff to produce baseline machine code quickly and TurboFan for hot
functions. Current V8 enables Liftoff, dynamic tiering, lazy compilation, and a
per-function execution budget in its Wasm flags
([source](https://chromium.googlesource.com/v8/v8/+/3e6373bb9f915f75f8e5d1d0d64e4d5a7968d1fa/src/flags/flag-definitions.h#2021)).
The official pipeline description explains that calls consume a function's
budget and trigger background TurboFan compilation when it becomes hot
([V8 pipeline](https://v8.dev/docs/wasm-compilation-pipeline)).

Large functions are not simply dropped from compilation. Functions above 4096
wire bytes enter a dedicated "big units" queue which is checked before normal
units
([source](https://chromium.googlesource.com/v8/v8/+/3e6373bb9f915f75f8e5d1d0d64e4d5a7968d1fa/src/wasm/module-compiler.cc#274)).
Optimization decisions are then independently budgeted. For example, current
defaults cap Wasm inlining by both TurboFan graph size and callee wire size, and
loop peeling has its own maximum-size limit
([source](https://chromium.googlesource.com/v8/v8/+/3e6373bb9f915f75f8e5d1d0d64e4d5a7968d1fa/src/flags/flag-definitions.h#2212)).

The important analogue is not background compilation itself. It is that V8
separates:

- whether a function can execute;
- whether the function is hot enough for the optimizing tier; and
- whether one expensive transform, such as inlining or peeling, is profitable.

A local transform budget does not disable all other TurboFan optimizations.

### JavaScriptCore/WebKit

Current JavaScriptCore has three Wasm tiers: the IPInt interpreter, the BBQ
baseline JIT, and the OMG optimizing JIT
([WebKit's current lifecycle description](https://webkit.org/blog/17899/introducing-the-jetstream-3-benchmark-suite/#ipint-support-for-simd)).
BBQ counts entries and loop backedges, then requests OMG compilation for hot
functions. Current defaults expose separate warm-up thresholds and a maximum
OMG candidate cost
([source](https://github.com/WebKit/WebKit/blob/b48581fbde83d2d64cdb46b2d7b8720deaabd336/Source/JavaScriptCore/runtime/OptionsList.h)).

WebKit does contain a whole-function size guard: `shouldOMGJIT` rejects a
function whose encoded body exceeds `maximumOMGCandidateCost`, currently
100,000 bytes
([source](https://github.com/WebKit/WebKit/blob/b48581fbde83d2d64cdb46b2d7b8720deaabd336/Source/JavaScriptCore/wasm/WasmOperations.cpp)).
This superficially resembles Wasmoon's cutoff, but the semantics differ in two
important ways:

1. The rejected function still has IPInt or BBQ code, so the cutoff only denies
   the highest tier rather than all algebraic optimization in the sole compiler.
2. The threshold is tied to top-tier candidate cost and is much higher than
   Wasmoon's cutoff. The units differ—encoded bytes versus post-cleanup IR
   instructions—so their numeric values are not directly comparable.

WebKit also has 5,000/20,000-byte partial-compilation limits whose purpose is to
yield to other compilation work, not to abandon the function
([source](https://github.com/WebKit/WebKit/blob/b48581fbde83d2d64cdb46b2d7b8720deaabd336/Source/JavaScriptCore/runtime/OptionsList.h)).
This is a useful distinction: scheduling slices and optimizer eligibility are
different policies.

### Wasmer

Wasmer exposes several compiler backends rather than hiding all trade-offs
inside one optimizer. Its current documentation classifies Singlepass as very
fast to compile, Cranelift as balanced, and LLVM as slower to compile but more
aggressively optimized
([runtime features](https://docs.wasmer.io/runtime/features/)).

Singlepass explicitly promises linear-time code generation and predictable
compilation for JIT-bomb-sensitive environments
([source](https://github.com/wasmerio/wasmer/blob/8c4b9ee9d33fb2068863fbb3d328683e7e6ff7f5/lib/compiler-singlepass/README.md)).
Its compiler consumes Wasm operators and feeds them directly to a function code
generator
([source](https://github.com/wasmerio/wasmer/blob/8c4b9ee9d33fb2068863fbb3d328683e7e6ff7f5/lib/compiler-singlepass/src/compiler.rs)).
The Cranelift backend inherits Cranelift's local e-graph limits; the LLVM
backend inherits LLVM's heavier optimization pipeline.

The lesson is to expose an honest pipeline trade-off when workloads require
different latency guarantees. Backend choice does not, however, justify a
quality cliff inside Wasmoon's default optimizing compiler.

### WAMR

WAMR offers classic and fast interpreters, Fast JIT, LLVM JIT, AOT, lazy JIT,
and multi-tier JIT. Its current build guide says lazy LLVM JIT compiles in
background threads to reduce startup time for large modules, while multi-tier
mode uses Fast JIT first and LLVM JIT second
([official build guide](https://github.com/bytecodealliance/wasm-micro-runtime/blob/219151f1c78ec9dae54c1c5aca9fbd1a73e95063/doc/build_wamr.md)).

The current implementation compiles Fast-JIT functions, triggers grouped LLVM
ORC compilation, and replaces function pointers as LLVM code becomes available
([source](https://github.com/bytecodealliance/wasm-micro-runtime/blob/219151f1c78ec9dae54c1c5aca9fbd1a73e95063/core/iwasm/interpreter/wasm_loader.c#L6076-L6307)).
This controls module startup by changing *when* expensive code is produced. It
does not provide an e-graph-like regional budget within one huge LLVM function;
that problem is delegated to LLVM.

WAMR is most relevant to Wasmoon as evidence that baseline/optimized tiering
can preserve peak quality without putting all optimization on the cold path.
It is a longer-term architectural option, not a prerequisite for fixing the
300-instruction cutoff.

### WasmEdge

WasmEdge exposes interpreter, JIT, and AOT modes and LLVM optimization levels
from O0 through Oz
([C API documentation](https://wasmedge.org/docs/embed/c/reference/latest/#aot-compiler-options)).
The CLI defaults to interpreting an uncompiled Wasm file and can load an AOT
artifact instead
([CLI documentation](https://wasmedge.org/docs/start/build-and-run/cli/)).

Its principal answer to compile cost is deployment policy: precompile when peak
performance matters, lower the LLVM optimization level when latency matters,
or interpret. This moves expensive work off the request path but does not
provide a fine-grained answer for Wasmoon's e-graph implementation.

### wazero

wazero is a useful category leader for pure-Go, no-CGo embedding. It supports a
default compiler, a portable interpreter, and a reusable compilation cache
([official repository](https://github.com/tetratelabs/wazero/tree/f4779551afb474c7f2ac79929ce2b3390197544c),
[runtime configuration](https://github.com/tetratelabs/wazero/blob/f4779551afb474c7f2ac79929ce2b3390197544c/config.go)).
Its current SSA optimizer is a compact sequence of classic CFG, phi, no-op, and
dead-code passes rather than equality saturation
([source](https://github.com/tetratelabs/wazero/blob/f4779551afb474c7f2ac79929ce2b3390197544c/internal/engine/wazevo/ssa/pass.go)).

This gives predictable implementation complexity, but it is not a model for
retaining Wasmoon's existing e-graph-only algebraic optimizations.

## Cross-Compiler Findings

### 1. A whole-function cutoff is acceptable only when a lower tier remains

WebKit can reject a very large function from OMG because BBQ remains usable.
V8 can delay TurboFan because Liftoff remains usable. Wasmoon's e-graph is not a
separate executable tier: skipping it permanently removes optimization
opportunities from the only optimizing pipeline. The same policy therefore has
a different quality cost.

### 2. Budget the source of combinatorial growth

Cranelift limits matches, e-class size, rewrite depth, and extractor work.
V8 limits individual transformations such as inlining and loop peeling. Neither
uses total function instruction count as the only proxy for all optimizer work.

For Wasmoon, relevant cost counters are:

- admitted pure MilkIR expressions;
- constructed e-classes and enodes;
- rule applications and rule-match attempts;
- extractor work;
- newly elaborated MilkIR instructions;
- peak e-graph memory.

### 3. Preserve cheap whole-function passes

All surveyed optimizing systems retain cheap canonicalization, CFG cleanup, or
baseline compilation when expensive work is denied. Wasmoon's existing DCE,
constant folding, alias canonicalization, GVN, and CFG passes should remain
independent of the e-graph budget.

### 4. Hotness and profitability are better signals than static size alone

V8 and WebKit tier per function based on execution. Their expensive local
transforms have separate profitability limits. A future Wasmoon tiering system
could use execution counts, but the immediate e-graph repair should not depend
on background or parallel compilation.

### 5. Graceful degradation must be deterministic

When a budget is exhausted, the compiler should stop adding alternatives and
extract the best valid expression already available, or preserve the original
expression for that region. It should not abandon unrelated regions and should
not let map iteration order decide which half of the function gets optimized.

## Recommended Wasmoon Design

### Immediate change: replace the gate with a work budget

Remove `use_egraph_for_instruction_count`. At O2/O3, every function should be
eligible for e-graph processing. Make construction incremental so the pass does
not copy every admitted expression before it can observe its budget. Extend the
existing Cranelift-style 5-match and 5-enode limits with explicit function-pass
counters for:

- total admitted e-graph nodes;
- total rule attempts/applications;
- total extraction work;
- total elaborated instructions.

Budget exhaustion should freeze further growth and preserve the original form
where no extracted improvement is available. It must not skip ordinary GVN or
cleanup passes.

This is the smallest change that removes the 299/300 cliff, but a single global
fuel counter can still favor whichever expressions happen to be visited first.

### Preferred change: optimize bounded pure-expression regions

Partition e-graph work by pure-expression connected components rooted at the
side-effect skeleton, terminators, and other observable uses. Give every region
a small independent budget and an optional function-wide ceiling. Small regions
inside a 10,000-instruction function then receive the same algebraic treatment
as the same regions inside a 100-instruction function.

Keep classic dominance-scoped GVN function-wide so region partitioning does not
discard inexpensive cross-block reuse. This combination mirrors the useful
parts of Cranelift—function-wide scope and local bounds—without requiring
Wasmoon to copy the whole function into one e-graph before doing useful work.

### Optional later change: add a baseline tier

If cold-start and peak throughput cannot be reconciled in one pipeline, a
baseline compiler plus hot-function recompilation is proven by V8, WebKit, and
WAMR. It is a major runtime/code-patching feature and should be evaluated
separately. It is not an excuse to retain the current cutoff.

## Required Regression and Performance Gates

1. Code-quality continuity at 299, 300, and 301 instructions for the same local
   e-graph-only rewrite.
2. A large function with a profitable small region near the beginning and
   another near the end; both must optimize.
3. A large function dominated by side effects but containing few admitted pure
   nodes; its e-graph cost should track admitted nodes, not total instructions.
4. An adversarial rewrite-growth case that hits each fuel limit without
   failure, nondeterminism, or excessive memory.
5. Existing AEGIS cold-compilation timing and the slowest corpus examples,
   measured serially under the repository's established Wasmtime comparison
   rules.
6. Per-pass telemetry for nodes, classes, rule attempts, applications,
   extractor work, elaborated instructions, elapsed time, and budget reason.

## Conclusion

Wasmoon's 300-instruction cutoff is not representative of the strongest
industry designs. The closest peer, Cranelift, runs its e-graph for every
optimized function and bounds local growth. Browser engines use tiers so that
denying or delaying top-tier work never removes the baseline. WebKit's genuine
large-function top-tier cutoff is safe precisely because BBQ remains.

The recommended direction is therefore:

1. remove the whole-function e-graph eligibility cliff;
2. bound the actual sources of optimizer work;
3. distribute work fairly across pure-expression regions;
4. preserve the original expression on budget exhaustion; and
5. consider runtime tiering only as a separate, later architecture project.
