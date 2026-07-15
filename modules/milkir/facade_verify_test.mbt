///|
test "public finalize rejects a missing terminator" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("missing_terminator")
  try builder.finalize() catch {
    err =>
      inspect(
        err,
        content=(
          #|MissingTerminator(block_id=0)
        ),
      )
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
    err =>
      inspect(
        err,
        content=(
          #|TypeMismatch(message="return value 0 has type i32, expected i64")
        ),
      )
  } noraise {
    _ => fail("expected finalize to reject a bad return type")
  }
}

///|
test "public finalize leaves extension semantics to an adapter" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("unknown_dialect")
  builder.emit_void_ext_inst(ExtOp("demo", "effect", []), [])
  builder.return_([])
  builder.finalize() |> ignore
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
    err =>
      inspect(
        err,
        content=(
          #|ArityMismatch(message="jump to block 1 expects 1 arguments, got 0")
        ),
      )
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
    err =>
      inspect(
        err,
        content=(
          #|ForeignBlock(block_id=0)
        ),
      )
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
    err =>
      inspect(
        err,
        content=(
          #|ForeignValue(value_id=0)
        ),
      )
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
    err =>
      inspect(
        err,
        content=(
          #|TypeMismatch(message="v128.const expects 16 bytes")
        ),
      )
  } noraise {
    _ => fail("expected verifier to reject the vector payload")
  }
}

///|
test "extension validators receive the complete read-only instruction shape" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("extension_view")
  let input = builder.add_param(I64)
  builder.add_result(I32)
  let views : Array[ExtensionInstView] = []
  let result = builder.emit_ext_inst(I32, ExtOp("demo", "shape", []), [input])
  builder.return_([result])
  let func = builder.finalize()
  func.verify_with_extension_validator("demo", view => {
    views.push(view)
    None
  })
  debug_inspect(
    views,
    content=(
      #|[
      #|  {
      #|    op: { dialect: "demo", opcode: "shape", immediates: <FixedArray: []> },
      #|    operand_types: <ReadOnlyArray: [I64]>,
      #|    result_types: <ReadOnlyArray: [I32]>,
      #|  },
      #|]
    ),
  )
}

///|
test "adapter validation rejects extensions owned by another dialect" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("foreign_dialect")
  builder.emit_void_ext_inst(ExtOp("demo", "effect", []), [])
  builder.return_([])
  let func = builder.finalize()
  try func.verify_with_extension_validator("wasm", fn(_) { None }) catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="extension dialect 'demo' is not owned by adapter 'wasm'")
        ),
      )
  } noraise {
    _ => fail("expected the adapter to reject a foreign dialect")
  }
}
