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
) -> @types.FunctionCode raise LowerError {
  if func_local_idx < 0 || func_local_idx >= mod_.codes.length() {
    raise MissingCode(index=func_local_idx)
  }
  mod_.codes[func_local_idx]
}

///|
fn function_name(mod_ : @types.Module, func_local_idx : Int) -> String {
  match mod_.func_names.get(func_local_idx) {
    Some(name) => name
    None => "wasm_func_\{func_local_idx}"
  }
}

///|
fn lower_body_skeleton(
  func : @milkir.Function,
  entry : @milkir.Block,
  code : @types.FunctionCode,
) -> Unit {
  // TODO(wasm_frontend): lower WebAssembly instructions into ordinary MilkIR
  // operations through EmbeddingEnvironment callbacks.
  match code.body {
    [] => entry.set_terminator(Return([]))
    [Return] => entry.set_terminator(Return([]))
    _ => {
      let inst = func.new_inst(
        Trap("TODO(wasm_frontend): unsupported Wasm instruction body"),
        [],
        [],
      )
      inst.add_metadata(
        Comment("TODO(wasm_frontend): replace skeleton trap with real lowering"),
      )
      entry.append_inst(inst)
      entry.set_terminator(
        TrapExit("TODO(wasm_frontend): unsupported Wasm instruction body"),
      )
    }
  }
}

///|
pub fn lower_function(
  env : EmbeddingEnvironment,
  mod_ : @types.Module,
  func_local_idx : Int,
) -> @milkir.Function raise LowerError {
  let func_type = get_func_type(mod_, func_local_idx)
  let code = get_code(mod_, func_local_idx)
  let signature = wasm_func_type_to_signature(env, func_type)
  let func = @milkir.Function::new(
    function_name(mod_, func_local_idx),
    signature,
  )
  let params : Array[@milkir.Value] = []
  for param in signature.params {
    params.push(func.new_value(param))
  }
  let entry = func.new_block(params)
  lower_body_skeleton(func, entry, code)
  func
}
