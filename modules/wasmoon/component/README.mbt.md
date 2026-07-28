# Component runtime facade

`Milky2018/wasmoon/component` is the stable embedding package for WebAssembly
components. It combines component parsing, validation, instantiation, export
lookup, WIT-shaped values, and checked calls behind a small API:

```text
component bytes
    -> ComponentRuntime::instantiate
    -> ComponentInstance::bind
    -> ComponentFunction::call
```

Do not import `Milky2018/wasmoon/component/runtime_impl` from ordinary
applications. That package owns canonical ABI adapters, resource tables, the
cooperative async scheduler, core runtime objects, and other mutable
implementation state.

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
```

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

`ComponentRuntime` uses the portable continuation-aware interpreter. Native JIT
selection is a Wasmoon product embedding policy because constructing a native
engine requires Store, core-module, VM context, and hostcall coordination that
must not appear in this stable facade.

The `wasmoon component --run` WASI command path and component conformance runner
continue to use Wasmoon's native JIT by default, with `--no-jit` for
differential testing. General facade and `--invoke` behavior stays independent
of target-specific engine types.
