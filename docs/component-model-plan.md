# Component Model Architecture

Wasmoon layers the WebAssembly Component Model above its validated core Wasm
runtime. Component parsing, validation, linking, canonical ABI adaptation, and
WASI component hosts remain product-owned code; embedded core modules reuse the
same runtime objects, interpreter, and native compiler as ordinary core Wasm.

## Package Boundaries

- `wasmoon/component`: stable parse, validation, instantiation, typed-value, and
  invocation facade.
- `wasmoon/component/model`: component binary data model and section parsers.
- `wasmoon/validator/component_model`: component validation.
- `wasmoon/component/runtime_impl`: linker, instantiation, canonical ABI,
  resources, tasks, streams, futures, and host adapters.
- `wasmoon/wasi_component`: WASI Preview 2 and Preview 3 component hosts.
- `wasmoon/cmd/wasmoon`: command execution and component-spec test harness.

Component execution does not add product dependencies to reusable compiler
modules. The component runtime selects a core execution engine through an
adapter owned by Wasmoon.

Ordinary embedders depend only on the root component facade. The validator and
runtime implementation depend directly on `component/model`, so the root
package can compose them without a dependency cycle. Public facade signatures
do not contain runtime implementation types.

## Core Execution Contract

Each instantiated core module is registered with a `CoreExecutionEngine`.
Component function references retain that engine and declare whether a call may
suspend, whether native entry is permitted, and which execution shape is
required:

- run-to-completion calls enter native code and return ordinary core results;
- callback steps enter native code once per scheduler decision and return
  normally to the component scheduler;
- stackful calls enter native code on a guarded fiber stack. A suspending
  canonical hostcall parks that activation and returns an opaque continuation.

Resuming a native continuation restores the original machine stack, trap
activation chain, hostcall context, and precise GC roots. It continues after
the exact hostcall boundary and never replays the core function from entry.
Explicit interpreter mode uses the equivalent structured interpreter
continuation. A continuation is linear: the component runtime must either
resume it to another suspension or terminal return, or cancel it.

`PreferNative` is strict. Failure to compile or enter native code is a
structured component runtime error, not an implicit interpreter fallback.
Imported and re-exported functions that are intentionally interpreter-owned
request `InterpreterOnly` explicitly.

## Async Host Contract

The component scheduler is a cooperative, single-threaded event loop. Component
tasks and MoonBit processes are logical tasks; Wasmoon does not create or model
operating-system threads. A Store and every continuation derived from it remain
on the thread that created them. Parked continuations may coexist, but only one
component entry chain is active at a time; nested native entry is tracked as
part of that chain.

Host async functions return pollable futures. Polling must be non-blocking.
`wasmoon/async_native` owns opaque native registrations and translates macOS
kqueue or Linux epoll events directly into `Pending`, `Ready`, or `Cancelled`
state without retaining guest state. When no guest task can progress, the WASI
host waits in that reactor. The component runtime owns guest-visible task and
waitable identity and resumes the stored continuation after observing
readiness.

Cancellation is cooperative and terminal. Ready or suspended work can be
cancelled at scheduler and hostcall boundaries; an actively running native
activation is not asynchronously preempted. Cancellation removes native
registrations, calls the host future cancellation hook, releases the
continuation stack and parked GC roots, and rejects stale late events.

No replay cursor or cached host result is part of this protocol. Effects before
a suspension point execute once, and events are consumed once after resumption.

## Supported Native Contract

The supported native WASI 0.3 targets are macOS AArch64 and Linux AMD64. The
component linker must remain alive while any call or continuation exists.
Embeddings must finish or cancel all continuations and then call
`ComponentLinker::close`; close is terminal and idempotent and releases native
code and trampoline mappings.

The stable `Milky2018/wasmoon/component` facade does not expose fibers,
platform-reactor contexts, native descriptors, Store internals, or mutable
scheduler queues. Those details remain in Wasmoon-owned implementation
packages.

The following are explicit non-goals:

- Windows native Component Async execution;
- multi-threaded access to one Store;
- moving a continuation to another thread;
- serializing or persisting a live continuation;
- preempting guest code at arbitrary machine instructions.

## Validation

The pinned component-model snapshot is divided into stable 0.2, current 0.3
async, and future-gated suites. Each suite can run with the default JIT adapter
or with `--no-jit`:

```bash
python3 scripts/run_component_wast.py --suite stable-0.2
python3 scripts/run_component_wast.py --suite stable-0.2 --no-jit
python3 scripts/run_component_wast.py --suite async-0.3
python3 scripts/run_component_wast.py --suite async-0.3 --no-jit
python3 scripts/run_component_wast.py --suite future-gated
python3 scripts/run_component_wast.py --suite future-gated --no-jit
```

Known unsupported specification features are recorded in
`docs/component/unsupported-matrix.md`.

Adversarial validation, the pinned current-Wasmtime differential, logical
resource cleanup, and generated large-component campaigns are documented in
`docs/component-security.md`. These gates are regression evidence, not a claim
that the runtime is safe for untrusted production workloads.
