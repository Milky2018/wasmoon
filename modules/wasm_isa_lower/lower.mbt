///|
pub fn external_helper_symbols(
  symbols : @wasm_milkir.RuntimeSymbols,
) -> Map[String, String] {
  {
    "memory.grow": symbols.memory_grow,
    "memory.size": symbols.memory_size,
    "memory.fill": symbols.memory_fill,
    "memory.copy": symbols.memory_copy,
    "memory.init": symbols.memory_init,
    "data.drop": symbols.data_drop,
    "table.grow": symbols.table_grow,
    "table.fill": symbols.table_fill,
    "table.copy": symbols.table_copy,
    "table.init": symbols.table_init,
    "elem.drop": symbols.elem_drop,
    "gc.ref_test": symbols.gc_ref_test,
    "gc.ref_cast": symbols.gc_ref_cast,
    "gc.struct_get": symbols.gc_struct_get,
    "gc.struct_set": symbols.gc_struct_set,
    "gc.array_get": symbols.gc_array_get,
    "gc.array_set": symbols.gc_array_set,
    "gc.array_len": symbols.gc_array_len,
    "gc.array_fill": symbols.gc_array_fill,
    "gc.array_copy": symbols.gc_array_copy,
    "gc.array_new_data": symbols.gc_array_new_data,
    "gc.array_new_elem": symbols.gc_array_new_elem,
    "gc.array_init_data": symbols.gc_array_init_data,
    "gc.array_init_elem": symbols.gc_array_init_elem,
    "gc.type_check_subtype": symbols.gc_type_check_subtype,
    "gc.register_struct_inline": symbols.gc_register_struct_inline,
    "gc.register_array_inline": symbols.gc_register_array_inline,
    "gc.alloc_struct_slow": symbols.gc_alloc_struct_slow,
    "gc.alloc_array_from_values_slow": symbols.gc_alloc_array_from_values_slow,
    "gc.alloc_array_slow": symbols.gc_alloc_array_slow,
    "exception.try_begin": symbols.exception_try_begin,
    "exception.try_end": symbols.exception_try_end,
    "exception.throw": symbols.exception_throw,
    "exception.throw_tag": symbols.exception_throw_tag,
    "exception.throw_ref": symbols.exception_throw_ref,
    "exception.delegate": symbols.exception_delegate,
    "exception.get_tag": symbols.exception_get_tag,
    "exception.get_value": symbols.exception_get_value,
    "exception.get_value_count": symbols.exception_get_value_count,
    "exception.sigsetjmp": symbols.exception_sigsetjmp,
    "exception.spill_locals": symbols.exception_spill_locals,
    "exception.get_spilled_local": symbols.exception_get_spilled_local,
  }
}

///|
struct WasmLoweringOptions {
  use_subtype_indirect_check : Bool
  canonical_type_indices : Array[Int]
  context_slots : WasmContextSlots
}

///|
fn WasmLoweringOptions::canonicalize_indirect_type_idx(
  self : WasmLoweringOptions,
  raw_type_idx : Int,
) -> Int {
  // Keep raw indices when full subtype checks are enabled.
  if self.use_subtype_indirect_check {
    return raw_type_idx
  }
  if raw_type_idx >= 0 && raw_type_idx < self.canonical_type_indices.length() {
    self.canonical_type_indices[raw_type_idx]
  } else {
    raw_type_idx
  }
}

///|
fn lower_extension_with_options(
  options : WasmLoweringOptions,
  ctx : @lower.LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  ext : @milkir.ExtOp,
) -> @lower.ExtensionLowerResult {
  let opcode = match @wasm_milkir.decode(ext) {
    Some(opcode) => opcode
    None => abort("Wasm extension changed after successful validation")
  }
  match opcode {
    StructNew(type_idx) =>
      return Handled(lower_struct_new(ctx, inst, block, type_idx))
    ArrayNewFixed(type_idx, len) =>
      return Handled(lower_array_new_fixed(ctx, inst, block, type_idx, len))
    LoadMemBase(memidx) =>
      lower_load_mem_base(ctx, inst, block, memidx, options.context_slots)
    WasmCall(func_idx) => lower_call(ctx, inst, block, func_idx)
    WasmCallIndirect(type_idx, table_idx) =>
      lower_call_indirect(ctx, inst, block, type_idx, table_idx, options)
    CallRef(type_idx) => lower_call_ref(ctx, inst, block, type_idx)
    ReturnCall(func_idx) => lower_return_call(ctx, inst, block, func_idx)
    ReturnCallIndirect(type_idx, table_idx) =>
      lower_return_call_indirect(ctx, inst, block, type_idx, table_idx, options)
    ReturnCallRef(type_idx) => lower_return_call_ref(ctx, inst, block, type_idx)
    GetFuncRef(func_idx) =>
      lower_get_func_ref(ctx, inst, block, func_idx, options.context_slots)
    I31New => lower_i31_new(ctx, inst, block)
    I31GetS => lower_i31_get_s(ctx, inst, block)
    I31GetU => lower_i31_get_u(ctx, inst, block)
    AnyConvertExtern | ExternConvertAny => lower_gc_convert(ctx, inst, block)
    StructNewDefault(type_idx) =>
      lower_struct_new_default(ctx, inst, block, type_idx)
    StructGet(type_idx, field_idx) =>
      lower_struct_get(ctx, inst, block, type_idx, field_idx)
    StructGetS(type_idx, field_idx, byte_width) =>
      lower_struct_get_s(ctx, inst, block, type_idx, field_idx, byte_width)
    StructGetU(type_idx, field_idx, byte_width) =>
      lower_struct_get_u(ctx, inst, block, type_idx, field_idx, byte_width)
    StructSet(type_idx, field_idx) =>
      lower_struct_set(ctx, inst, block, type_idx, field_idx)
    ArrayNew(type_idx) => lower_array_new(ctx, inst, block, type_idx)
    ArrayNewDefault(type_idx) =>
      lower_array_new_default(ctx, inst, block, type_idx)
    ArrayGet(type_idx) => lower_array_get(ctx, inst, block, type_idx)
    ArrayGetS(type_idx, byte_width) =>
      lower_array_get_s(ctx, inst, block, type_idx, byte_width)
    ArrayGetU(type_idx, byte_width) =>
      lower_array_get_u(ctx, inst, block, type_idx, byte_width)
    ArraySet(type_idx) => lower_array_set(ctx, inst, block, type_idx)
    ArrayLen => lower_array_len(ctx, inst, block)
    ArrayFill(type_idx) => lower_array_fill(ctx, inst, block, type_idx)
    ArrayCopy(dst_type, src_type) =>
      lower_array_copy(ctx, inst, block, dst_type, src_type)
    ArrayNewData(type_idx, data_idx) =>
      lower_array_new_data(ctx, inst, block, type_idx, data_idx)
    ArrayNewElem(type_idx, elem_idx) =>
      lower_array_new_elem(ctx, inst, block, type_idx, elem_idx)
    ArrayInitData(type_idx, data_idx) =>
      lower_array_init_data(ctx, inst, block, type_idx, data_idx)
    ArrayInitElem(type_idx, elem_idx) =>
      lower_array_init_elem(ctx, inst, block, type_idx, elem_idx)
    RefTest(type_idx, nullable) =>
      lower_ref_test(ctx, inst, block, type_idx, nullable)
    RefCast(type_idx, nullable) =>
      lower_ref_cast(ctx, inst, block, type_idx, nullable)
    RefEq => lower_ref_eq(ctx, inst, block)
    Throw(tag_idx) => lower_throw(ctx, inst, block, tag_idx)
    ThrowRef => lower_throw_ref(ctx, inst, block)
    TryTableBegin(handler_id) =>
      lower_try_table_begin(ctx, inst, block, handler_id)
    TryTableEnd(handler_id) => lower_try_table_end(ctx, inst, block, handler_id)
    GetExceptionTag => lower_get_exception_tag(ctx, inst, block)
    GetExceptionValue(idx) => lower_get_exception_value(ctx, inst, block, idx)
    GetExceptionValueCount => lower_get_exception_value_count(ctx, inst, block)
    Delegate(depth) => lower_delegate(ctx, inst, block, depth)
    SpillLocalsForThrow(count) =>
      lower_spill_locals_for_throw(ctx, inst, block, count)
    GetSpilledLocal(idx) => lower_get_spilled_local(ctx, inst, block, idx)
  }
  Handled(block)
}

///|
pub fn lower_function(
  func : @milkir.Function,
  context_slots : WasmContextSlots,
  isa? : @isa.ISA = AArch64,
  embedding_abi? : @abi.EmbeddingABI? = None,
  runtime_symbols? : @wasm_milkir.RuntimeSymbols = @wasm_milkir.RuntimeSymbols::with_runtime_prefix(
    "wasm.runtime",
  ),
  num_imports? : Int = -1,
  run_ir_opt? : Bool = true,
  trap_payload_resolver? : (String) -> Int = fn(_reason) { 0 },
  use_subtype_indirect_check? : Bool = true,
  canonical_type_indices? : Array[Int] = [],
) -> @machv.Function raise @milkir.VerifyError {
  @wasm_milkir.verify_function(func)
  let options : WasmLoweringOptions = {
    use_subtype_indirect_check,
    canonical_type_indices,
    context_slots,
  }
  fn lower_extension(
    ctx : @lower.LoweringContext,
    inst : @milkir.Inst,
    block : @block.Block,
    ext : @milkir.ExtOp,
  ) -> @lower.ExtensionLowerResult {
    lower_extension_with_options(options, ctx, inst, block, ext)
  }
  @lower.lower_dialect_function(
    func,
    lower_extension,
    isa~,
    embedding_abi~,
    external_helper_symbols=external_helper_symbols(runtime_symbols),
    trap_payload_resolver~,
    num_imports~,
    run_ir_opt~,
  )
}
