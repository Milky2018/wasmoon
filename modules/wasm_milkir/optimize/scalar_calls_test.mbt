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
    function.instruction_by_id(id).unwrap().add_metadata(SourceByteOffset(71L))
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
  let mut has_byte_offset = false
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
        if metadata is SourceByteOffset(71L) {
          has_byte_offset = true
        }
      }
    }
  }
  assert_eq(calls, 0)
  assert_true(has_source)
  assert_true(has_byte_offset)
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

///|
test "small GC read and constructor callees inline while retaining allocation effects" {
  for construct in [false, true] {
    let callee = @milkir.FunctionBuilder::FunctionBuilder("gc_leaf")
    callee.add_param(I64) |> ignore
    let argument = callee.add_param(if construct { I32 } else { Ref })
    callee.add_result(if construct { Ref } else { I32 })
    callee.return_([
      if construct {
        @wasm_milkir.struct_new(callee, 0, [argument])
      } else {
        @wasm_milkir.struct_get(callee, 0, 0, argument, I32)
      },
    ])
    let b = @milkir.FunctionBuilder::FunctionBuilder("gc_leaf_caller")
    let input = b.add_param(if construct { I32 } else { Ref })
    b.add_result(if construct { Ref } else { I32 })
    b.return_([
      @wasm_milkir.call_multi(b, 0, [if construct { Ref } else { I32 }], [input])[0],
    ])
    let context = @wasm_milkir.WasmValidationContext::new({
      function_contract: fn(_) {
        Some({
          params: [if construct { I32 } else { Ref }],
          results: [if construct { Ref } else { I32 }],
        })
      },
      defined_type_contract: fn(_) {
        Some(
          Struct([{ storage: Value(I32), mutable_: false, defaultable: true, }]),
        )
      },
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
      O2,
      scalar_callees=Map([(0, callee.get_function())]),
    )
    |> ignore
    assert_false(function.print().contains("ext.wasm.call"))
    assert_true(
      function
      .print()
      .contains(if construct { "struct_new" } else { "struct_get" }),
    )
    @wasm_milkir.verify_function_with_context(function, context)
  }
}

///|
test "invalid GC leaf contract is rejected before rewriting its caller" {
  let callee = @milkir.FunctionBuilder::FunctionBuilder("invalid_gc_leaf")
  callee.add_param(I64) |> ignore
  let reference = callee.add_param(Ref)
  callee.add_result(I32)
  callee.return_([@wasm_milkir.struct_get(callee, 0, 1, reference, I32)])
  let caller = @milkir.FunctionBuilder::FunctionBuilder("gc_contract_caller")
  let argument = caller.add_param(Ref)
  caller.add_result(I32)
  caller.return_([@wasm_milkir.call_multi(caller, 0, [I32], [argument])[0]])
  let context = @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { Some({ params: [Ref], results: [I32], }) },
    defined_type_contract: fn(_) {
      Some(
        Struct([{ storage: Value(I32), mutable_: false, defaultable: true, }]),
      )
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
  let function = caller.get_function()
  let before = function.print()
  let rejected = try {
    @optimize.optimize_with_level(
      function,
      context,
      O2,
      scalar_callees=Map([(0, callee.get_function())]),
    )
    |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(function.print(), before)
}

///|
test "leaf inlining retains entry polls even when its result is unused" {
  let callee = @milkir.FunctionBuilder("polled_leaf")
  callee.add_param(I64) |> ignore
  let input = callee.add_param(I32)
  callee.add_result(I64)
  let poll = @wasm_milkir.encode(SafepointPoll(-8, 0, 16, 24))
  callee.emit_void_ext_inst(poll, [])
  callee.return_([callee.sextend(I64, input)])
  let caller = @milkir.FunctionBuilder("polled_caller")
  caller.add_param(I64) |> ignore
  let value = caller.add_param(I32)
  caller.add_result(I64)
  caller.emit_void_ext_inst(poll, [])
  @wasm_milkir.call_multi(caller, 0, [I64], [value]) |> ignore
  caller.return_([@wasm_milkir.call_multi(caller, 0, [I64], [value])[0]])
  let context = @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { Some({ params: [I32], results: [I64], }) },
    defined_type_contract: fn(_) { None },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
  let function = caller.get_function()
  @optimize.optimize_with_level(
    function,
    context,
    O2,
    scalar_callees=Map([(0, callee.get_function())]),
  )
  |> ignore
  @wasm_milkir.verify_function_with_context(function, context)
  let mut polls = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let opcode = function.instruction_by_id(id).unwrap().opcode
      assert_false(@wasm_milkir.decode_opcode(opcode) is Some(WasmCall(_)))
      if @wasm_milkir.decode_opcode(opcode) is Some(SafepointPoll(_, _, _, _)) {
        polls += 1
      }
    }
  }
  assert_eq(polls, 3)
}
