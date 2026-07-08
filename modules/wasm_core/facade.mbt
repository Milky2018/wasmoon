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
  params : Array[@types.ValueType],
  results : Array[@types.ValueType],
  body : Array[@types.Instruction],
  export_name : String,
) -> @types.Module {
  @types.Module::simple(params, results, body, export_name)
}

///|
pub fn func_type(
  params : Array[@types.ValueType],
  results : Array[@types.ValueType],
) -> @types.FuncType {
  { params, results }
}

///|
pub fn func_subtype(
  params : Array[@types.ValueType],
  results : Array[@types.ValueType],
) -> @types.SubType {
  @types.SubType::func(params, results)
}
