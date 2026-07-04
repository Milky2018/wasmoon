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
fn emit_void_op(
  builder : @milkir.IRBuilder,
  opcode : @milkir.Opcode,
  operands : Array[@milkir.Value],
) -> Bool {
  guard builder.current_block() is Some(block) else { return false }
  let func = builder.get_function()
  block.append_inst(func.new_inst(opcode, operands, []))
  true
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
fn push_unary_opcode_as(
  builder : @milkir.IRBuilder,
  stack : Array[@milkir.Value],
  ty : @milkir.Type,
  opcode : @milkir.Opcode,
) -> Bool {
  guard pop_value(stack) is Some(value) else { return false }
  guard emit_op(builder, ty, opcode, [value]) is Some(result) else {
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
fn get_global_func_type(
  mod_ : @types.Module,
  func_idx : Int,
) -> @types.FuncType? {
  if func_idx < 0 {
    return None
  }
  if func_idx < mod_.imports.length() {
    match mod_.imports[func_idx].desc {
      Func(type_idx) =>
        if type_idx >= 0 && type_idx < mod_.types.length() {
          match mod_.types[type_idx].composite {
            Func(func_type) => Some(func_type)
            _ => None
          }
        } else {
          None
        }
      _ => None
    }
  } else {
    let local_idx = func_idx - mod_.imports.length()
    if local_idx >= 0 && local_idx < mod_.funcs.length() {
      let type_idx = mod_.funcs[local_idx]
      if type_idx >= 0 && type_idx < mod_.types.length() {
        match mod_.types[type_idx].composite {
          Func(func_type) => Some(func_type)
          _ => None
        }
      } else {
        None
      }
    } else {
      None
    }
  }
}

///|
fn push_direct_call(
  builder : @milkir.IRBuilder,
  stack : Array[@milkir.Value],
  mod_ : @types.Module,
  func_idx : Int,
) -> Bool {
  guard get_global_func_type(mod_, func_idx) is Some(func_type) else {
    return false
  }
  let args : Array[@milkir.Value] = []
  for _ in 0..<func_type.params.length() {
    guard pop_value(stack) is Some(value) else { return false }
    args.push(value)
  }
  args.rev_in_place()
  let result_types = func_type.results.map(wasm_value_type_to_milkir)
  let symbol = @milkir.ExternalSymbol::new("wasm.func.\{func_idx}")
  if result_types.length() == 0 {
    emit_void_op(builder, Call(symbol), args)
  } else {
    let results = builder.call_multi(symbol, result_types, args)
    for result in results {
      stack.push(result)
    }
    true
  }
}

///|
fn push_memory_base(
  builder : @milkir.IRBuilder,
  vmctx : @milkir.Value,
  memidx : Int,
) -> @milkir.Value? {
  emit_op(builder, I64, Custom("wasmoon.LoadMemBase(\{memidx})"), [vmctx])
}

///|
fn extend_memory32_addr(
  builder : @milkir.IRBuilder,
  addr : @milkir.Value,
) -> @milkir.Value? {
  if addr.ty == I64 {
    Some(addr)
  } else {
    emit_op(builder, I64, Uextend, [addr])
  }
}

///|
fn memory32_effective_addr(
  builder : @milkir.IRBuilder,
  vmctx : @milkir.Value,
  memidx : Int,
  wasm_addr : @milkir.Value,
  offset : Int64,
) -> @milkir.Value? {
  guard push_memory_base(builder, vmctx, memidx) is Some(base) else {
    return None
  }
  guard extend_memory32_addr(builder, wasm_addr) is Some(addr_i64) else {
    return None
  }
  let offset_value = builder.iconst_i64(offset)
  let addr_plus_offset = builder.iadd(addr_i64, offset_value)
  Some(builder.iadd(base, addr_plus_offset))
}

///|
fn push_memory_load(
  builder : @milkir.IRBuilder,
  stack : Array[@milkir.Value],
  vmctx : @milkir.Value?,
  mod_ : @types.Module,
  memidx : Int,
  ty : @milkir.Type,
  offset : Int64,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  if memidx != 0 ||
    memidx >= mod_.memories.length() ||
    mod_.memories[memidx].is_memory64 {
    // TODO(ISS-023): copy the legacy FuncEnvironment bounds-check lowering
    // for memory64 and non-zero memories into the native MilkIR frontend.
    return false
  }
  guard pop_value(stack) is Some(wasm_addr) else { return false }
  guard memory32_effective_addr(builder, context, memidx, wasm_addr, offset)
    is Some(effective_addr) else {
    return false
  }
  stack.push(builder.load_ptr(ty, effective_addr, builder.iconst_i64(0L)))
  true
}

///|
fn push_memory_store(
  builder : @milkir.IRBuilder,
  stack : Array[@milkir.Value],
  vmctx : @milkir.Value?,
  mod_ : @types.Module,
  memidx : Int,
  ty : @milkir.Type,
  offset : Int64,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  if memidx != 0 ||
    memidx >= mod_.memories.length() ||
    mod_.memories[memidx].is_memory64 {
    // TODO(ISS-023): copy the legacy FuncEnvironment bounds-check lowering
    // for memory64 and non-zero memories into the native MilkIR frontend.
    return false
  }
  guard pop_value(stack) is Some(value) else { return false }
  guard pop_value(stack) is Some(wasm_addr) else { return false }
  guard memory32_effective_addr(builder, context, memidx, wasm_addr, offset)
    is Some(effective_addr) else {
    return false
  }
  builder.store_ptr(ty, effective_addr, value, builder.iconst_i64(0L))
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
  let mut vmctx : @milkir.Value? = None
  if env.hidden_context_param() is Some(hidden_context_type) {
    vmctx = Some(builder.add_param(hidden_context_type))
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
      F32Ceil | F64Ceil =>
        if !push_unary_opcode(builder, stack, Fceil) {
          return None
        }
      F32Floor | F64Floor =>
        if !push_unary_opcode(builder, stack, Ffloor) {
          return None
        }
      F32Trunc | F64Trunc =>
        if !push_unary_opcode(builder, stack, Ftrunc) {
          return None
        }
      F32Nearest | F64Nearest =>
        if !push_unary_opcode(builder, stack, Fnearest) {
          return None
        }
      F32Eq | F64Eq => if !push_float_cmp(builder, stack, Eq) { return None }
      F32Ne | F64Ne => if !push_float_cmp(builder, stack, Ne) { return None }
      F32Lt | F64Lt => if !push_float_cmp(builder, stack, Lt) { return None }
      F32Gt | F64Gt => if !push_float_cmp(builder, stack, Gt) { return None }
      F32Le | F64Le => if !push_float_cmp(builder, stack, Le) { return None }
      F32Ge | F64Ge => if !push_float_cmp(builder, stack, Ge) { return None }
      I32WrapI64 =>
        if !push_unary_opcode_as(builder, stack, I32, Ireduce) {
          return None
        }
      I64ExtendI32S =>
        if !push_unary_opcode_as(builder, stack, I64, Sextend) {
          return None
        }
      I64ExtendI32U =>
        if !push_unary_opcode_as(builder, stack, I64, Uextend) {
          return None
        }
      I32Extend8S =>
        if !push_unary_opcode_as(builder, stack, I32, Sextend8) {
          return None
        }
      I32Extend16S =>
        if !push_unary_opcode_as(builder, stack, I32, Sextend16) {
          return None
        }
      I64Extend8S =>
        if !push_unary_opcode_as(builder, stack, I64, Sextend8) {
          return None
        }
      I64Extend16S =>
        if !push_unary_opcode_as(builder, stack, I64, Sextend16) {
          return None
        }
      I64Extend32S =>
        if !push_unary_opcode_as(builder, stack, I64, Sextend32) {
          return None
        }
      F32DemoteF64 =>
        if !push_unary_opcode_as(builder, stack, F32, Fdemote) {
          return None
        }
      F64PromoteF32 =>
        if !push_unary_opcode_as(builder, stack, F64, Fpromote) {
          return None
        }
      I32TruncF32S | I32TruncF64S =>
        if !push_unary_opcode_as(builder, stack, I32, FcvtToSint) {
          return None
        }
      I32TruncF32U | I32TruncF64U =>
        if !push_unary_opcode_as(builder, stack, I32, FcvtToUint) {
          return None
        }
      I64TruncF32S | I64TruncF64S =>
        if !push_unary_opcode_as(builder, stack, I64, FcvtToSint) {
          return None
        }
      I64TruncF32U | I64TruncF64U =>
        if !push_unary_opcode_as(builder, stack, I64, FcvtToUint) {
          return None
        }
      F32ConvertI32S | F32ConvertI64S =>
        if !push_unary_opcode_as(builder, stack, F32, SintToFcvt) {
          return None
        }
      F32ConvertI32U | F32ConvertI64U =>
        if !push_unary_opcode_as(builder, stack, F32, UintToFcvt) {
          return None
        }
      F64ConvertI32S | F64ConvertI64S =>
        if !push_unary_opcode_as(builder, stack, F64, SintToFcvt) {
          return None
        }
      F64ConvertI32U | F64ConvertI64U =>
        if !push_unary_opcode_as(builder, stack, F64, UintToFcvt) {
          return None
        }
      I32TruncSatF32S | I32TruncSatF64S =>
        if !push_unary_opcode_as(builder, stack, I32, FcvtToSintSat) {
          return None
        }
      I32TruncSatF32U | I32TruncSatF64U =>
        if !push_unary_opcode_as(builder, stack, I32, FcvtToUintSat) {
          return None
        }
      I64TruncSatF32S | I64TruncSatF64S =>
        if !push_unary_opcode_as(builder, stack, I64, FcvtToSintSat) {
          return None
        }
      I64TruncSatF32U | I64TruncSatF64U =>
        if !push_unary_opcode_as(builder, stack, I64, FcvtToUintSat) {
          return None
        }
      I32ReinterpretF32 =>
        if !push_unary_opcode_as(builder, stack, I32, Bitcast) {
          return None
        }
      I64ReinterpretF64 =>
        if !push_unary_opcode_as(builder, stack, I64, Bitcast) {
          return None
        }
      F32ReinterpretI32 =>
        if !push_unary_opcode_as(builder, stack, F32, Bitcast) {
          return None
        }
      F64ReinterpretI64 =>
        if !push_unary_opcode_as(builder, stack, F64, Bitcast) {
          return None
        }
      Call(func_idx) =>
        if !push_direct_call(builder, stack, mod_, func_idx) {
          return None
        }
      I32Load(memidx, _, offset) =>
        if !push_memory_load(builder, stack, vmctx, mod_, memidx, I32, offset) {
          return None
        }
      I64Load(memidx, _, offset) =>
        if !push_memory_load(builder, stack, vmctx, mod_, memidx, I64, offset) {
          return None
        }
      F32Load(memidx, _, offset) =>
        if !push_memory_load(builder, stack, vmctx, mod_, memidx, F32, offset) {
          return None
        }
      F64Load(memidx, _, offset) =>
        if !push_memory_load(builder, stack, vmctx, mod_, memidx, F64, offset) {
          return None
        }
      I32Store(memidx, _, offset) =>
        if !push_memory_store(builder, stack, vmctx, mod_, memidx, I32, offset) {
          return None
        }
      I64Store(memidx, _, offset) =>
        if !push_memory_store(builder, stack, vmctx, mod_, memidx, I64, offset) {
          return None
        }
      F32Store(memidx, _, offset) =>
        if !push_memory_store(builder, stack, vmctx, mod_, memidx, F32, offset) {
          return None
        }
      F64Store(memidx, _, offset) =>
        if !push_memory_store(builder, stack, vmctx, mod_, memidx, F64, offset) {
          return None
        }
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
