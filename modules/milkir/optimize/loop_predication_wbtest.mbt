///|
fn counted_bounds_fixture(
  step~ : Int32 = 1,
  collecting~ : Bool = false,
  decreasing~ : Bool = false,
  compatibility~ : Bool = false,
) -> @milkir.Function raise @milkir.VerifyError {
  let b = @milkir.FunctionBuilder("two_induction_bounds")
  let start = b.add_param(I32)
  let output_start = b.add_param(I32)
  let limit = b.add_param(I32)
  let length = b.add_param(I32)
  let extra = if compatibility {
    Some((b.add_param(I32), b.add_param(I32)))
  } else {
    None
  }
  b.add_result(I32)
  let header = b.create_block()
  let index = b.add_block_param(header, I32)
  let output = b.add_block_param(header, I32)
  let sum = b.add_block_param(header, I32)
  let first = b.create_block()
  let second = b.create_block()
  let latch = b.create_block()
  let trap = b.create_block()
  let exit = b.create_block()
  let result = b.add_block_param(exit, I32)
  let zero = b.iconst_i32(0)
  b.jump(header, [start, output_start, zero])
  b.switch_to_block(header)
  b.branch(
    if decreasing {
      b.icmp_sge(index, zero)
    } else {
      b.icmp_slt(index, limit)
    },
    first,
    [],
    exit,
    [sum],
  )
  b.switch_to_block(first)
  let output_index = if decreasing {
    b.isub(output, b.iconst_i32(1))
  } else {
    output
  }
  b.branch(b.icmp_ult(output_index, length), second, [], trap, [])
  b.switch_to_block(second)
  if extra is Some((compatible, raw_length)) {
    let select = b.create_block()
    let present = b.create_block()
    let missing = b.create_block()
    let join = b.create_block()
    let selected_length = b.add_block_param(join, I32)
    b.branch(b.icmp_ult(index, length), select, [], trap, [])
    b.switch_to_block(select)
    b.branch(compatible, present, [], missing, [])
    b.switch_to_block(present)
    b.jump(join, [raw_length])
    b.switch_to_block(missing)
    b.jump(join, [b.iadd(raw_length, b.iconst_i32(1))])
    b.switch_to_block(join)
    b.branch(b.icmp_slt(output_index, selected_length), latch, [], trap, [])
  } else {
    b.branch(b.icmp_ult(index, length), latch, [], trap, [])
  }
  b.switch_to_block(latch)
  if collecting {
    let symbol = b.get_function().declare_external_symbol("may_collect")
    b.call_symbol(symbol, None, []) |> ignore
  }
  let next = if decreasing {
    b.isub(index, b.iconst_i32(step))
  } else {
    b.iadd(index, b.iconst_i32(step))
  }
  let next_output = if decreasing {
    output_index
  } else {
    b.iadd(output, b.iconst_i32(1))
  }
  b.jump(header, [next, next_output, b.iadd(sum, output)])
  b.switch_to_block(trap)
  b.trap("original bounds trap")
  b.switch_to_block(exit)
  b.return_([result])
  b.finalize()
}

///|
test "counted loop predication removes only proven fast-loop checks" {
  let function = counted_bounds_fixture()
  let original_checks = function.blocks.filter(block => {
    block.terminator is Some(Branch(condition, _, _, _, _)) &&
    function
    .defining_inst(condition)
    .map(inst => inst.opcode is Scalar(IntCompare(Ult)))
    .unwrap_or(false)
  })
  let old_next_block = function.next_block_id
  function.verify()
  assert_true(predicate_counted_loop_bounds(function).changed)
  function.verify()
  for block in original_checks {
    assert_true(block.terminator is Some(Branch(_, _, _, _, _)))
  }
  let fast = @milkir.CFG::build(function)
    .find_loops()
    .filter(loop_ => loop_.header >= old_next_block)
  assert_eq(fast.length(), 1)
  for block in function.blocks {
    if !fast[0].contains(block.id) {
      continue
    }
    if block.terminator is Some(Branch(condition, _, _, _, _)) {
      assert_false(
        function
        .defining_inst(condition)
        .map(inst => inst.opcode is Scalar(IntCompare(Ult)))
        .unwrap_or(false),
      )
    }
  }
}

///|
test "counted loop predication rejects unproved steps and collecting fast paths" {
  for
    function in [
      counted_bounds_fixture(step=2),
      counted_bounds_fixture(collecting=true),
    ] {
    function.verify()
    assert_false(predicate_counted_loop_bounds(function).changed)
    function.verify()
  }
}

///|
test "decreasing loop predication proves an offset secondary index" {
  let function = counted_bounds_fixture(decreasing=true)
  let first_new = function.next_block_id
  assert_true(predicate_counted_loop_bounds(function).changed)
  function.verify()
  let fast = @milkir.CFG::build(function)
    .find_loops()
    .filter(loop_ => loop_.header >= first_new)
  assert_eq(fast.length(), 1)
  for block in function.blocks {
    if fast[0].contains(block.id) &&
      block.terminator is Some(Branch(condition, _, _, _, _)) {
      assert_false(
        function
        .defining_inst(condition)
        .map(inst => inst.opcode is Scalar(IntCompare(Ult)))
        .unwrap_or(false),
      )
    }
  }
  let wrong_step = counted_bounds_fixture(step=2, decreasing=true)
  assert_false(predicate_counted_loop_bounds(wrong_step).changed)
}

///|
test "loop predication resolves guarded compatibility joins before signed bounds" {
  let function = counted_bounds_fixture(decreasing=true, compatibility=true)
  let first_new = function.next_block_id
  assert_true(predicate_counted_loop_bounds(function).changed)
  function.verify()
  let fast = @milkir.CFG::build(function)
    .find_loops()
    .filter(loop_ => loop_.header >= first_new)
  assert_eq(fast.length(), 1)
  for block in function.blocks {
    if fast[0].contains(block.id) &&
      block.terminator is Some(Branch(condition, _, _, _, _)) {
      assert_true(
        function
        .defining_inst(condition)
        .map(inst => inst.opcode is Scalar(IntCompare(Sge)))
        .unwrap_or(false),
      )
    }
  }
}
