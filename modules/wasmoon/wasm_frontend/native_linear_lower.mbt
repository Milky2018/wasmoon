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
fn emit_op(
  builder : @milkir.IRBuilder,
  ty : @milkir.Type,
  opcode : @milkir.Opcode,
  operands : Array[@milkir.Value],
) -> @milkir.Value? {
  guard builder.current_block() is Some(block) else { return None }
  let func = builder.get_function()
  let result = func.new_value(ty)
  block.append_inst(func.new_inst(opcode, operands, [result]))
  Some(result)
}

///|
fn push_unary_opcode(
  builder : @milkir.IRBuilder,
  stack : Array[@milkir.Value],
  opcode : @milkir.Opcode,
) -> Bool {
  guard pop_value(stack) is Some(value) else { return false }
  guard emit_op(builder, value.ty, opcode, [value]) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_binary_opcode(
  builder : @milkir.IRBuilder,
  stack : Array[@milkir.Value],
  opcode : @milkir.Opcode,
) -> Bool {
  guard pop_value(stack) is Some(rhs) else { return false }
  guard pop_value(stack) is Some(lhs) else { return false }
  guard emit_op(builder, lhs.ty, opcode, [lhs, rhs]) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_int_cmp(
  builder : @milkir.IRBuilder,
  stack : Array[@milkir.Value],
  cc : @milkir.IntCC,
) -> Bool {
  guard pop_value(stack) is Some(rhs) else { return false }
  guard pop_value(stack) is Some(lhs) else { return false }
  guard emit_op(builder, I32, Icmp(cc), [lhs, rhs]) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_float_cmp(
  builder : @milkir.IRBuilder,
  stack : Array[@milkir.Value],
  cc : @milkir.FloatCC,
) -> Bool {
  guard pop_value(stack) is Some(rhs) else { return false }
  guard pop_value(stack) is Some(lhs) else { return false }
  guard emit_op(builder, I32, Fcmp(cc), [lhs, rhs]) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_select(
  builder : @milkir.IRBuilder,
  stack : Array[@milkir.Value],
) -> Bool {
  guard pop_value(stack) is Some(cond) else { return false }
  guard pop_value(stack) is Some(false_value) else { return false }
  guard pop_value(stack) is Some(true_value) else { return false }
  stack.push(builder.select(cond, true_value, false_value))
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
      LocalTee(idx) => {
        if idx < 0 || idx >= locals.length() {
          return None
        }
        guard stack.last() is Some(value) else { return None }
        locals[idx] = value
      }
      I32Const(value) => stack.push(builder.iconst_i32(value))
      I64Const(value) => stack.push(builder.iconst_i64(value))
      F32Const(value) => stack.push(builder.fconst_f32(value))
      F64Const(value) => stack.push(builder.fconst_f64(value))
      I32Add | I64Add =>
        if !push_binary(stack, fn(lhs, rhs) { builder.iadd(lhs, rhs) }) {
          return None
        }
      I32Sub | I64Sub =>
        if !push_binary(stack, fn(lhs, rhs) { builder.isub(lhs, rhs) }) {
          return None
        }
      I32Mul | I64Mul =>
        if !push_binary(stack, fn(lhs, rhs) { builder.imul(lhs, rhs) }) {
          return None
        }
      I32DivS | I64DivS =>
        if !push_binary_opcode(builder, stack, Sdiv) {
          return None
        }
      I32DivU | I64DivU =>
        if !push_binary_opcode(builder, stack, Udiv) {
          return None
        }
      I32RemS | I64RemS =>
        if !push_binary_opcode(builder, stack, Srem) {
          return None
        }
      I32RemU | I64RemU =>
        if !push_binary_opcode(builder, stack, Urem) {
          return None
        }
      I32And | I64And =>
        if !push_binary_opcode(builder, stack, Band) {
          return None
        }
      I32Or | I64Or =>
        if !push_binary_opcode(builder, stack, Bor) {
          return None
        }
      I32Xor | I64Xor =>
        if !push_binary_opcode(builder, stack, Bxor) {
          return None
        }
      I32Shl | I64Shl =>
        if !push_binary_opcode(builder, stack, Ishl) {
          return None
        }
      I32ShrS | I64ShrS =>
        if !push_binary_opcode(builder, stack, Sshr) {
          return None
        }
      I32ShrU | I64ShrU =>
        if !push_binary_opcode(builder, stack, Ushr) {
          return None
        }
      I32Rotl | I64Rotl =>
        if !push_binary_opcode(builder, stack, Rotl) {
          return None
        }
      I32Rotr | I64Rotr =>
        if !push_binary_opcode(builder, stack, Rotr) {
          return None
        }
      I32Clz | I64Clz =>
        if !push_unary_opcode(builder, stack, Clz) {
          return None
        }
      I32Ctz | I64Ctz =>
        if !push_unary_opcode(builder, stack, Ctz) {
          return None
        }
      I32Popcnt | I64Popcnt =>
        if !push_unary_opcode(builder, stack, Popcnt) {
          return None
        }
      I32Eqz => {
        guard pop_value(stack) is Some(value) else { return None }
        stack.push(builder.icmp_eq(value, builder.iconst_i32(0)))
      }
      I64Eqz => {
        guard pop_value(stack) is Some(value) else { return None }
        stack.push(builder.icmp_eq(value, builder.iconst_i64(0L)))
      }
      I32Eq | I64Eq => if !push_int_cmp(builder, stack, Eq) { return None }
      I32Ne | I64Ne => if !push_int_cmp(builder, stack, Ne) { return None }
      I32LtS | I64LtS => if !push_int_cmp(builder, stack, Slt) { return None }
      I32LtU | I64LtU => if !push_int_cmp(builder, stack, Ult) { return None }
      I32GtS | I64GtS => if !push_int_cmp(builder, stack, Sgt) { return None }
      I32GtU | I64GtU => if !push_int_cmp(builder, stack, Ugt) { return None }
      I32LeS | I64LeS => if !push_int_cmp(builder, stack, Sle) { return None }
      I32LeU | I64LeU => if !push_int_cmp(builder, stack, Ule) { return None }
      I32GeS | I64GeS => if !push_int_cmp(builder, stack, Sge) { return None }
      I32GeU | I64GeU => if !push_int_cmp(builder, stack, Uge) { return None }
      F32Add | F64Add =>
        if !push_binary(stack, fn(lhs, rhs) { builder.fadd(lhs, rhs) }) {
          return None
        }
      F32Sub | F64Sub =>
        if !push_binary(stack, fn(lhs, rhs) { builder.fsub(lhs, rhs) }) {
          return None
        }
      F32Mul | F64Mul =>
        if !push_binary(stack, fn(lhs, rhs) { builder.fmul(lhs, rhs) }) {
          return None
        }
      F32Div | F64Div =>
        if !push_binary_opcode(builder, stack, Fdiv) {
          return None
        }
      F32Min | F64Min =>
        if !push_binary_opcode(builder, stack, Fmin) {
          return None
        }
      F32Max | F64Max =>
        if !push_binary_opcode(builder, stack, Fmax) {
          return None
        }
      F32Neg | F64Neg =>
        if !push_unary_opcode(builder, stack, Fneg) {
          return None
        }
      F32Abs | F64Abs =>
        if !push_unary_opcode(builder, stack, Fabs) {
          return None
        }
      F32Sqrt | F64Sqrt =>
        if !push_unary_opcode(builder, stack, Fsqrt) {
          return None
        }
      F32Eq | F64Eq => if !push_float_cmp(builder, stack, Eq) { return None }
      F32Ne | F64Ne => if !push_float_cmp(builder, stack, Ne) { return None }
      F32Lt | F64Lt => if !push_float_cmp(builder, stack, Lt) { return None }
      F32Gt | F64Gt => if !push_float_cmp(builder, stack, Gt) { return None }
      F32Le | F64Le => if !push_float_cmp(builder, stack, Le) { return None }
      F32Ge | F64Ge => if !push_float_cmp(builder, stack, Ge) { return None }
      Select | SelectTyped(_) => if !push_select(builder, stack) { return None }
      Drop => {
        guard pop_value(stack) is Some(_) else { return None }
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
