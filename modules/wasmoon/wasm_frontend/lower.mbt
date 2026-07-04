///|
fn wasm_value_type_to_milkir(ty : @types.ValueType) -> @milkir.Type {
  match ty {
    I32 => I32
    I64 => I64
    F32 => F32
    F64 => F64
    V128 => V128
    _ => Ref
  }
}

///|
fn wasm_func_type_to_signature(
  env : EmbeddingEnvironment,
  func_type : @types.FuncType,
) -> @milkir.Signature {
  let params : Array[@milkir.Type] = []
  if env.hidden_context_param() is Some(hidden_context_type) {
    params.push(hidden_context_type)
  }
  for param in func_type.params {
    params.push(wasm_value_type_to_milkir(param))
  }
  let results = func_type.results.map(wasm_value_type_to_milkir)
  @milkir.Signature::new(params, results)
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
) -> Unit raise LowerError {
  if func_local_idx < 0 || func_local_idx >= mod_.codes.length() {
    raise MissingCode(index=func_local_idx)
  }
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
  let func_type = get_func_type(mod_, func_local_idx)
  get_code(mod_, func_local_idx)
  let signature = wasm_func_type_to_signature(env, func_type)
  // TODO(ISS-023): replace this bridge with a native Wasm-to-MilkIR frontend
  // so reusable MilkIR no longer depends on the legacy Wasmoon IR translator.
  let legacy_func = @ir.translate_function(
    mod_,
    func_local_idx,
    name=function_name(mod_, func_local_idx),
  )
  legacy_func.to_milkir_with_signature(signature)
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
      if inst.opcode is Custom(_) {
        return true
      }
    }
  }
  false
}
