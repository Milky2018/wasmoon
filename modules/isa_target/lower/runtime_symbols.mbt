///|
fn external_symbol(name : String) -> @instr.ExternalName {
  @instr.ExternalName::new(name)
}

///|
fn wasm_runtime_symbols(ctx : LoweringContext) -> @wasm_milkir.RuntimeSymbols {
  match ctx.wasm_runtime_symbols {
    Some(symbols) => symbols
    None =>
      abort("Wasm runtime-helper lowering requires explicit runtime symbols")
  }
}

///|
fn rt_gc_ref_test(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_ref_test)
}

///|
fn rt_gc_ref_cast(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_ref_cast)
}

///|
fn rt_gc_struct_get(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_struct_get)
}

///|
fn rt_gc_struct_set(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_struct_set)
}

///|
fn rt_gc_array_get(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_array_get)
}

///|
fn rt_gc_array_set(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_array_set)
}

///|
fn rt_gc_array_len(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_array_len)
}

///|
fn rt_gc_array_fill(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_array_fill)
}

///|
fn rt_gc_array_copy(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_array_copy)
}

///|
fn rt_gc_array_new_data(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_array_new_data)
}

///|
fn rt_gc_array_new_elem(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_array_new_elem)
}

///|
fn rt_gc_array_init_data(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_array_init_data)
}

///|
fn rt_gc_array_init_elem(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_array_init_elem)
}

///|
fn rt_gc_type_check_subtype(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_type_check_subtype)
}

///|
fn rt_gc_register_struct_inline(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_register_struct_inline)
}

///|
fn rt_gc_register_array_inline(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_register_array_inline)
}

///|
fn rt_gc_alloc_struct_slow(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_alloc_struct_slow)
}

///|
fn rt_gc_alloc_array_from_values_slow(
  ctx : LoweringContext,
) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_alloc_array_from_values_slow)
}

///|
fn rt_gc_alloc_array_slow(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).gc_alloc_array_slow)
}

///|
fn rt_exception_try_begin(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).exception_try_begin)
}

///|
fn rt_exception_try_end(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).exception_try_end)
}

///|
fn rt_exception_throw(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).exception_throw)
}

///|
fn rt_exception_throw_tag(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).exception_throw_tag)
}

///|
fn rt_exception_throw_ref(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).exception_throw_ref)
}

///|
fn rt_exception_delegate(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).exception_delegate)
}

///|
fn rt_exception_get_tag(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).exception_get_tag)
}

///|
fn rt_exception_get_value(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).exception_get_value)
}

///|
fn rt_exception_get_value_count(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).exception_get_value_count)
}

///|
fn rt_exception_sigsetjmp(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).exception_sigsetjmp)
}

///|
fn rt_exception_spill_locals(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).exception_spill_locals)
}

///|
fn rt_exception_get_spilled_local(ctx : LoweringContext) -> @instr.ExternalName {
  external_symbol(wasm_runtime_symbols(ctx).exception_get_spilled_local)
}
