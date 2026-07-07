///|
fn runtime_helper_symbol(
  ctx : @lower.LoweringContext,
  key : String,
) -> @instr.ExternalName {
  @lower.runtime_helper_symbol(ctx, key)
}

///|
fn rt_gc_ref_test(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.ref_test")
}

///|
fn rt_gc_ref_cast(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.ref_cast")
}

///|
fn rt_gc_struct_get(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.struct_get")
}

///|
fn rt_gc_struct_set(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.struct_set")
}

///|
fn rt_gc_array_get(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.array_get")
}

///|
fn rt_gc_array_set(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.array_set")
}

///|
fn rt_gc_array_len(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.array_len")
}

///|
fn rt_gc_array_fill(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.array_fill")
}

///|
fn rt_gc_array_copy(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.array_copy")
}

///|
fn rt_gc_array_new_data(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.array_new_data")
}

///|
fn rt_gc_array_new_elem(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.array_new_elem")
}

///|
fn rt_gc_array_init_data(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.array_init_data")
}

///|
fn rt_gc_array_init_elem(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.array_init_elem")
}

///|
fn rt_gc_type_check_subtype(
  ctx : @lower.LoweringContext,
) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.type_check_subtype")
}

///|
fn rt_gc_register_struct_inline(
  ctx : @lower.LoweringContext,
) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.register_struct_inline")
}

///|
fn rt_gc_register_array_inline(
  ctx : @lower.LoweringContext,
) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.register_array_inline")
}

///|
fn rt_gc_alloc_struct_slow(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.alloc_struct_slow")
}

///|
fn rt_gc_alloc_array_from_values_slow(
  ctx : @lower.LoweringContext,
) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.alloc_array_from_values_slow")
}

///|
fn rt_gc_alloc_array_slow(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "gc.alloc_array_slow")
}

///|
fn rt_exception_try_begin(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "exception.try_begin")
}

///|
fn rt_exception_try_end(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "exception.try_end")
}

///|
fn rt_exception_throw(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "exception.throw")
}

///|
fn rt_exception_throw_tag(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "exception.throw_tag")
}

///|
fn rt_exception_throw_ref(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "exception.throw_ref")
}

///|
fn rt_exception_delegate(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "exception.delegate")
}

///|
fn rt_exception_get_tag(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "exception.get_tag")
}

///|
fn rt_exception_get_value(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "exception.get_value")
}

///|
fn rt_exception_get_value_count(
  ctx : @lower.LoweringContext,
) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "exception.get_value_count")
}

///|
fn rt_exception_sigsetjmp(ctx : @lower.LoweringContext) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "exception.sigsetjmp")
}

///|
fn rt_exception_spill_locals(
  ctx : @lower.LoweringContext,
) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "exception.spill_locals")
}

///|
fn rt_exception_get_spilled_local(
  ctx : @lower.LoweringContext,
) -> @instr.ExternalName {
  runtime_helper_symbol(ctx, "exception.get_spilled_local")
}
