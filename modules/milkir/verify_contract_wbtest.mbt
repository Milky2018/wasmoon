///|
fn expect_verify_rejection(func : Function, context : String) -> Unit raise {
  try func.verify() catch {
    _ => ()
  } noraise {
    _ => fail("expected verifier rejection: \{context}")
  }
}

///|
test "verify rejects duplicate block ids" {
  let func = Function::new_empty("duplicate_block_id")
  let entry = func.new_block([])
  entry.set_terminator(Return([]))
  func.blocks.push(entry)
  expect_verify_rejection(func, "duplicate block id")
}

///|
test "verify rejects missing jump arguments" {
  let func = Function::new_empty("missing_jump_argument")
  let entry = func.new_block([])
  let target_param = func.new_value(I32)
  let target = func.new_block([target_param])
  entry.set_terminator(Jump(target.id, []))
  target.set_terminator(Return([]))
  expect_verify_rejection(func, "jump argument arity")
}

///|
test "verify rejects return value type mismatches" {
  let func = Function::new_empty("bad_return_type")
  func.add_result(I64)
  let value = func.add_param(I32)
  let entry = func.new_block([])
  entry.set_terminator(Return([value]))
  expect_verify_rejection(func, "return value type")
}

///|
test "verify rejects missing instruction results" {
  let func = Function::new_empty("missing_iconst_result")
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Scalar(ScalarOp::IntConst(1L)), [], []))
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "iconst result arity")
}

///|
test "verify rejects instruction result type mismatches" {
  let func = Function::new_empty("bad_iadd_result_type")
  let lhs = func.add_param(I32)
  let rhs = func.add_param(I32)
  let result = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(Scalar(ScalarOp::IntBinary(IntBinaryOp::Add)), [lhs, rhs], [
      result,
    ]),
  )
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "iadd result type")
}

///|
test "verify rejects reference-typed integer arithmetic" {
  let func = Function::new_empty("reference_integer_add")
  let lhs = func.add_param(Ref)
  let rhs = func.add_param(Ref)
  let result = func.new_value(Ref)
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(Scalar(ScalarOp::IntBinary(IntBinaryOp::Add)), [lhs, rhs], [
      result,
    ]),
  )
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "integer arithmetic operand types")
}

///|
test "verify rejects floating-point integer equality" {
  let func = Function::new_empty("floating_integer_equality")
  let lhs = func.add_param(F64)
  let rhs = func.add_param(F64)
  let result = func.new_value(I32)
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(Scalar(ScalarOp::IntCompare(Eq)), [lhs, rhs], [result]),
  )
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "integer equality operand types")
}

///|
test "verify rejects malformed select types" {
  let func = Function::new_empty("bad_select_types")
  let condition = func.add_param(F32)
  let on_true = func.add_param(I32)
  let on_false = func.add_param(I64)
  let result = func.new_value(I32)
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(Scalar(ScalarOp::Select), [condition, on_true, on_false], [
      result,
    ]),
  )
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "select operand types")
}

///|
test "verify rejects narrow loads with non-integer results" {
  let func = Function::new_empty("bad_narrow_load_result")
  let address = func.add_param(Ptr)
  let offset = func.add_param(I64)
  let result = func.new_value(F64)
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(
      Memory(MemoryOp::LoadNarrow(F64, 8, false)),
      [address, offset],
      [result],
    ),
  )
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "narrow load result type")
}

///|
test "verify rejects malformed SIMD operand arity" {
  let func = Function::new_empty("bad_simd_arity")
  let lhs = func.add_param(V128)
  let result = func.new_value(V128)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Vector(V128Add32), [lhs], [result]))
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "v128.add32 operand arity")
}

///|
test "verify rejects direct calls that disagree with their signature" {
  let func = Function::new_empty("bad_direct_call")
  let result = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(
      Call(CallOp::Direct(ExternalSymbol("callee"), Signature([I32], [I64]))),
      [],
      [result],
    ),
  )
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "call argument arity")
}

///|
test "verify rejects pointer calls that disagree with declared counts" {
  let func = Function::new_empty("bad_pointer_call")
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Call(CallOp::Pointer(2, 1)), [], []))
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "call_ptr argument and result counts")
}

///|
test "verify rejects negative pointer call counts" {
  let func = Function::new_empty("negative_pointer_call_counts")
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Call(CallOp::Pointer(-2, 0)), [], []))
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "negative call_ptr argument count")
}

///|
test "builder finalize accepts i64 pointer carriers for call_ptr" {
  let builder = FunctionBuilder::FunctionBuilder("i64_pointer_call")
  let func_ptr = builder.add_param(I64)
  let callee_context = builder.add_param(I64)
  builder.call_ptr(func_ptr, callee_context, [], []) |> ignore
  builder.return_([])
  builder.finalize() |> ignore
}

///|
test "verify rejects a non-pointer call_ptr function carrier" {
  let func = Function::new_empty("floating_function_pointer_call")
  let func_ptr = func.add_param(F64)
  let callee_context = func.add_param(I64)
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(Call(CallOp::Pointer(1, 0)), [func_ptr, callee_context], []),
  )
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "non-pointer call_ptr function carrier")
}

///|
test "verify treats pointer call operands after the callee as ordinary arguments" {
  let func = Function::new_empty("generic_pointer_call_arguments")
  let func_ptr = func.add_param(I64)
  let floating_argument = func.add_param(F64)
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(Call(CallOp::Pointer(1, 0)), [func_ptr, floating_argument], []),
  )
  entry.set_terminator(Return([]))
  inspect(func.verify(), content="()")
}

///|
test "verify rejects extension instructions that disagree with their contract" {
  let func = Function::new_empty("bad_extension_contract")
  let entry = func.new_block([])
  let ext = ExtOp("demo", "checked", FixedArray::make(0, 0))
  entry.append_inst(func.new_inst(Ext(ext, Signature([I32], [])), [], []))
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "extension instruction contract")
}

///|
test "verify_core rejects unresolved dialect operations" {
  let func = Function::new_empty("dialect_is_not_core")
  let entry = func.new_block([])
  let ext = ExtOp::ExtOp("wasm", "example", [])
  entry.append_inst(func.new_inst(Ext(ext, Signature([], [])), [], []))
  entry.set_terminator(Return([]))
  inspect(func.verify(), content="()")
  try func.verify_core() catch {
    UnverifiableInstruction(message~) =>
      inspect(
        message,
        content="unresolved dialect operation wasm.example is not core MilkIR",
      )
    err => fail("unexpected verification error: \{err}")
  } noraise {
    _ => fail("expected core verification to reject dialect operation")
  }
}

///|
#warnings("-unused_try")
test "builder finalize rejects unverified functions" {
  let builder = FunctionBuilder::FunctionBuilder("invalid_finalized_function")
  try builder.finalize() catch {
    _ => ()
  } noraise {
    _ => fail("expected finalize to reject a function without a terminator")
  }
}
