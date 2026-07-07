///|
/// Helpers for target and embedding ABI role queries used in lowering.
///
/// Target scratch choices come from ISA policy. Embedding-specific roles, such
/// as a pinned context pointer, come from `EmbeddingRegRoles`.

///|
fn current_isa(ctx : LoweringContext) -> @isa.ISA {
  ctx.isa
}

///|
pub fn vmctx_index(ctx : LoweringContext) -> Int {
  match ctx.embedding_reg_roles().context {
    Some(preg) => preg.index
    None => abort("embedding context register role is required")
  }
}

///|
pub fn vmctx_preg(ctx : LoweringContext) -> @abi.PReg {
  match ctx.embedding_reg_roles().context {
    Some(preg) => preg
    None => abort("embedding context register role is required")
  }
}

///|
pub fn scratch2_index(ctx : LoweringContext) -> Int {
  current_isa(ctx).scratch_reg_2_index()
}

///|
fn scratch1_index(ctx : LoweringContext) -> Int {
  current_isa(ctx).scratch_reg_1_index()
}

///|
