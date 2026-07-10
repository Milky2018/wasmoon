///|
fn wasm_value_type_to_milkir(ty : @types.ValueType) -> @milkir.Type {
  match ty {
    I32 => I32
    I64 => I64
    F32 => F32
    F64 => F64
    V128 => V128
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef =>
      @wasm_milkir.wasm_funcref_type()
    ExternRef | RefExtern | NullExternRef => @wasm_milkir.wasm_externref_type()
    _ => Ref
  }
}

///|
fn get_func_type(
  mod_ : @types.Module,
  func_local_idx : Int,
) -> @types.FuncType raise LowerError {
  if func_local_idx < 0 || func_local_idx >= mod_.funcs.length() {
    raise FunctionIndexOutOfRange(index=func_local_idx)
  }
  let type_idx = mod_.funcs[func_local_idx]
  if type_idx < 0 || type_idx >= mod_.types.length() {
    raise TypeIndexOutOfRange(index=type_idx)
  }
  match mod_.types[type_idx].composite {
    Func(func_type) => func_type
    _ => raise NonFunctionType(index=type_idx)
  }
}

///|
fn get_code(
  mod_ : @types.Module,
  func_local_idx : Int,
) -> @types.FunctionCode raise LowerError {
  if func_local_idx < 0 || func_local_idx >= mod_.codes.length() {
    raise MissingCode(index=func_local_idx)
  }
  mod_.codes[func_local_idx]
}

///|
fn module_memory_is_64(mod_ : @types.Module, memidx : Int) -> Bool? {
  if memidx < 0 || memidx >= mod_.memories.length() {
    None
  } else {
    Some(mod_.memories[memidx].is_memory64)
  }
}

///|
fn first_native_capability_gap(
  mod_ : @types.Module,
  body : Array[@types.Instruction],
) -> String? {
  for instr in body {
    match instr {
      MemoryFill(memidx) =>
        if module_memory_is_64(mod_, memidx) == Some(true) {
          return Some(
            "memory64 memory.fill requires a reusable runtime helper ABI",
          )
        }
      MemoryCopy(dst_memidx, src_memidx) => {
        if module_memory_is_64(mod_, dst_memidx) == Some(true) {
          return Some(
            "memory64 memory.copy destination requires a reusable runtime helper ABI",
          )
        }
        if module_memory_is_64(mod_, src_memidx) == Some(true) {
          return Some(
            "memory64 memory.copy source requires a reusable runtime helper ABI",
          )
        }
      }
      MemoryInit(memidx, _) =>
        if module_memory_is_64(mod_, memidx) == Some(true) {
          return Some(
            "memory64 memory.init requires a reusable runtime helper ABI",
          )
        }
      Block(_, nested) | Loop(_, nested) =>
        if first_native_capability_gap(mod_, nested) is Some(reason) {
          return Some(reason)
        }
      If(_, then_body, else_body) => {
        if first_native_capability_gap(mod_, then_body) is Some(reason) {
          return Some(reason)
        }
        if first_native_capability_gap(mod_, else_body) is Some(reason) {
          return Some(reason)
        }
        return Some(
          "general structured if requires block and label-stack lowering",
        )
      }
      Br(_)
      | BrIf(_)
      | BrTable(_, _)
      | BrOnNull(_)
      | BrOnNonNull(_)
      | TryTable(_, _, _) =>
        return Some("structured branches require label-stack lowering")
      _ => ()
    }
  }
  None
}

///|
fn native_lowering_rejection_reason(
  mod_ : @types.Module,
  code : @types.FunctionCode,
) -> String {
  first_native_capability_gap(mod_, code.body).unwrap_or(
    "native linear frontend does not support this function body shape",
  )
}

///|
fn function_name(mod_ : @types.Module, func_local_idx : Int) -> String {
  match mod_.func_names.get(func_local_idx) {
    Some(name) => name
    None => "wasm_func_\{func_local_idx}"
  }
}

///|
pub fn lower_function(
  env : EmbeddingEnvironment,
  mod_ : @types.Module,
  func_local_idx : Int,
) -> @milkir.Function raise LowerError {
  if try_lower_linear_function(env, mod_, func_local_idx) is Some(func) {
    return func
  }
  let code = get_code(mod_, func_local_idx)
  raise UnsupportedNativeLowering(
    index=func_local_idx,
    reason=native_lowering_rejection_reason(mod_, code),
  )
}

///|
pub fn try_lower_native_function(
  env : EmbeddingEnvironment,
  mod_ : @types.Module,
  func_local_idx : Int,
) -> @milkir.Function? raise LowerError {
  match try_lower_linear_function(env, mod_, func_local_idx) {
    Some(func) =>
      if function_contains_custom_opcode(func) {
        None
      } else {
        Some(func)
      }
    None => None
  }
}

///|
fn function_contains_custom_opcode(func : @milkir.Function) -> Bool {
  for block in func.blocks {
    for inst in block.instructions {
      if inst.opcode is Custom(_, _) {
        return true
      }
    }
  }
  false
}
