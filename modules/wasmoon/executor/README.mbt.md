# Checked Core embedding

Validate once, instantiate the protected snapshot, and call an exported function
with provenance-aware values. `Function` executes through the interpreter; raw
native execution APIs have separate ABI preconditions. See
[Core embedding boundaries](../../../docs/core-embedding.md) for ownership and
migration notes.

```mbt check
///|
test {
  let module_ = @types.Module::simple(
    [I32],
    [I32],
    [LocalGet(0), I32Const(1), I32Add],
    "increment",
  )
  let validated = @validator.ValidatedModule::new(module_)
  let (store, instance) = @executor.instantiate_validated_module_with_init(
    validated,
  )
  defer store.close()
  let increment = @executor.Function::from_export(store, instance, "increment")
  defer increment.close()
  let result = increment.call([@runtime.RootedValue::i32(41)])
  defer result[0].close()
  debug_inspect(result[0].scalar(), content="I32(42)")
}
```

Reference results keep their Store and guest object alive. MoonBit RC releases
roots automatically; `close()` releases them early. Calls reject closed or
rolled-back instances and references from another Store. Async host imports use
`Function.call_async`, whose temporary argument roots also cover suspension and
cancellation.
