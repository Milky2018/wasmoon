///|
fn external_symbol(name : String) -> @instr.ExternalName {
  ExternalName(name)
}

///|
pub fn external_helper_symbol(
  ctx : LoweringContext,
  key : String,
) -> @instr.ExternalName {
  match ctx.external_helper_symbols.get(key) {
    Some(symbol) => external_symbol(symbol)
    None => abort("external helper lowering requires explicit symbol mappings")
  }
}
