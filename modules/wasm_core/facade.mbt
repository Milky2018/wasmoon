///|
/// Root facade for the reusable WebAssembly specification model.
///
/// The complete type model lives in `Milky2018/wasm_core/types`. These helpers
/// keep the root package useful as a stable construction entry point without
/// duplicating the spec-level data definitions.

///|
pub fn empty_module() -> @types.Module {
  @types.Module::empty()
}

///|
pub fn simple_module(
  params : ArrayView[@types.ValueType],
  results : ArrayView[@types.ValueType],
  body : ArrayView[@types.Instruction],
  export_name : String,
) -> @types.Module {
  @types.Module::simple(
    ReadOnlyArray::from_array(params),
    ReadOnlyArray::from_array(results),
    ReadOnlyArray::from_array(body),
    export_name,
  )
}

///|
pub fn func_type(
  params : ArrayView[@types.ValueType],
  results : ArrayView[@types.ValueType],
) -> @types.FuncType {
  {
    params: ReadOnlyArray::from_array(params),
    results: ReadOnlyArray::from_array(results),
  }
}

///|
pub fn func_subtype(
  params : ArrayView[@types.ValueType],
  results : ArrayView[@types.ValueType],
) -> @types.SubType {
  @types.SubType::func(
    ReadOnlyArray::from_array(params),
    ReadOnlyArray::from_array(results),
  )
}
