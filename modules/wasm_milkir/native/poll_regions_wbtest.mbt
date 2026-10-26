///|
fn test_poll_region(limit : Int32) -> PollRegion {
  { execution: -224, controls: 64, callback: 0, budget: 16, limit, key: 717, }
}

///|
test "native poll credits reject missing guards false edges overcharge and opaque calls" {
  for
    mode in [
      "missing", "false_edge", "overcharge", "opaque", "unknown", "side_entry", "mismatch",
    ] {
    let b = @milkir.FunctionBuilder("poll_credit_\{mode}")
    b.add_param(I64) |> ignore
    let region = test_poll_region(1)
    if mode != "missing" {
      let guard_ = b.emit_ext_inst(I32, poll_region_opcode(region, true), [])
      let yes = b.create_block()
      let no = b.create_block()
      b.branch(guard_, yes, [], no, [])
      b.switch_to_block(if mode == "false_edge" { yes } else { no })
      if mode == "side_entry" {
        b.jump(yes, [])
      } else {
        b.return_([])
      }
      b.switch_to_block(if mode == "false_edge" { no } else { yes })
    }
    if mode == "opaque" {
      b.emit_void_ext_inst(
        @wasm_milkir.encode(SafepointPoll(-224, 64, 0, 16)),
        [],
      )
    }
    if mode == "unknown" {
      let symbol = b
        .get_function()
        .declare_external_symbol("unknown_control_mutation")
      b.call_symbol(symbol, None, []) |> ignore
    }
    b.emit_void_ext_inst(
      poll_region_opcode(
        if mode == "mismatch" {
          { ..region, budget: 24, }
        } else {
          region
        },
        false,
      ),
      [],
    )
    if mode == "overcharge" {
      b.emit_void_ext_inst(poll_region_opcode(region, false), [])
    }
    b.return_([])
    let function = b.finalize()
    assert_true(poll_region_error(function) is Some(_), msg=mode)
    assert_true(gc_borrow_error(function) is Some(_), msg=mode)
  }
}

///|
test "native poll credit permits only its bounded true branch" {
  let b = @milkir.FunctionBuilder("poll_credit_valid")
  b.add_param(I64) |> ignore
  let region = test_poll_region(2)
  let guard_ = b.emit_ext_inst(I32, poll_region_opcode(region, true), [])
  let yes = b.create_block()
  let no = b.create_block()
  b.branch(guard_, yes, [], no, [])
  b.switch_to_block(no)
  b.return_([])
  b.switch_to_block(yes)
  b.emit_void_ext_inst(poll_region_opcode(region, false), [])
  b.emit_void_ext_inst(poll_region_opcode(region, false), [])
  b.return_([])
  assert_eq(poll_region_error(b.finalize()), None)
}

///|
fn polled_digit_fixture(
  no_state~ : Bool = false,
) -> @milkir.Function raise @milkir.VerifyError {
  let b = @milkir.FunctionBuilder("polled_digit_loop")
  b.add_param(I64) |> ignore
  let object = b.add_param(Ref)
  let count = b.add_param(I32)
  let header = b.create_block()
  let index = if no_state {
    b.iconst_i32(0)
  } else {
    b.add_block_param(header, I32)
  }
  let body = b.create_block()
  let exit = b.create_block()
  b.jump(header, if no_state { [] } else { [b.iconst_i32(0)] })
  b.switch_to_block(header)
  b.emit_void_ext_inst(@wasm_milkir.encode(SafepointPoll(-224, 64, 0, 16)), [])
  b.branch(b.icmp_ult(index, count), body, [], exit, [])
  b.switch_to_block(body)
  let array = @wasm_milkir.struct_get(b, 1, 0, object, Ref)
  let value = @wasm_milkir.array_get_u(b, 0, array, index, 1)
  b.emit_void_ext_inst(@wasm_milkir.encode(SafepointPoll(-224, 64, 0, 16)), [])
  let refreshed = @wasm_milkir.struct_get(b, 1, 0, object, Ref)
  @wasm_milkir.array_set(b, 0, refreshed, index, value)
  b.jump(header, if no_state { [] } else { [b.iadd(index, b.iconst_i32(1))] })
  b.switch_to_block(exit)
  b.return_([])
  b.finalize()
}

///|
test "poll loop versioning retains both header and inlined body charges" {
  let function = polled_digit_fixture()
  prepare_gc_memory(
    function,
    digit_memory_context(),
    exclusive_poll_controls=true,
  )
  assert_eq(poll_region_error(function), None)
  let mut guards = 0
  let mut charges = 0
  let mut original = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if inst.opcode is Ext(op, _) &&
        decode_poll_region(op) is Some((region, guard_)) {
        assert_eq(region.limit, 2)
        if guard_ {
          guards += 1
        } else {
          charges += 1
        }
      }
      if @wasm_milkir.decode_opcode(inst.opcode)
        is Some(SafepointPoll(_, _, _, _)) {
        original += 1
      }
    }
  }
  assert_eq(guards, 1)
  assert_eq(charges, 2)
  assert_eq(original, 2)
}

///|
test "budget proof recognizes both zero and nonzero conditional edges" {
  for reversed in [false, true] {
    let b = @milkir.FunctionBuilder("native_poll_conditional")
    b.add_param(I64) |> ignore
    let region = test_poll_region(1)
    let guard_ = b.emit_ext_inst(I32, poll_region_opcode(region, true), [])
    let entry = b.get_function().blocks[0]
    let yes = b.create_block()
    let no = b.create_block()
    entry.set_terminator(
      if reversed {
        Brz(guard_, no.id, yes.id)
      } else {
        Brnz(guard_, yes.id, no.id)
      },
    )
    b.switch_to_block(no)
    b.return_([])
    b.switch_to_block(yes)
    b.emit_void_ext_inst(poll_region_opcode(region, false), [])
    b.return_([])
    assert_eq(poll_region_error(b.finalize()), None)
  }
}

///|
test "poll regions require explicit ownership permission and prepare idempotently" {
  for enabled in [false, true] {
    let function = polled_digit_fixture(no_state=true)
    prepare_gc_memory(
      function,
      digit_memory_context(),
      exclusive_poll_controls=enabled,
    )
    assert_eq(function.print().contains("native_poll_budget_guard"), enabled)
    let before = function.print()
    prepare_gc_memory(
      function,
      digit_memory_context(),
      exclusive_poll_controls=enabled,
    )
    assert_eq(function.print(), before)
  }
}

///|
test "poll loop clones empty scalar exit forwarding blocks" {
  let b = @milkir.FunctionBuilder("polled_forwarded_exit")
  b.add_param(I64) |> ignore
  let holder = b.add_param(Ref)
  let count = b.add_param(I32)
  b.add_result(I32)
  let header = b.create_block()
  let index = b.add_block_param(header, I32)
  let body = b.create_block()
  let bridge = b.create_block()
  let exit = b.create_block()
  let result = b.add_block_param(exit, I32)
  b.jump(header, [b.iconst_i32(0)])
  b.switch_to_block(header)
  b.emit_void_ext_inst(@wasm_milkir.encode(SafepointPoll(-224, 64, 0, 16)), [])
  b.branch(b.icmp_ult(index, count), body, [], bridge, [])
  b.switch_to_block(body)
  let array = @wasm_milkir.struct_get(b, 1, 0, holder, Ref)
  let value = @wasm_milkir.array_get_u(b, 0, array, index, 1)
  b.emit_void_ext_inst(@wasm_milkir.encode(SafepointPoll(-224, 64, 0, 16)), [])
  let refreshed = @wasm_milkir.struct_get(b, 1, 0, holder, Ref)
  @wasm_milkir.array_set(b, 0, refreshed, index, value)
  b.jump(header, [b.iadd(index, b.iconst_i32(1))])
  b.switch_to_block(bridge)
  b.jump(exit, [index])
  b.switch_to_block(exit)
  b.return_([result])
  let function = b.finalize()
  let header_metadata : Array[@milkir.Metadata] = [SourceByteOffset(123L)]
  let bridge_metadata : Array[@milkir.Metadata] = [SourceLoc("forwarded exit")]
  header.set_terminator(header.terminator.unwrap(), metadata=header_metadata)
  bridge.set_terminator(bridge.terminator.unwrap(), metadata=bridge_metadata)
  version_poll_loops(function, digit_memory_context())
  assert_true(function.print().contains("native_poll_budget_guard"))
  assert_eq(
    function.blocks
    .filter(block => block.terminator_metadata() == header_metadata)
    .length(),
    2,
  )
  assert_eq(
    function.blocks
    .filter(block => block.terminator_metadata() == bridge_metadata)
    .length(),
    2,
  )
  prepare_gc_memory(
    function,
    digit_memory_context(),
    exclusive_poll_controls=true,
  )
  assert_eq(gc_borrow_error(function), None)
}

///|
test "a cycle cannot recharge credit without passing its budget guard" {
  let b = @milkir.FunctionBuilder("poll_credit_cycle")
  b.add_param(I64) |> ignore
  let region = test_poll_region(1)
  let guard_ = b.emit_ext_inst(I32, poll_region_opcode(region, true), [])
  let loop_ = b.create_block()
  let exit = b.create_block()
  b.branch(guard_, loop_, [], exit, [])
  b.switch_to_block(loop_)
  b.emit_void_ext_inst(poll_region_opcode(region, false), [])
  b.jump(loop_, [])
  b.switch_to_block(exit)
  b.return_([])
  assert_true(poll_region_error(b.finalize()) is Some(_))
}

///|
test "a poll between the guard and its branch invalidates the guard result" {
  let b = @milkir.FunctionBuilder("poll_stale_guard")
  b.add_param(I64) |> ignore
  let region = test_poll_region(1)
  let guard_ = b.emit_ext_inst(I32, poll_region_opcode(region, true), [])
  b.emit_void_ext_inst(@wasm_milkir.encode(SafepointPoll(-224, 64, 0, 16)), [])
  let yes = b.create_block()
  let no = b.create_block()
  b.branch(guard_, yes, [], no, [])
  b.switch_to_block(yes)
  b.emit_void_ext_inst(poll_region_opcode(region, false), [])
  b.return_([])
  b.switch_to_block(no)
  b.return_([])
  assert_true(poll_region_error(b.finalize()) is Some(_))
}

///|
test "branching again on an old guard result cannot restore spent credit" {
  let b = @milkir.FunctionBuilder("poll_reused_guard")
  b.add_param(I64) |> ignore
  let region = test_poll_region(1)
  let guard_ = b.emit_ext_inst(I32, poll_region_opcode(region, true), [])
  let first = b.create_block()
  let second = b.create_block()
  let exit = b.create_block()
  b.branch(guard_, first, [], exit, [])
  b.switch_to_block(first)
  b.emit_void_ext_inst(poll_region_opcode(region, false), [])
  b.branch(guard_, second, [], exit, [])
  b.switch_to_block(second)
  b.emit_void_ext_inst(poll_region_opcode(region, false), [])
  b.return_([])
  b.switch_to_block(exit)
  b.return_([])
  assert_true(poll_region_error(b.finalize()) is Some(_))
}
