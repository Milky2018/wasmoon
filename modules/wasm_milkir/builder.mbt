///|
fn i32_type() -> @milkir.Type {
  I32
}

///|
fn i64_type() -> @milkir.Type {
  I64
}

///|
pub fn wasm_funcref_type() -> @milkir.Type {
  CallableRef
}

///|
pub fn wasm_externref_type() -> @milkir.Type {
  OpaqueRef
}

///|
fn external_symbol(
  builder : @milkir.FunctionBuilder,
  name : String,
) -> @milkir.ExternalSymbol {
  builder.get_function().declare_external_symbol(name)
}

///|
fn call_runtime(
  builder : @milkir.FunctionBuilder,
  symbol : String,
  result_ty : @milkir.Type?,
  args : Array[@milkir.Value],
) -> @milkir.Value? {
  builder.call_symbol(external_symbol(builder, symbol), result_ty, args)
}

///|
fn emit_wasm_inst(
  builder : @milkir.FunctionBuilder,
  ty : @milkir.Type,
  opcode : WasmOpcode,
  operands : Array[@milkir.Value],
) -> @milkir.Value {
  register_wasm_validator(builder)
  builder.emit_ext_inst(ty, encode(opcode), operands)
}

///|
fn emit_void_wasm_inst(
  builder : @milkir.FunctionBuilder,
  opcode : WasmOpcode,
  operands : Array[@milkir.Value],
) -> Unit {
  register_wasm_validator(builder)
  builder.emit_void_ext_inst(encode(opcode), operands)
}

///|
fn append_multi_result_inst(
  builder : @milkir.FunctionBuilder,
  opcode : WasmOpcode,
  result_types : Array[@milkir.Type],
  args : Array[@milkir.Value],
) -> Array[@milkir.Value] {
  if result_types.length() == 0 {
    emit_void_wasm_inst(builder, opcode, args)
    return []
  }
  register_wasm_validator(builder)
  builder.emit_multi_ext_inst(result_types, encode(opcode), args)
}

///|
pub fn load_mem_base(
  builder : @milkir.FunctionBuilder,
  vmctx : @milkir.Value,
  memidx : Int,
) -> @milkir.Value {
  emit_wasm_inst(builder, i64_type(), LoadMemBase(memidx), [vmctx])
}

///|
pub fn memory_grow(
  builder : @milkir.FunctionBuilder,
  runtime_symbols : RuntimeSymbols,
  vmctx : @milkir.Value,
  memidx : Int,
  delta : @milkir.Value,
  max_pages? : Int,
  is_memory64? : Bool = false,
) -> @milkir.Value {
  let max_pages_value = max_pages.unwrap_or(-1)
  let call_result = call_runtime(
    builder,
    runtime_symbols.memory_grow,
    Some(I32),
    [
      vmctx,
      builder.iconst_i32(memidx),
      delta,
      builder.iconst_i32(max_pages_value),
    ],
  ).unwrap()
  if is_memory64 {
    builder.sextend(I64, call_result)
  } else {
    call_result
  }
}

///|
pub fn memory_size(
  builder : @milkir.FunctionBuilder,
  runtime_symbols : RuntimeSymbols,
  vmctx : @milkir.Value,
  memidx : Int,
  is_memory64? : Bool = false,
) -> @milkir.Value {
  let call_result = call_runtime(
    builder,
    runtime_symbols.memory_size,
    Some(I32),
    [vmctx, builder.iconst_i32(memidx)],
  ).unwrap()
  if is_memory64 {
    builder.uextend(I64, call_result)
  } else {
    call_result
  }
}

///|
pub fn memory_fill(
  builder : @milkir.FunctionBuilder,
  runtime_symbols : RuntimeSymbols,
  vmctx : @milkir.Value,
  memidx : Int,
  dst : @milkir.Value,
  val : @milkir.Value,
  size : @milkir.Value,
) -> Unit {
  call_runtime(builder, runtime_symbols.memory_fill, None, [
    vmctx,
    builder.iconst_i32(memidx),
    dst,
    val,
    size,
  ])
  |> ignore
}

///|
pub fn memory_copy(
  builder : @milkir.FunctionBuilder,
  runtime_symbols : RuntimeSymbols,
  vmctx : @milkir.Value,
  dst_memidx : Int,
  src_memidx : Int,
  dst : @milkir.Value,
  src : @milkir.Value,
  size : @milkir.Value,
) -> Unit {
  call_runtime(builder, runtime_symbols.memory_copy, None, [
    vmctx,
    builder.iconst_i32(dst_memidx),
    builder.iconst_i32(src_memidx),
    dst,
    src,
    size,
  ])
  |> ignore
}

///|
pub fn memory_init(
  builder : @milkir.FunctionBuilder,
  runtime_symbols : RuntimeSymbols,
  vmctx : @milkir.Value,
  memidx : Int,
  data_idx : Int,
  dst : @milkir.Value,
  src : @milkir.Value,
  size : @milkir.Value,
) -> Unit {
  call_runtime(builder, runtime_symbols.memory_init, None, [
    vmctx,
    builder.iconst_i32(memidx),
    builder.iconst_i32(data_idx),
    dst,
    src,
    size,
  ])
  |> ignore
}

///|
pub fn data_drop(
  builder : @milkir.FunctionBuilder,
  runtime_symbols : RuntimeSymbols,
  vmctx : @milkir.Value,
  data_idx : Int,
) -> Unit {
  call_runtime(builder, runtime_symbols.data_drop, None, [
    vmctx,
    builder.iconst_i32(data_idx),
  ])
  |> ignore
}

///|
pub fn table_grow(
  builder : @milkir.FunctionBuilder,
  runtime_symbols : RuntimeSymbols,
  vmctx : @milkir.Value,
  table_idx : Int,
  delta : @milkir.Value,
  init_value : @milkir.Value,
  is_table64? : Bool = false,
) -> @milkir.Value {
  let call_result = call_runtime(
    builder,
    runtime_symbols.table_grow,
    Some(I32),
    [vmctx, builder.iconst_i32(table_idx), delta, init_value],
  ).unwrap()
  if is_table64 {
    builder.sextend(I64, call_result)
  } else {
    call_result
  }
}

///|
pub fn table_fill(
  builder : @milkir.FunctionBuilder,
  runtime_symbols : RuntimeSymbols,
  vmctx : @milkir.Value,
  table_idx : Int,
  dst : @milkir.Value,
  val : @milkir.Value,
  size : @milkir.Value,
) -> Unit {
  call_runtime(builder, runtime_symbols.table_fill, None, [
    vmctx,
    builder.iconst_i32(table_idx),
    dst,
    val,
    size,
  ])
  |> ignore
}

///|
pub fn table_copy(
  builder : @milkir.FunctionBuilder,
  runtime_symbols : RuntimeSymbols,
  vmctx : @milkir.Value,
  dst_table_idx : Int,
  src_table_idx : Int,
  dst : @milkir.Value,
  src : @milkir.Value,
  size : @milkir.Value,
) -> Unit {
  call_runtime(builder, runtime_symbols.table_copy, None, [
    vmctx,
    builder.iconst_i32(dst_table_idx),
    builder.iconst_i32(src_table_idx),
    dst,
    src,
    size,
  ])
  |> ignore
}

///|
pub fn table_init(
  builder : @milkir.FunctionBuilder,
  runtime_symbols : RuntimeSymbols,
  vmctx : @milkir.Value,
  table_idx : Int,
  elem_idx : Int,
  dst : @milkir.Value,
  src : @milkir.Value,
  size : @milkir.Value,
) -> Unit {
  call_runtime(builder, runtime_symbols.table_init, None, [
    vmctx,
    builder.iconst_i32(table_idx),
    builder.iconst_i32(elem_idx),
    dst,
    src,
    size,
  ])
  |> ignore
}

///|
pub fn elem_drop(
  builder : @milkir.FunctionBuilder,
  runtime_symbols : RuntimeSymbols,
  vmctx : @milkir.Value,
  elem_idx : Int,
) -> Unit {
  call_runtime(builder, runtime_symbols.elem_drop, None, [
    vmctx,
    builder.iconst_i32(elem_idx),
  ])
  |> ignore
}

///|
pub fn get_func_ref(
  builder : @milkir.FunctionBuilder,
  func_idx : Int,
) -> @milkir.Value {
  emit_wasm_inst(builder, wasm_funcref_type(), GetFuncRef(func_idx), [])
}

///|
pub fn call_multi(
  builder : @milkir.FunctionBuilder,
  func_idx : Int,
  result_types : Array[@milkir.Type],
  args : Array[@milkir.Value],
) -> Array[@milkir.Value] {
  append_multi_result_inst(builder, WasmCall(func_idx), result_types, args)
}

///|
pub fn return_call_multi(
  builder : @milkir.FunctionBuilder,
  func_idx : Int,
  args : Array[@milkir.Value],
) -> Unit {
  emit_void_wasm_inst(builder, ReturnCall(func_idx), args)
}

///|
pub fn return_call_indirect_multi(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  table_idx : Int,
  callee : @milkir.Value,
  args : Array[@milkir.Value],
) -> Unit {
  let all_args : Array[@milkir.Value] = [callee]
  for arg in args {
    all_args.push(arg)
  }
  emit_void_wasm_inst(
    builder,
    ReturnCallIndirect(type_idx, table_idx),
    all_args,
  )
}

///|
pub fn return_call_ref_multi(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  func_ref : @milkir.Value,
  args : Array[@milkir.Value],
) -> Unit {
  let all_args : Array[@milkir.Value] = [func_ref]
  for arg in args {
    all_args.push(arg)
  }
  emit_void_wasm_inst(builder, ReturnCallRef(type_idx), all_args)
}

///|
pub fn call_indirect_multi(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  table_idx : Int,
  result_types : Array[@milkir.Type],
  callee : @milkir.Value,
  args : Array[@milkir.Value],
) -> Array[@milkir.Value] {
  let all_args : Array[@milkir.Value] = [callee]
  for arg in args {
    all_args.push(arg)
  }
  append_multi_result_inst(
    builder,
    WasmCallIndirect(type_idx, table_idx),
    result_types,
    all_args,
  )
}

///|
pub fn call_ref_multi(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  result_types : Array[@milkir.Type],
  func_ref : @milkir.Value,
  args : Array[@milkir.Value],
) -> Array[@milkir.Value] {
  let all_args : Array[@milkir.Value] = [func_ref]
  for arg in args {
    all_args.push(arg)
  }
  append_multi_result_inst(builder, CallRef(type_idx), result_types, all_args)
}

///|
pub fn struct_new(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  fields : Array[@milkir.Value],
) -> @milkir.Value {
  emit_wasm_inst(builder, Ref, StructNew(type_idx), fields)
}

///|
pub fn struct_new_default(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
) -> @milkir.Value {
  emit_wasm_inst(builder, Ref, StructNewDefault(type_idx), [])
}

///|
pub fn struct_get(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  field_idx : Int,
  struct_ref : @milkir.Value,
  field_type : @milkir.Type,
) -> @milkir.Value {
  emit_wasm_inst(builder, field_type, StructGet(type_idx, field_idx), [
    struct_ref,
  ])
}

///|
pub fn struct_get_s(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  field_idx : Int,
  struct_ref : @milkir.Value,
  byte_width : Int,
) -> @milkir.Value {
  emit_wasm_inst(builder, I32, StructGetS(type_idx, field_idx, byte_width), [
    struct_ref,
  ])
}

///|
pub fn struct_get_u(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  field_idx : Int,
  struct_ref : @milkir.Value,
  byte_width : Int,
) -> @milkir.Value {
  emit_wasm_inst(builder, I32, StructGetU(type_idx, field_idx, byte_width), [
    struct_ref,
  ])
}

///|
pub fn struct_set(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  field_idx : Int,
  struct_ref : @milkir.Value,
  value : @milkir.Value,
) -> Unit {
  emit_void_wasm_inst(builder, StructSet(type_idx, field_idx), [
    struct_ref, value,
  ])
}

///|
pub fn array_new(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  init_value : @milkir.Value,
  length : @milkir.Value,
) -> @milkir.Value {
  emit_wasm_inst(builder, Ref, ArrayNew(type_idx), [init_value, length])
}

///|
pub fn array_new_default(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  length : @milkir.Value,
) -> @milkir.Value {
  emit_wasm_inst(builder, Ref, ArrayNewDefault(type_idx), [length])
}

///|
pub fn array_new_fixed(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  count : Int,
  elements : Array[@milkir.Value],
) -> @milkir.Value {
  emit_wasm_inst(builder, Ref, ArrayNewFixed(type_idx, count), elements)
}

///|
pub fn array_get(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  array_ref : @milkir.Value,
  index : @milkir.Value,
  element_type : @milkir.Type,
) -> @milkir.Value {
  emit_wasm_inst(builder, element_type, ArrayGet(type_idx), [array_ref, index])
}

///|
pub fn array_get_s(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  array_ref : @milkir.Value,
  index : @milkir.Value,
  byte_width : Int,
) -> @milkir.Value {
  emit_wasm_inst(builder, I32, ArrayGetS(type_idx, byte_width), [
    array_ref, index,
  ])
}

///|
pub fn array_get_u(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  array_ref : @milkir.Value,
  index : @milkir.Value,
  byte_width : Int,
) -> @milkir.Value {
  emit_wasm_inst(builder, I32, ArrayGetU(type_idx, byte_width), [
    array_ref, index,
  ])
}

///|
pub fn array_set(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  array_ref : @milkir.Value,
  index : @milkir.Value,
  value : @milkir.Value,
) -> Unit {
  emit_void_wasm_inst(builder, ArraySet(type_idx), [array_ref, index, value])
}

///|
pub fn array_len(
  builder : @milkir.FunctionBuilder,
  array_ref : @milkir.Value,
) -> @milkir.Value {
  emit_wasm_inst(builder, i32_type(), ArrayLen, [array_ref])
}

///|
pub fn array_fill(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  array_ref : @milkir.Value,
  offset : @milkir.Value,
  value : @milkir.Value,
  count : @milkir.Value,
) -> Unit {
  emit_void_wasm_inst(builder, ArrayFill(type_idx), [
    array_ref, offset, value, count,
  ])
}

///|
pub fn array_copy(
  builder : @milkir.FunctionBuilder,
  dst_type_idx : Int,
  src_type_idx : Int,
  dst : @milkir.Value,
  dst_offset : @milkir.Value,
  src : @milkir.Value,
  src_offset : @milkir.Value,
  count : @milkir.Value,
) -> Unit {
  emit_void_wasm_inst(builder, ArrayCopy(dst_type_idx, src_type_idx), [
    dst, dst_offset, src, src_offset, count,
  ])
}

///|
pub fn array_new_data(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  data_idx : Int,
  data_offset : @milkir.Value,
  length : @milkir.Value,
) -> @milkir.Value {
  emit_wasm_inst(builder, Ref, ArrayNewData(type_idx, data_idx), [
    data_offset, length,
  ])
}

///|
pub fn array_new_elem(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  elem_idx : Int,
  elem_offset : @milkir.Value,
  length : @milkir.Value,
) -> @milkir.Value {
  emit_wasm_inst(builder, Ref, ArrayNewElem(type_idx, elem_idx), [
    elem_offset, length,
  ])
}

///|
pub fn array_init_data(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  data_idx : Int,
  array_ref : @milkir.Value,
  arr_offset : @milkir.Value,
  data_offset : @milkir.Value,
  length : @milkir.Value,
) -> Unit {
  emit_void_wasm_inst(builder, ArrayInitData(type_idx, data_idx), [
    array_ref, arr_offset, data_offset, length,
  ])
}

///|
pub fn array_init_elem(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  elem_idx : Int,
  array_ref : @milkir.Value,
  arr_offset : @milkir.Value,
  elem_offset : @milkir.Value,
  length : @milkir.Value,
) -> Unit {
  emit_void_wasm_inst(builder, ArrayInitElem(type_idx, elem_idx), [
    array_ref, arr_offset, elem_offset, length,
  ])
}

///|
pub fn i31_new(
  builder : @milkir.FunctionBuilder,
  value : @milkir.Value,
) -> @milkir.Value {
  emit_wasm_inst(builder, Ref, I31New, [value])
}

///|
pub fn i31_get_s(
  builder : @milkir.FunctionBuilder,
  i31_ref : @milkir.Value,
) -> @milkir.Value {
  emit_wasm_inst(builder, i32_type(), I31GetS, [i31_ref])
}

///|
pub fn i31_get_u(
  builder : @milkir.FunctionBuilder,
  i31_ref : @milkir.Value,
) -> @milkir.Value {
  emit_wasm_inst(builder, i32_type(), I31GetU, [i31_ref])
}

///|
pub fn ref_test(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  nullable : Bool,
  ref_val : @milkir.Value,
) -> @milkir.Value {
  emit_wasm_inst(builder, i32_type(), RefTest(type_idx, nullable), [ref_val])
}

///|
pub fn ref_cast(
  builder : @milkir.FunctionBuilder,
  type_idx : Int,
  nullable : Bool,
  ref_val : @milkir.Value,
  result_type : @milkir.Type,
) -> @milkir.Value {
  emit_wasm_inst(builder, result_type, RefCast(type_idx, nullable), [ref_val])
}

///|
pub fn any_convert_extern(
  builder : @milkir.FunctionBuilder,
  extern_ref : @milkir.Value,
) -> @milkir.Value {
  emit_wasm_inst(builder, Ref, AnyConvertExtern, [extern_ref])
}

///|
pub fn extern_convert_any(
  builder : @milkir.FunctionBuilder,
  any_ref : @milkir.Value,
) -> @milkir.Value {
  emit_wasm_inst(builder, OpaqueRef, ExternConvertAny, [any_ref])
}

///|
pub fn ref_eq(
  builder : @milkir.FunctionBuilder,
  ref1 : @milkir.Value,
  ref2 : @milkir.Value,
) -> @milkir.Value {
  emit_wasm_inst(builder, i32_type(), RefEq, [ref1, ref2])
}

///|
pub fn emit_throw(
  builder : @milkir.FunctionBuilder,
  tag_idx : Int,
  values : Array[@milkir.Value],
) -> Unit {
  emit_void_wasm_inst(builder, Throw(tag_idx), values)
}

///|
pub fn emit_throw_ref(
  builder : @milkir.FunctionBuilder,
  exnref : @milkir.Value,
) -> Unit {
  emit_void_wasm_inst(builder, ThrowRef, [exnref])
}

///|
pub fn try_table_begin(
  builder : @milkir.FunctionBuilder,
  handler_id : Int,
) -> @milkir.Value {
  emit_wasm_inst(builder, i32_type(), TryTableBegin(handler_id), [])
}

///|
pub fn try_table_end(
  builder : @milkir.FunctionBuilder,
  handler_id : Int,
) -> Unit {
  emit_void_wasm_inst(builder, TryTableEnd(handler_id), [])
}

///|
pub fn get_exception_tag(builder : @milkir.FunctionBuilder) -> @milkir.Value {
  emit_wasm_inst(builder, i32_type(), GetExceptionTag, [])
}

///|
pub fn get_exception_value(
  builder : @milkir.FunctionBuilder,
  idx : Int,
) -> @milkir.Value {
  emit_wasm_inst(builder, i64_type(), GetExceptionValue(idx), [])
}

///|
pub fn get_exception_value_count(
  builder : @milkir.FunctionBuilder,
) -> @milkir.Value {
  emit_wasm_inst(builder, i32_type(), GetExceptionValueCount, [])
}

///|
pub fn delegate(builder : @milkir.FunctionBuilder, depth : Int) -> Unit {
  emit_void_wasm_inst(builder, Delegate(depth), [])
}

///|
pub fn spill_locals_for_throw(
  builder : @milkir.FunctionBuilder,
  locals : Array[@milkir.Value],
) -> Unit {
  emit_void_wasm_inst(builder, SpillLocalsForThrow(locals.length()), locals)
}

///|
pub fn get_spilled_local(
  builder : @milkir.FunctionBuilder,
  idx : Int,
) -> @milkir.Value {
  emit_wasm_inst(builder, i64_type(), GetSpilledLocal(idx), [])
}
