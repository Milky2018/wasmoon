///|
test "tiny integer callees inline without retaining a call or root boundary" {
  let callee = @milkir.FunctionBuilder::FunctionBuilder("extend")
  callee.add_param(I64) |> ignore // Frontend execution environment.
  let value = callee.add_param(I32)
  callee.add_result(I64)
  callee.return_([callee.sextend(I64, value)])
  let b = @milkir.FunctionBuilder::FunctionBuilder("caller")
  let arg = b.add_param(I32)
  b.add_result(I64)
  b.return_([@wasm_milkir.call_multi(b, 0, [I64], [arg])[0]])
  let context = @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { Some({ params: [I32], results: [I64], }) },
    defined_type_contract: fn(_) { None },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
  let function = b.get_function()
  for id in function.block_instruction_ids(function.blocks[0]) {
    function
    .instruction_by_id(id)
    .unwrap()
    .add_metadata(SourceLoc("caller.wasm:17"))
  }
  @optimize.optimize_with_level(
    function,
    context,
    O2,
    scalar_callees=Map([(0, callee.get_function())]),
  )
  |> ignore
  let mut calls = 0
  let mut has_source = false
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      if @wasm_milkir.decode_opcode(
          function.instruction_by_id(id).unwrap().opcode,
        )
        is Some(WasmCall(_)) {
        calls += 1
      }
      for metadata in function.instruction_by_id(id).unwrap().metadata {
        if metadata is SourceLoc("caller.wasm:17") {
          has_source = true
        }
      }
    }
  }
  assert_eq(calls, 0)
  assert_true(has_source)
}

///|
test "integer inlining excludes effectful callees and preserves O0 O1" {
  for
    (effectful, level) in [
      (true, @generic.OptLevel::O2),
      (false, O0),
      (false, O1),
    ] {
    let callee = @milkir.FunctionBuilder::FunctionBuilder("conversion")
    callee.add_param(I64) |> ignore
    let argument = callee.add_param(I32)
    callee.add_result(I64)
    if effectful {
      let symbol = callee.get_function().declare_external_symbol("poll")
      callee.call_symbol(symbol, None, []) |> ignore
    }
    callee.return_([callee.sextend(I64, argument)])
    let b = @milkir.FunctionBuilder::FunctionBuilder("effect_caller")
    let input = b.add_param(I32)
    b.add_result(I64)
    b.return_([@wasm_milkir.call_multi(b, 0, [I64], [input])[0]])
    let context = @wasm_milkir.WasmValidationContext::new({
      function_contract: fn(_) { Some({ params: [I32], results: [I64], }) },
      defined_type_contract: fn(_) { None },
      table_contract: fn(_) { None },
      tag_contract: fn(_) { None },
      memory_exists: fn(_) { false },
      data_segment_exists: fn(_) { false },
      element_segment_type: fn(_) { None },
    })
    let function = b.get_function()
    @optimize.optimize_with_level(
      function,
      context,
      level,
      scalar_callees=Map([(0, callee.get_function())]),
    )
    |> ignore
    assert_true(function.print().contains("ext.wasm.call"))
  }
}

///|
test "invalid callee IR is rejected before rewriting the caller" {
  let invalid = @milkir.FunctionBuilder::FunctionBuilder("missing_return")
  let b = @milkir.FunctionBuilder::FunctionBuilder("valid_caller")
  let input = b.add_param(I32)
  b.add_result(I64)
  b.return_([@wasm_milkir.call_multi(b, 0, [I64], [input])[0]])
  let context = @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { Some({ params: [I32], results: [I64], }) },
    defined_type_contract: fn(_) { None },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
  let function = b.get_function()
  let before = function.print()
  let rejected = try {
    @optimize.optimize_with_level(
      function,
      context,
      O2,
      scalar_callees=Map([(0, invalid.get_function())]),
    )
    |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(function.print(), before)
}
