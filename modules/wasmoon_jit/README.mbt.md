# wasmoon_jit

Wasmoon-specific JIT integration and native runtime glue.

`wasmoon_jit` connects the reusable compiler infrastructure to Wasmoon's
runtime embedding. It owns VMContext layout details, native runtime helpers,
cwasm artifacts, trampolines, WASI bridge glue, and integration planning for
loading generated code into Wasmoon.

## Packages

- `Milky2018/wasmoon_jit`: runtime layout, JIT integration planning,
  trampolines, native glue, runtime symbols, and helper APIs.
- `Milky2018/wasmoon_jit/cwasm`: serialized precompiled-code artifacts.
- `Milky2018/wasmoon_jit/perf`: optional JIT performance metrics.
- `Milky2018/wasmoon_jit/jit_ffi`: native stubs used by the JIT runtime.

## When to use it

Use `wasmoon_jit` from Wasmoon or from a Wasmoon-compatible embedding that
needs VMContext layout, runtime helper symbols, trampolines, cwasm artifacts,
or native glue. Use `milkir`, `machv`, `regalloc`, and `machv_emit` directly
when you want compiler infrastructure without Wasmoon runtime coupling.

## Example: plan MilkIR through the Wasmoon JIT pipeline

This is the Wasmoon-owned path that connects reusable compiler infrastructure
to native code bytes plus the runtime glue Wasmoon must provide.

```moonbit check
///|
test "plan a small MilkIR function for x64 JIT integration" {
  let signature = @milkir.Signature::Signature([I64, I64], [I64])
  let milk = @milkir.Function::Function("add64", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let sum = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Iadd, [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let plan = plan_milkir_integration_for_target(milk, X64)
  inspect(plan.entry_symbol, content="add64")
  debug_inspect(plan.target, content="X64")
  inspect(plan.object.get_bytes().length() > 0, content="true")
  inspect(
    native_glue_covers_jit_ffi_stubs(glue=plan.native_glue),
    content="true",
  )
}
```

## Example: serialize a cwasm artifact

The `cwasm` package stores compiled functions, imports, memories, data
segments, and target metadata in a portable artifact format.

```moonbit check
///|
test "serialize and restore a precompiled module" {
  let mod_ = @cwasm.PrecompiledModule::PrecompiledModule(AArch64)
  mod_.add_type([TYPE_I32], [TYPE_I32])
  mod_.add_import("env", "host_inc", 1, 1)
  let entry = @cwasm.CompiledEntry::CompiledEntry(0, "inc", [0xc3], 0, 0, 1, 1)
  mod_.add_function(entry)
  let encoded = mod_.serialize()
  let decoded = @cwasm.deserialize(encoded)
  debug_inspect(decoded.target, content="AArch64")
  inspect(decoded.import_count(), content="1")
  inspect(decoded.function_count(), content="1")
}
```

## Boundary

This module is intentionally Wasmoon-owned. Generic compiler infrastructure
should remain in `milkir`, `machv`, `regalloc`, `machv_regalloc`,
`machv_emit`, and target modules.
