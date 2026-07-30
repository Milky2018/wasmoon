# Component runtime facade

`Milky2018/wasmoon/component` is the stable embedding package for WebAssembly
components. It combines component parsing, validation, instantiation, export
lookup, WIT-shaped values, and checked calls behind a small API:

```text
component bytes
    -> ComponentRuntime::instantiate
    -> ComponentInstance::bind
    -> ComponentFunction::start
    -> ComponentCall::{poll, wait, join, cancel}
```

Do not import `Milky2018/wasmoon/component/runtime_impl` from ordinary
applications. That package owns canonical ABI adapters, resource tables, the
cooperative async scheduler, core runtime objects, and other mutable
implementation state.

`ComponentEngine`, `NativeComponentExecutionEvent`, and
`ComponentHostInstaller` are owned by this package. They are not aliases for
low-level implementation types, so their public methods cannot reveal a
Store-scoped core engine or linker. The native session factory remains an
internal product and conformance seam rather than an ordinary embedding API.

`ComponentHostInstaller` is consumed by the first successful
`ComponentRuntime::install` claim. A WASI command context is likewise owned by
one runtime for its terminal lifetime, even when aliases create multiple
installers. Build a distinct `WasiComponentCtx` for every runtime.

## Invoke an export

The stable facade validates before instantiation and returns structured
`ComponentRuntimeError` values for parse, validation, linking, binding, value,
and invocation failures:

```moonbit skip
///|
let runtime = @component.ComponentRuntime()

///|
let instance = runtime.instantiate("demo", component_bytes)

///|
let increment = instance.bind("math#increment")

///|
let results = increment.call([@component.ComponentValue::U32(41U)])

///|
runtime.close()
```

`call(args)` is the blocking convenience form of `start(args).wait()`. Use
`start` when the embedding needs an explicit invocation lifetime:

```moonbit skip
///|
let call = increment.start([@component.ComponentValue::U32(41U)])

///|
match call.poll() {
  Pending => ()
  Ready(results) => consume(results)
}

///|
let results = call.wait()

///|
let async_results = call.join()

///|
call.cancel()
```

`poll` performs bounded guest progress and a zero-timeout host-event drain; it
never waits for descriptor or timer readiness. `wait` may block in the native
reactor after guest work is exhausted. `join` is a MoonBit async operation: it
cooperatively suspends the current MoonBit process and does not create an
operating-system thread. Cancellation is terminal and idempotent.

Export paths use `#` only to cross component instance exports. A top-level
function is named `run`; a function in an exported interface instance is named
`wasi:cli/run@0.2.11#run`. The separator does not conflict with WIT package,
interface, or version syntax.

`ComponentFunction::type_` returns a stable `ComponentFuncType`.
`ComponentInstance::bind_typed` additionally checks an expected type before
returning a function. The check includes async mode, parameter names and order,
record fields, variant cases, flags, compound types, and a consistent
bidirectional mapping of resource identities.

## Values and JSON

`ComponentValue` represents WIT meaning rather than canonical ABI layout:

- records retain field names instead of becoming anonymous tuples;
- variants and enums retain case names instead of numeric tags;
- flags retain selected names instead of a bitset;
- options and results use explicit value constructors;
- resource values carry an opaque identity and can be passed back to a
  compatible parameter.

The CLI and library use the same schema-directed JSON forms:

| WIT shape | JSON |
| --- | --- |
| scalar | JSON boolean, number, or string |
| `list<T>`, `tuple<...>` | array |
| record | object keyed by field name |
| variant | `{"case":"name"}` or `{"case":"name","value":...}` |
| enum | case-name string |
| flags | array of selected name strings |
| `option<T>` | `null`, `{"some":...}`, or an unwrapped non-null value |
| `result<T, E>` | `{"ok":...}` or `{"err":...}` |

Use `parse_component_value_json` when a `ComponentValueType` is already known.
Use `component_value_to_json` or `component_values_to_json` for output. Signed
and unsigned 64-bit JSON numbers preserve their exact decimal spelling.

## WIT bindings

`Milky2018/wasmoon/wit` turns a resolved world into an eagerly checked binding
set:

```moonbit skip
///|
let resolved = @wit.resolve_package(root_package, dependencies)

///|
let bindings = resolved.bind_world("demo", instance)

///|
let function = bindings.function("math#increment")

///|
let results = function.call([@component.ComponentValue::U32(41U)])
```

Binding is not delayed until the first call. Missing exports and incompatible
WIT signatures fail in `bind_world`; `WitBindings::paths` reports the functions
that were successfully bound. Direct world functions, inline interfaces, local
interfaces, and dependency-package interfaces are supported.

The current checked API is dynamic: it gives generated binding tools a stable
runtime target, but does not itself emit MoonBit source.

## Execution policy

`ComponentRuntime()` uses Wasmoon's strict native engine. Native compilation or
target failures are structured errors and never trigger an implicit
interpreter fallback. Use
`ComponentRuntime(engine=interpreter_component_engine())` when portable
interpreter execution is required. Advanced embedders can retain and reuse a
`ComponentEngine`; it is an immutable configuration produced by a concrete
facade constructor, and each runtime opens an independent execution session.
The facade does not expose a generic session factory.

The `wasmoon component --run` WASI command path and component conformance runner
use Wasmoon's native JIT by default on macOS AArch64 and Linux AMD64, with
`--no-jit` for explicit interpreter execution. Native callback steps return to
the scheduler normally. Stackful calls park an opaque continuation and resume
the original native activation after the suspending hostcall; they are not
replayed and do not silently fall back to the interpreter.

The stable facade exposes only opaque engine, runtime, instance, function, and
call handles. Native fibers, platform reactors, descriptors, Store objects,
and scheduler queues remain private to Wasmoon-owned adapters.

`ComponentRuntime::close` is terminal and idempotent. It rejects new
instantiation, binding, host installation, and calls; cancels every outstanding
`ComponentCall`; closes installed host contexts and their reactor
registrations; and finally closes the execution session and Store resources.
Retained instance, function, and call aliases cannot re-enter a closed runtime.

## Security and hardening

The facade validates component bytes before linker instantiation and returns
structured errors, but the Component Model runtime has not completed an
independent security audit. It must not be treated as a production sandbox for
untrusted components.

Repository hardening includes deterministic malformed-binary and generated
valid-component fuzzing, an official Wasmtime 45.0.0 semantic differential,
logical stream/future/resource lifecycle checks, source-boundary auditing, and
large generated component stress workloads. See
`docs/component-security.md` for the exact threat model, commands, CI budgets,
and retained evidence.
