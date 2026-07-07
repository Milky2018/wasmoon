///|
fn external_symbol(name : String) -> @instr.ExternalName {
  @instr.ExternalName::new(name)
}

///|
pub fn runtime_helper_symbol(
  ctx : LoweringContext,
  key : String,
) -> @instr.ExternalName {
  match ctx.runtime_helper_symbols.get(key) {
    Some(symbol) => external_symbol(symbol)
    None =>
      abort("Wasm runtime-helper lowering requires explicit runtime symbols")
  }
}
