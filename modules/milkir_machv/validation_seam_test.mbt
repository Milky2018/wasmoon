///|
fn finalized_function_with_removed_definition() -> @milkir.Function raise {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "mutated_after_finalize",
  )
  builder.add_result(I32)
  let result = builder.iconst_i32(1)
  builder.return_([result])
  let func = builder.finalize()
  func.blocks[0].instructions.clear()
  func
}

///|
test "core lowering rejects a function mutated after finalization" {
  let func = finalized_function_with_removed_definition()
  try @lower.lower_function(func, run_ir_opt=false) catch {
    err => inspect(err, content="UndefinedValue(value_id=0)")
  } noraise {
    _ => fail("expected core lowering to return the validation error")
  }
}

///|
test "dialect lowering rejects a function mutated after finalization" {
  let func = finalized_function_with_removed_definition()
  try
    @lower.lower_dialect_function(
      func,
      "demo",
      fn(_) { None },
      fn(_, _, block, _) { Handled(block) },
      run_ir_opt=false,
    )
  catch {
    err => inspect(err, content="UndefinedValue(value_id=0)")
  } noraise {
    _ => fail("expected dialect lowering to return the validation error")
  }
}

///|
test "dialect lowering applies its explicit adapter verifier" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("invalid_dialect")
  builder.emit_void_ext_inst(ExtOp("demo", "invalid", []), [])
  builder.return_([])
  let func = builder.finalize()
  try
    @lower.lower_dialect_function(
      func,
      "demo",
      fn(_) { Some("demo adapter rejected the extension") },
      fn(_, _, block, _) { Handled(block) },
      run_ir_opt=false,
    )
  catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="demo adapter rejected the extension")
        ),
      )
  } noraise {
    _ => fail("expected dialect lowering to apply adapter validation")
  }
}
