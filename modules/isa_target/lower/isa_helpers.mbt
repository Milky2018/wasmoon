///|
/// Helpers for ISA role queries used in lowering.
///
/// Keep ISA-dependent register choices out of the lowering logic. The selected
/// ISA is carried by `LoweringContext` and supplied by the embedding pipeline.

///|
fn current_isa(ctx : LoweringContext) -> @isa.ISA {
  ctx.isa
}

///|
fn vmctx_index(ctx : LoweringContext) -> Int {
  current_isa(ctx).vmctx_reg_index()
}

///|
fn vmctx_preg(ctx : LoweringContext) -> @abi.PReg {
  current_isa(ctx).vmctx_preg()
}

///|
fn scratch2_index(ctx : LoweringContext) -> Int {
  current_isa(ctx).scratch_reg_2_index()
}

///|
fn scratch1_index(ctx : LoweringContext) -> Int {
  current_isa(ctx).scratch_reg_1_index()
}

///|
