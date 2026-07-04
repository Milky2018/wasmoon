///|
fn zero_value(builder : @milkir.IRBuilder, ty : @milkir.Type) -> @milkir.Value? {
  match ty {
    I32 => Some(builder.iconst_i32(0))
    I64 | Ref | Ptr => Some(builder.iconst_i64(0L))
    _ => None
  }
}

///|
fn pop_value(stack : Array[@milkir.Value]) -> @milkir.Value? {
  match stack.pop() {
    Some(value) => Some(value)
    None => None
  }
}

///|
fn push_binary(
  stack : Array[@milkir.Value],
  op : (@milkir.Value, @milkir.Value) -> @milkir.Value,
) -> Bool {
  guard pop_value(stack) is Some(rhs) else { return false }
  guard pop_value(stack) is Some(lhs) else { return false }
  stack.push(op(lhs, rhs))
  true
}

///|
fn finish_linear_return(
  builder : @milkir.IRBuilder,
  stack : Array[@milkir.Value],
  result_count : Int,
) -> Bool {
  if stack.length() < result_count {
    return false
  }
  let popped : Array[@milkir.Value] = []
  for _ in 0..<result_count {
    guard pop_value(stack) is Some(value) else { return false }
    popped.push(value)
  }
  let results : Array[@milkir.Value] = []
  for i in 0..<popped.length() {
    results.push(popped[popped.length() - 1 - i])
  }
  builder.return_(results)
  true
}

///|
fn try_lower_linear_function(
  env : EmbeddingEnvironment,
  mod_ : @types.Module,
  func_local_idx : Int,
) -> @milkir.Function? raise LowerError {
  let func_type = get_func_type(mod_, func_local_idx)
  get_code(mod_, func_local_idx)
  let code = mod_.codes[func_local_idx]
  let builder = @milkir.IRBuilder::new(function_name(mod_, func_local_idx))
  let locals : Array[@milkir.Value] = []
  if env.hidden_context_param() is Some(hidden_context_type) {
    builder.add_param(hidden_context_type) |> ignore
  }
  for param in func_type.params {
    locals.push(builder.add_param(wasm_value_type_to_milkir(param)))
  }
  for local_ty in code.locals {
    let milk_ty = wasm_value_type_to_milkir(local_ty)
    guard zero_value(builder, milk_ty) is Some(value) else { return None }
    locals.push(value)
  }
  for result in func_type.results {
    builder.add_result(wasm_value_type_to_milkir(result))
  }
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let stack : Array[@milkir.Value] = []
  let mut terminated = false
  for instr in code.body {
    if terminated {
      // TODO(ISS-023): native wasm_frontend should model unreachable tails
      // directly instead of falling back to the legacy translator.
      return None
    }
    match instr {
      LocalGet(idx) => {
        if idx < 0 || idx >= locals.length() {
          return None
        }
        stack.push(locals[idx])
      }
      LocalSet(idx) => {
        if idx < 0 || idx >= locals.length() {
          return None
        }
        guard pop_value(stack) is Some(value) else { return None }
        locals[idx] = value
      }
      I32Const(value) => stack.push(builder.iconst_i32(value))
      I64Const(value) => stack.push(builder.iconst_i64(value))
      I32Add | I64Add =>
        if !push_binary(stack, fn(lhs, rhs) { builder.iadd(lhs, rhs) }) {
          return None
        }
      I32Mul | I64Mul =>
        if !push_binary(stack, fn(lhs, rhs) { builder.imul(lhs, rhs) }) {
          return None
        }
      Return => {
        if !finish_linear_return(builder, stack, func_type.results.length()) {
          return None
        }
        terminated = true
      }
      Unreachable => {
        builder.trap("unreachable")
        terminated = true
      }
      _ =>
        // TODO(ISS-023): port the remaining Wasm operators/control-flow
        // lowering from the legacy translator into native MilkIR construction.
        return None
    }
  }
  if !terminated &&
    !finish_linear_return(builder, stack, func_type.results.length()) {
    return None
  }
  Some(builder.get_function())
}
