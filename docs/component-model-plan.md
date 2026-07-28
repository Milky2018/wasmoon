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
suspend and whether native entry is safe.

Synchronous, native-eligible core calls use the JIT by default. Calls that may
re-enter canonical adapters through imports or indirect tables use the
interpreter conservatively. Suspendable calls always use the continuation-aware
interpreter because native machine stacks are not guest continuations.

The interpreter returns either completed results or a typed suspension with an
owned continuation. A continuation captures the exact operand stack, locals,
frames, labels, and remaining structured control flow. It can be resumed once
or cancelled; resumption retries only the suspended host-call boundary.

## Async Host Contract

The component scheduler is a cooperative, single-threaded event loop. Component
tasks and MoonBit processes are logical tasks; Wasmoon does not require or
model operating-system threads.

Host async functions return pollable futures. Polling must be non-blocking.
When no guest task can progress, the embedding-provided host event-loop hook
waits for external I/O or timer readiness. Waitable-set events wake the owning
task, and the scheduler resumes its stored continuation. Cancellation releases
the continuation and calls the host future's cancellation hook.

No replay cursor or cached host result is part of this protocol. Effects before
a suspension point execute once, and events are consumed once after resumption.

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
