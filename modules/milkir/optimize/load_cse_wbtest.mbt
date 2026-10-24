///|
fn remaining_loads(function : @milkir.Function) -> Int32 {
  let mut count = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      if function.instruction_by_id(id).unwrap().opcode is Memory(Load(_)) {
        count += 1
      }
    }
  }
  count
}

///|
test "load CSE retains the first trapping read and respects aliases and calls" {
  for boundary in 0..<3 {
    let builder = @milkir.FunctionBuilder("loads")
    let pointer = builder.add_param(Ptr)
    let other_pointer = builder.add_param(Ptr)
    let value = builder.add_param(I32)
    builder.add_result(I32)
    builder.add_result(I32)
    let zero = builder.iconst_i64(0L)
    let first = builder.load_ptr(I32, pointer, zero)
    if boundary == 1 {
      builder.store_ptr(I32, other_pointer, value, zero)
    } else if boundary == 2 {
      let symbol = builder.get_function().declare_external_symbol("unknown")
      builder.call_symbol(symbol, None, [pointer]) |> ignore
    }
    let second = builder.load_ptr(I32, pointer, zero)
    builder.return_([first, second])
    let function = builder.finalize()
    optimize_with_level(function, O2) |> ignore
    function.verify()
    assert_eq(remaining_loads(function), if boundary == 0 { 1 } else { 2 })
  }
}

///|
test "load CSE cannot reuse a conditional read outside its dominance path" {
  let builder = @milkir.FunctionBuilder("conditional_read")
  let pointer = builder.add_param(Ptr)
  let condition = builder.add_param(I32)
  builder.add_result(I32)
  let zero = builder.iconst_i64(0L)
  let taken = builder.create_block()
  let join = builder.create_block()
  builder.branch(condition, taken, [], join, [])
  builder.switch_to_block(taken)
  builder.load_ptr(I32, pointer, zero) |> ignore
  builder.jump(join, [])
  builder.switch_to_block(join)
  let value = builder.load_ptr(I32, pointer, zero)
  builder.return_([value])
  let function = builder.finalize()
  optimize_with_level(function, O2) |> ignore
  function.verify()
  assert_eq(remaining_loads(function), 2)
}

///|
test "unknown readers may alias writes in any concrete region" {
  let b = @milkir.FunctionBuilder("unknown_read_concrete_write")
  let pointer = b.add_param(Ptr)
  let object = b.add_param(Ref)
  b.add_result(I32)
  b.add_result(I32)
  let known = b.emit_ext_inst(
    Ptr,
    ExtOp(
      "memory-test",
      "project",
      [],
      effects=Some({
        read: Some(Context),
        write: None,
        may_trap: false,
        observable: false,
        pointer_region: Some(Heap(0)),
        pointer_bytes: 0,
      }),
    ),
    [object],
  )
  let zero = b.iconst_i64(0L)
  let before = b.load_ptr(I32, pointer, zero)
  b.store_ptr(I32, known, b.iconst_i32(42), zero)
  let after = b.load_ptr(I32, pointer, zero)
  b.return_([before, after])
  let function = b.finalize()
  optimize_with_level(function, O2) |> ignore
  function.verify()
  assert_eq(remaining_loads(function), 2)
}
