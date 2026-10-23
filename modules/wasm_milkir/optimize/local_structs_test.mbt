///|
fn local_struct_context() -> @wasm_milkir.WasmValidationContext {
  @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(index) {
      if index == 0 {
        Some(
          Struct([{ storage: Value(I32), mutable_: true, defaultable: true, }]),
        )
      } else if index == 1 {
        Some(
          Struct([{ storage: Value(I64), mutable_: true, defaultable: true, }]),
        )
      } else {
        None
      }
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
}

///|
fn remaining_struct_accesses(function : @milkir.Function) -> Int32 {
  let mut count = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      match
        @wasm_milkir.decode_opcode(
          function.instruction_by_id(id).unwrap().opcode,
        ) {
        Some(StructGet(_, _) | StructSet(_, _)) => count += 1
        _ => ()
      }
    }
  }
  count
}

///|
test "private fields merge with existing block arguments and integer widths" {
  let b = @milkir.FunctionBuilder::FunctionBuilder("private_branch")
  let condition = b.add_param(I32)
  b.add_result(I64)
  let object = @wasm_milkir.struct_new(b, 1, [b.iconst_i64(7L)])
  let left = b.create_block()
  let right = b.create_block()
  let join = b.create_block()
  let extra = b.add_block_param(join, I64)
  b.branch(condition, left, [], right, [])
  b.switch_to_block(left)
  @wasm_milkir.struct_set(b, 1, 0, object, b.iconst_i64(42L))
  b.jump(join, [b.iconst_i64(1L)])
  b.switch_to_block(right)
  b.jump(join, [b.iconst_i64(2L)])
  b.switch_to_block(join)
  b.return_([b.iadd(extra, @wasm_milkir.struct_get(b, 1, 0, object, I64))])
  let function = b.get_function()
  @optimize.optimize_with_level(function, local_struct_context(), O2) |> ignore
  assert_eq(remaining_struct_accesses(function), 0)
  @wasm_milkir.verify_function_with_context(function, local_struct_context())
}

///|
test "escaping fields remain observable through calls and returns" {
  for escape in ["call", "return"] {
    let b = @milkir.FunctionBuilder::FunctionBuilder("escaped_\{escape}")
    let object = @wasm_milkir.struct_new(b, 0, [b.iconst_i32(7)])
    @wasm_milkir.struct_set(b, 0, 0, object, b.iconst_i32(42))
    @wasm_milkir.struct_get(b, 0, 0, object, I32) |> ignore
    if escape == "call" {
      let symbol = b.get_function().declare_external_symbol("observe_box")
      b.call_symbol(symbol, None, [object]) |> ignore
      b.return_([])
    } else {
      b.add_result(Ref)
      b.return_([object])
    }
    let function = b.get_function()
    @optimize.optimize_with_level(function, local_struct_context(), O2)
    |> ignore
    assert_true(remaining_struct_accesses(function) > 0)
  }
}

///|
test "private scalar promotion respects O0 and O1" {
  for level in [@generic.OptLevel::O0, O1] {
    let b = @milkir.FunctionBuilder::FunctionBuilder("private_unoptimized")
    let object = @wasm_milkir.struct_new(b, 0, [b.iconst_i32(7)])
    b.add_result(I32)
    b.return_([@wasm_milkir.struct_get(b, 0, 0, object, I32)])
    let function = b.get_function()
    @optimize.optimize_with_level(function, local_struct_context(), level)
    |> ignore
    assert_eq(remaining_struct_accesses(function), 1)
  }
}

///|
test "loop allocations keep their separate dynamic field state" {
  let b = @milkir.FunctionBuilder::FunctionBuilder("loop_box")
  let condition = b.add_param(I32)
  let loop_ = b.create_block()
  let exit = b.create_block()
  b.jump(loop_, [])
  b.switch_to_block(loop_)
  let object = @wasm_milkir.struct_new(b, 0, [b.iconst_i32(7)])
  let value = @wasm_milkir.struct_get(b, 0, 0, object, I32)
  b.branch(condition, loop_, [], exit, [])
  b.switch_to_block(exit)
  b.add_result(I32)
  b.return_([value])
  let function = b.get_function()
  @optimize.optimize_with_level(function, local_struct_context(), O2) |> ignore
  assert_eq(remaining_struct_accesses(function), 0)
  assert_true(function.print().contains("struct_new"))
  @wasm_milkir.verify_function_with_context(function, local_struct_context())
}

///|
test "private integer struct fields become loop-carried SSA without removing allocation" {
  let b = @milkir.FunctionBuilder::FunctionBuilder("private_counter")
  let limit = b.add_param(I32)
  b.add_result(I32)
  let object = @wasm_milkir.struct_new(b, 0, [b.iconst_i32(0)])
  let loop_ = b.create_block()
  let exit = b.create_block()
  b.jump(loop_, [])
  b.switch_to_block(loop_)
  let old = @wasm_milkir.struct_get(b, 0, 0, object, I32)
  let next = b.iadd(old, b.iconst_i32(1))
  @wasm_milkir.struct_set(b, 0, 0, object, next)
  b.branch(b.icmp_slt(next, limit), loop_, [], exit, [])
  b.switch_to_block(exit)
  b.return_([@wasm_milkir.struct_get(b, 0, 0, object, I32)])
  let function = b.get_function()
  @optimize.optimize_with_level(function, local_struct_context(), O2) |> ignore
  let mut accesses = 0
  let mut allocations = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      match
        @wasm_milkir.decode_opcode(
          function.instruction_by_id(id).unwrap().opcode,
        ) {
        Some(StructGet(_, _) | StructSet(_, _)) => accesses += 1
        Some(StructNew(_)) => allocations += 1
        _ => ()
      }
    }
  }
  assert_eq(accesses, 0)
  assert_eq(allocations, 1)
  @wasm_milkir.verify_function_with_context(function, local_struct_context())
}

///|
test "conditional loop boxes promote with initialization at each allocation" {
  let b = @milkir.FunctionBuilder("conditional_private_box")
  let limit = b.add_param(I32)
  b.add_result(I32)
  let header = b.create_block()
  let i = b.add_block_param(header, I32)
  let sum = b.add_block_param(header, I32)
  let choose = b.create_block()
  let allocate = b.create_block()
  let skip = b.create_block()
  let join = b.create_block()
  let value = b.add_block_param(join, I32)
  let exit = b.create_block()
  let result = b.add_block_param(exit, I32)
  b.jump(header, [b.iconst_i32(0), b.iconst_i32(0)])
  b.switch_to_block(header)
  b.branch(b.icmp_slt(i, limit), choose, [], exit, [sum])
  b.switch_to_block(choose)
  b.branch(
    b.icmp_eq(b.band(i, b.iconst_i32(1)), b.iconst_i32(0)),
    allocate,
    [],
    skip,
    [],
  )
  b.switch_to_block(allocate)
  let box = @wasm_milkir.struct_new(b, 0, [i])
  @wasm_milkir.struct_set(
    b,
    0,
    0,
    box,
    b.iadd(@wasm_milkir.struct_get(b, 0, 0, box, I32), b.iconst_i32(3)),
  )
  b.jump(join, [@wasm_milkir.struct_get(b, 0, 0, box, I32)])
  b.switch_to_block(skip)
  b.jump(join, [i])
  b.switch_to_block(join)
  b.jump(header, [b.iadd(i, b.iconst_i32(1)), b.iadd(sum, value)])
  b.switch_to_block(exit)
  b.return_([result])
  let function = b.get_function()
  @optimize.optimize_with_level(function, local_struct_context(), O2) |> ignore
  assert_eq(remaining_struct_accesses(function), 0)
  assert_true(function.print().contains("struct_new"))
  @wasm_milkir.verify_function_with_context(function, local_struct_context())
}
