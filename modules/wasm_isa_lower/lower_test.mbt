///|
fn test_context_slots() -> WasmContextSlots {
  {
    memory0_base: 0,
    function_table: 0,
    table0_base: 0,
    table_directory: 0,
    memory_directory: 0,
    pointer_stride: 8,
  }
}

///|
test "Wasm lowering returns validation errors for unknown opcodes" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("unknown_wasm_opcode")
  @wasm_milkir.get_exception_tag(builder) |> ignore
  builder.emit_void_ext_inst(ExtOp("wasm", "typo", []), [])
  builder.return_([])
  try lower_function(builder.get_function(), test_context_slots()) catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="unknown Wasm MilkIR extension opcode 'typo'")
        ),
      )
  } noraise {
    _ => fail("expected Wasm lowering to return the validation error")
  }
}

///|
test "Wasm lowering does not trust a producer-provided validator" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("untrusted_validator")
  builder.get_function().register_extension_validator("wasm", fn(_) { None })
  builder.emit_void_ext_inst(ExtOp("wasm", "typo", []), [])
  builder.return_([])
  try lower_function(builder.get_function(), test_context_slots()) catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="unknown Wasm MilkIR extension opcode 'typo'")
        ),
      )
  } noraise {
    _ => fail("expected Wasm lowering to apply its trusted validator")
  }
}

///|
test "Wasm lowering returns validation errors for malformed immediates" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "malformed_wasm_immediate",
  )
  @wasm_milkir.get_exception_tag(builder) |> ignore
  builder.emit_void_ext_inst(
    ExtOp(
      "wasm",
      "ref_test",
      FixedArray::makei(2, fn(i) { if i == 0 { 3 } else { 2 } }),
    ),
    [],
  )
  builder.return_([])
  try lower_function(builder.get_function(), test_context_slots()) catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="malformed Wasm MilkIR extension 'ref_test': immediate 1 is a bool flag encoded as 0 or 1, got 2")
        ),
      )
  } noraise {
    _ => fail("expected Wasm lowering to reject malformed immediates")
  }
}

///|
test "Wasm lowering rejects missing fixed results before instruction selection" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "missing_wasm_extension_result",
  )
  @wasm_milkir.get_exception_tag(builder) |> ignore
  builder.emit_void_ext_inst(@wasm_milkir.encode(GetExceptionTag), [])
  builder.return_([])
  try lower_function(builder.get_function(), test_context_slots()) catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="malformed Wasm MilkIR extension 'get_exception_tag': expected results [i32], got []")
        ),
      )
  } noraise {
    _ => fail("expected Wasm lowering to reject a missing extension result")
  }
}

///|
test "Wasm lowering rejects removed memory and table extension names" {
  let rejected : Array[@milkir.VerifyError] = []
  let removed : Array[@milkir.ExtOp] = [
    ExtOp("wasm", "memory_grow", [0]),
    ExtOp("wasm", "table_grow", [0]),
  ]
  for ext in removed {
    let builder = @milkir.FunctionBuilder::FunctionBuilder(
      "removed_wasm_opcode",
    )
    @wasm_milkir.get_exception_tag(builder) |> ignore
    builder.emit_void_ext_inst(ext, [])
    builder.return_([])
    try lower_function(builder.get_function(), test_context_slots()) catch {
      err => rejected.push(err)
    } noraise {
      _ => fail("expected Wasm lowering to reject the removed opcode")
    }
  }
  debug_inspect(
    rejected,
    content=(
      #|[
      #|  UnverifiableInstruction(message="unknown Wasm MilkIR extension opcode 'memory_grow'"),
      #|  UnverifiableInstruction(message="unknown Wasm MilkIR extension opcode 'table_grow'"),
      #|]
    ),
  )
}
