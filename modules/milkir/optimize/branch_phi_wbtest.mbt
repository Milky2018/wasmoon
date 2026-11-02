///|
test "jump threading resolves constant branch parameters and remaps selected arguments" {
  for bits in [0, 1, -1] {
    let b = @milkir.FunctionBuilder("constant_dispatch")
    b.add_result(I32)
    let dispatch = b.create_block()
    let selected = b.add_block_param(dispatch, I32)
    let payload = b.add_block_param(dispatch, I32)
    let yes = b.create_block()
    let no = b.create_block()
    let yes_value = b.add_block_param(yes, I32)
    let no_value = b.add_block_param(no, I32)
    let value = b.iconst_i32(77)
    b.jump(dispatch, [b.iconst_i32(bits), value])
    b.switch_to_block(dispatch)
    b.branch(selected, yes, [payload], no, [payload])
    b.switch_to_block(yes)
    b.return_([yes_value])
    b.switch_to_block(no)
    b.return_([no_value])
    let function = b.finalize()
    assert_true(thread_jumps(function).changed)
    guard function.blocks[0].terminator is Some(Jump(target, [actual])) else {
      fail("constant dispatch was not threaded")
    }
    assert_eq(target, if bits == 0 { no.id } else { yes.id })
    assert_eq(actual, value)
    function.verify()
  }
}

///|
test "conditional threading retains parameters read by descendants" {
  let b = @milkir.FunctionBuilder("dispatch_live_parameter")
  b.add_result(I32)
  let dispatch = b.create_block()
  let selected = b.add_block_param(dispatch, I32)
  let payload = b.add_block_param(dispatch, I32)
  let yes = b.create_block()
  let no = b.create_block()
  b.jump(dispatch, [b.iconst_i32(1), b.iconst_i32(77)])
  b.switch_to_block(dispatch)
  b.branch(selected, yes, [], no, [])
  b.switch_to_block(yes)
  b.return_([payload])
  b.switch_to_block(no)
  b.return_([b.iconst_i32(0)])
  let function = b.finalize()
  assert_false(thread_jumps(function).changed)
  function.verify()
}

///|
test "conditional threading does not bypass instructions before dispatch" {
  let b = @milkir.FunctionBuilder("dispatch_effects")
  b.add_result(I32)
  let dispatch = b.create_block()
  let selected = b.add_block_param(dispatch, I32)
  let yes = b.create_block()
  let no = b.create_block()
  b.jump(dispatch, [b.iconst_i32(1)])
  b.switch_to_block(dispatch)
  let symbol = b.get_function().declare_external_symbol("observable")
  b.call_symbol(symbol, None, []) |> ignore
  b.branch(selected, yes, [], no, [])
  b.switch_to_block(yes)
  b.return_([b.iconst_i32(77)])
  b.switch_to_block(no)
  b.return_([b.iconst_i32(0)])
  let function = b.finalize()
  assert_false(thread_jumps(function).changed)
  function.verify()
}
