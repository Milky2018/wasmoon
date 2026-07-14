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
      fn(_, _, block, _) { Handled(block) },
      run_ir_opt=false,
    )
  catch {
    err => inspect(err, content="UndefinedValue(value_id=0)")
  } noraise {
    _ => fail("expected dialect lowering to return the validation error")
  }
}
