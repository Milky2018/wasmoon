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
  entry.append_inst(func.new_inst(Iconst(1L), [], []))
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
  entry.append_inst(func.new_inst(Iadd, [lhs, rhs], [result]))
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "iadd result type")
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
    func.new_inst(Select, [condition, on_true, on_false], [result]),
  )
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "select operand types")
}

///|
test "verify rejects malformed SIMD operand arity" {
  let func = Function::new_empty("bad_simd_arity")
  let lhs = func.add_param(V128)
  let result = func.new_value(V128)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(V128Add32, [lhs], [result]))
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "v128.add32 operand arity")
}

///|
test "verify rejects indirect calls that disagree with their signature" {
  let func = Function::new_empty("bad_indirect_call")
  let callee = func.add_param(Ptr)
  let result = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(CallIndirect(Signature([I32], [I64])), [callee], [result]),
  )
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "call_indirect argument arity")
}

///|
test "verify rejects direct calls that disagree with their signature" {
  let func = Function::new_empty("bad_direct_call")
  let result = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(Call(ExternalSymbol("callee"), Signature([I32], [I64])), [], [
      result,
    ]),
  )
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "call argument arity")
}

///|
test "verify rejects pointer calls that disagree with declared counts" {
  let func = Function::new_empty("bad_pointer_call")
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(CallPtr(2, 1), [], []))
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "call_ptr argument and result counts")
}

///|
test "verify rejects custom instructions that disagree with their contract" {
  let func = Function::new_empty("untyped_custom")
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(Custom("unknown", Signature([I32], [])), [], []),
  )
  entry.set_terminator(Return([]))
  expect_verify_rejection(func, "custom instruction contract")
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
#warnings("-unused_try")
test "builder finalize rejects unverified functions" {
  let builder = FunctionBuilder::FunctionBuilder("invalid_finalized_function")
  try builder.finalize() catch {
    _ => ()
  } noraise {
    _ => fail("expected finalize to reject a function without a terminator")
  }
}
