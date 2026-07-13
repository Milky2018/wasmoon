///|
test "public finalize rejects a missing terminator" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("missing_terminator")
  try builder.finalize() catch {
    MissingTerminator(_) => ()
    err => fail("expected MissingTerminator, got \{err}")
  } noraise {
    _ => fail("expected finalize to reject a missing terminator")
  }
}

///|
test "public finalize rejects a return type mismatch" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("bad_return")
  builder.add_result(I64)
  let value = builder.iconst_i32(1)
  builder.return_([value])
  try builder.finalize() catch {
    TypeMismatch(_) => ()
    err => fail("expected TypeMismatch, got \{err}")
  } noraise {
    _ => fail("expected finalize to reject a bad return type")
  }
}

///|
test "public finalize rejects missing jump arguments" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("bad_jump")
  let target = builder.create_block()
  builder.add_block_param(target, I32) |> ignore
  builder.jump(target, [])
  builder.switch_to_block(target)
  builder.return_([])
  try builder.finalize() catch {
    ArityMismatch(_) => ()
    err => fail("expected ArityMismatch, got \{err}")
  } noraise {
    _ => fail("expected finalize to reject missing jump arguments")
  }
}

///|
test "public builder records a foreign block error" {
  let first = @milkir.FunctionBuilder::FunctionBuilder("first")
  let second = @milkir.FunctionBuilder::FunctionBuilder("second")
  first.switch_to_block(second.current_block())
  first.trap("finish own block")
  try first.finalize() catch {
    ForeignBlock(_) => ()
    err => fail("expected ForeignBlock, got \{err}")
  } noraise {
    _ => fail("expected finalize to report the foreign block")
  }
}

///|
test "public builder records a foreign value error" {
  let first = @milkir.FunctionBuilder::FunctionBuilder("first")
  let foreign = first.add_param(I32)
  let second = @milkir.FunctionBuilder::FunctionBuilder("second")
  let own = second.add_param(I32)
  second.iadd(foreign, own) |> ignore
  second.return_([])
  try second.finalize() catch {
    ForeignValue(_) => ()
    err => fail("expected ForeignValue, got \{err}")
  } noraise {
    _ => fail("expected finalize to report the foreign value")
  }
}

///|
test "public vector constant rejects a payload with the wrong width" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("bad_vector_constant")
  builder.add_result(V128)
  let value = builder.v128_const(b"too short")
  builder.return_([value])
  try builder.finalize() catch {
    TypeMismatch(_) => ()
    err => fail("expected TypeMismatch, got \{err}")
  } noraise {
    _ => fail("expected verifier to reject the vector payload")
  }
}
