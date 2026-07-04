///|
fn entry_trampoline_type(
  ty : @types.ValueType,
) -> @milkir.Type raise JitPipelineError {
  match ty {
    I32 => I32
    I64 => I64
    F32 => F32
    F64 => F64
    V128 =>
      raise PipelineFailure(
        message="TODO(ISS-022): V128 entry trampolines need MilkIR vector lane extract/insert operations",
      )
    FuncRef
    | ExternRef
    | RefFunc
    | RefExtern
    | RefFuncTyped(_)
    | RefNullFuncTyped(_)
    | AnyRef
    | ExnRef
    | NullRef
    | NullFuncRef
    | NullExnRef
    | NullExternRef
    | RefStruct(_)
    | RefNullStruct(_)
    | RefArray(_)
    | RefNullArray(_)
    | RefAny
    | RefEq
    | RefNullEq
    | RefI31
    | RefNullI31
    | RefStructAbs
    | RefArrayAbs
    | StructRef
    | ArrayRef
    | RefNone => I64
  }
}

///|
fn build_entry_trampoline_milkir(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
) -> @milkir.Function raise JitPipelineError {
  let builder = @milkir.IRBuilder::new("entry_trampoline")
  let vmctx = builder.add_param(Ptr)
  let values_vec = builder.add_param(Ptr)
  let func_ptr = builder.add_param(Ptr)
  builder.add_result(I64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let wasm_args : Array[@milkir.Value] = []
  let mut offset = 0
  for ty in param_types {
    let milk_ty = entry_trampoline_type(ty)
    let loaded = builder.load_ptr(
      milk_ty,
      values_vec,
      builder.iconst_i64(offset.to_int64()),
    )
    wasm_args.push(loaded)
    offset = offset + 8
  }
  let result_values : Array[@milkir.Value] = []
  let result_milk_types : Array[@milkir.Type] = []
  for ty in result_types {
    let milk_ty = entry_trampoline_type(ty)
    result_milk_types.push(milk_ty)
    result_values.push(builder.get_function().new_value(milk_ty))
  }
  let call_args : Array[@milkir.Value] = [func_ptr, vmctx]
  for arg in wasm_args {
    call_args.push(arg)
  }
  entry.append_inst(
    builder
    .get_function()
    .new_inst(
      CallPtr(wasm_args.length(), result_values.length()),
      call_args,
      result_values,
    ),
  )
  for i, result in result_values {
    builder.store_ptr(
      result_milk_types[i],
      values_vec,
      result,
      builder.iconst_i64(offset.to_int64()),
    )
    offset = offset + 8
  }
  builder.return_([builder.iconst_i64(0L)])
  builder.get_function()
}

///|
pub fn can_use_reusable_entry_trampoline(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
) -> Bool {
  // TODO(ISS-022): expand this gate as the reusable entry trampoline gains full
  // production ABI coverage. Today it is intentionally limited to the scalar
  // register-only signature covered by the reusable MilkIR/MachV pipeline test.
  if param_types.length() != 2 || result_types.length() != 1 {
    return false
  }
  param_types[0] is I64 && param_types[1] is I64 && result_types[0] is I64
}

///|
pub fn plan_entry_trampoline_for_target(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
  target : @machv_emit.EmitTarget,
) -> JitIntegrationPlan raise JitPipelineError {
  plan_milkir_integration_for_target(
    build_entry_trampoline_milkir(param_types, result_types),
    target,
  )
}
