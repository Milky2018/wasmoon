///|
fn projection(
  builder : @milkir.FunctionBuilder,
  object : @milkir.Value,
) -> @milkir.Value {
  builder.emit_ext_inst(
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
        pointer_region: Some(Heap(-1)),
        pointer_bytes: 0,
      }),
    ),
    [object],
  )
}

///|
test "projection CSE distinguishes metadata lifetime from payload aliases" {
  for barrier in 0..<3 {
    let builder = @milkir.FunctionBuilder("projection_versions")
    let object = builder.add_param(Ref)
    let unknown = builder.add_param(Ptr)
    let value = builder.add_param(I32)
    builder.add_result(Ptr)
    builder.add_result(Ptr)
    let zero = builder.iconst_i64(0L)
    let first = projection(builder, object)
    if barrier == 0 {
      builder.store_ptr(I32, first, value, zero)
    } else if barrier == 1 {
      builder.store_ptr(I32, unknown, value, zero)
    } else {
      let symbol = builder
        .get_function()
        .declare_external_symbol("moving_or_reentrant")
      builder.call_symbol(symbol, None, []) |> ignore
    }
    let second = projection(builder, object)
    builder.return_([first, second])
    let function = builder.finalize()
    optimize_with_level(function, O2) |> ignore
    let mut projections = 0
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        if function.instruction_by_id(id).unwrap().opcode is Ext(_, _) {
          projections += 1
        }
      }
    }
    assert_eq(projections, if barrier == 0 { 1 } else { 2 })
  }
}

///|
test "LICM records every result of a call defined inside a loop" {
  let builder = @milkir.FunctionBuilder("multi_result_loop")
  let condition = builder.add_param(I32)
  builder.add_result(I64)
  let header = builder.create_block()
  let exit = builder.create_block()
  let result = builder.add_block_param(exit, I64)
  builder.jump(header, [])
  builder.switch_to_block(header)
  let symbol = builder.get_function().declare_external_symbol("pair")
  let pair = builder.call_symbol_multi(symbol, [I64, I64], [])
  let sum = builder.iadd(pair[1], builder.iconst_i64(1L))
  builder.branch(condition, header, [], exit, [sum])
  builder.switch_to_block(exit)
  builder.return_([result])
  let function = builder.finalize()
  function.verify()
  optimize_with_level(function, O3) |> ignore
  function.verify()
}

///|
test "projection CSE respects a collecting loop backedge" {
  for budget in [0, 2, 100] {
    let builder = @milkir.FunctionBuilder("loop_projection_versions")
    builder.add_result(I32)
    let object = builder.add_param(Ref)
    let condition = builder.add_param(I32)
    let before = projection(builder, object)
    builder.load_ptr(I32, before, builder.iconst_i64(0L)) |> ignore
    let header = builder.create_block()
    let body = builder.create_block()
    let exit = builder.create_block()
    builder.jump(header, [])
    builder.switch_to_block(header)
    let current = projection(builder, object)
    let value = builder.load_ptr(I32, current, builder.iconst_i64(0L))
    builder.branch(condition, body, [], exit, [])
    builder.switch_to_block(body)
    let symbol = builder.get_function().declare_external_symbol("collecting")
    builder.call_symbol(symbol, None, []) |> ignore
    builder.jump(header, [])
    builder.switch_to_block(exit)
    builder.return_([value])
    let function = builder.finalize()
    run_acyclic_optimization_with_budget_and_analysis(
      function,
      budget,
      FunctionAnalysis::build(function),
    )
    |> ignore
    function.verify()
    let mut projections = 0
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        if function.instruction_by_id(id).unwrap().opcode is Ext(_, _) {
          projections += 1
        }
      }
    }
    assert_eq(projections, 2)
  }
}

///|
test "memory versions distinguish loop entry from a conditional repeated call" {
  let builder = @milkir.FunctionBuilder("conditional_loop_versions")
  let object = builder.add_param(Ref)
  let condition = builder.add_param(I32)
  let header = builder.create_block()
  let call = builder.create_block()
  let join = builder.create_block()
  let exit = builder.create_block()
  builder.jump(header, [])
  builder.switch_to_block(header)
  let before = projection(builder, object)
  builder.load_ptr(I32, before, builder.iconst_i64(0L)) |> ignore
  builder.branch(condition, call, [], join, [])
  builder.switch_to_block(call)
  let symbol = builder.get_function().declare_external_symbol("collecting")
  builder.call_symbol(symbol, None, []) |> ignore
  builder.jump(join, [])
  builder.switch_to_block(join)
  let after = projection(builder, object)
  builder.load_ptr(I32, after, builder.iconst_i64(0L)) |> ignore
  builder.branch(condition, header, [], exit, [])
  builder.switch_to_block(exit)
  builder.return_([])
  let function = builder.finalize()
  optimize_with_level(function, O2) |> ignore
  function.verify()
  let mut projections = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      if function.instruction_by_id(id).unwrap().opcode is Ext(_, _) {
        projections += 1
      }
    }
  }
  assert_eq(projections, 2)
}

///|
test "LICM moves only admitted in-range loads across disjoint effects" {
  for mode in ["admitted", "unchecked", "outside", "alias", "disjoint", "call"] {
    let b = @milkir.FunctionBuilder("bounded_load_\{mode}")
    let object = b.add_param(Ref)
    let condition = b.add_param(I32)
    let pointer = b.emit_ext_inst(
      Ptr,
      ExtOp(
        "memory-test",
        "checked",
        [],
        effects=Some({
          read: Some(Context),
          write: None,
          may_trap: true,
          observable: false,
          pointer_region: Some(Heap(-1)),
          pointer_bytes: if mode == "unchecked" {
            0
          } else {
            4
          },
        }),
      ),
      [object],
    )
    let header = b.create_block()
    let body = b.create_block()
    let exit = b.create_block()
    let offset = b.iconst_i64(if mode == "outside" { 4L } else { 0L })
    b.jump(header, [])
    b.switch_to_block(header)
    b.branch(condition, body, [], exit, [])
    b.switch_to_block(body)
    b.load_ptr(I32, pointer, offset) |> ignore
    if mode == "call" {
      let symbol = b.get_function().declare_external_symbol("collecting")
      b.call_symbol(symbol, None, []) |> ignore
    } else if mode == "alias" || mode == "disjoint" {
      b.emit_ext_inst(
        I32,
        ExtOp(
          "memory-test",
          "write",
          [],
          effects=Some({
            read: None,
            write: Some(Heap(if mode == "alias" { -1 } else { -2 })),
            may_trap: false,
            observable: true,
            pointer_region: None,
            pointer_bytes: 0,
          }),
        ),
        [],
      )
      |> ignore
    }
    b.jump(header, [])
    b.switch_to_block(exit)
    b.return_([])
    let function = b.finalize()
    hoist_loop_invariants(function) |> ignore
    function.verify()
    let mut loads = 0
    let cfg = @milkir.CFG::build(function)
    for loop_ in cfg.find_loops() {
      for block in function.blocks {
        if loop_.contains(block.id) {
          for id in function.block_instruction_ids(block) {
            if function.instruction_by_id(id).unwrap().opcode is Memory(Load(_)) {
              loads += 1
            }
          }
        }
      }
    }
    assert_eq(
      loads,
      if mode == "admitted" || mode == "disjoint" {
        0
      } else {
        1
      },
      msg=mode,
    )
  }
}

///|
test "guarded LICM preserves zero-trip entry tests and stops at earlier effects" {
  for effect in [false, true] {
    let b = @milkir.FunctionBuilder("guarded_read")
    let object = b.add_param(Ref)
    let count = b.add_param(I32)
    let header = b.create_block()
    let index = b.add_block_param(header, I32)
    let body = b.create_block()
    let exit = b.create_block()
    b.jump(header, [b.iconst_i32(0)])
    b.switch_to_block(header)
    b.branch(b.icmp_slt(index, count), body, [], exit, [])
    b.switch_to_block(body)
    if effect {
      let symbol = b
        .get_function()
        .declare_external_symbol("observable_before_read")
      b.call_symbol(symbol, None, []) |> ignore
    }
    let checked = b.emit_ext_inst(
      Ptr,
      ExtOp(
        "memory-test",
        "checked",
        [],
        effects=Some({
          read: Some(Context),
          write: None,
          may_trap: true,
          observable: false,
          pointer_region: Some(Heap(0)),
          pointer_bytes: 4,
        }),
      ),
      [object],
    )
    b.load_ptr(I32, checked, b.iconst_i64(0L)) |> ignore
    b.jump(header, [b.iadd(index, b.iconst_i32(1))])
    b.switch_to_block(exit)
    b.return_([])
    let function = b.finalize()
    hoist_loop_invariants(function, guard_entries=true) |> ignore
    function.verify()
    let cfg = @milkir.CFG::build(function)
    let mut checked_in_loop = 0
    for loop_ in cfg.find_loops() {
      for block in function.blocks {
        if loop_.contains(block.id) {
          for id in function.block_instruction_ids(block) {
            if function.instruction_by_id(id).unwrap().opcode is Ext(_, _) {
              checked_in_loop += 1
            }
          }
        }
      }
    }
    assert_eq(checked_in_loop, if effect { 1 } else { 0 })
    assert_eq(function.blocks.length(), if effect { 4 } else { 6 })
  }
}

///|
test "guarded LICM preserves header definitions used after a zero-trip loop" {
  for escaping_phi in [false, true] {
    let b = @milkir.FunctionBuilder("guard_header_uses")
    let object = b.add_param(Ref)
    let count = b.add_param(I32)
    b.add_result(I32)
    let header = b.create_block()
    let index = b.add_block_param(header, I32)
    let body = b.create_block()
    let exit = b.create_block()
    b.jump(header, [b.iconst_i32(0)])
    b.switch_to_block(header)
    let one = b.iconst_i32(1)
    b.branch(b.icmp_slt(index, count), body, [], exit, [])
    b.switch_to_block(body)
    b.emit_ext_inst(
      Ptr,
      ExtOp(
        "memory-test",
        "checked",
        [],
        effects=Some({
          read: Some(Context),
          write: None,
          may_trap: true,
          observable: false,
          pointer_region: Some(Heap(0)),
          pointer_bytes: 4,
        }),
      ),
      [object],
    )
    |> ignore
    b.jump(header, [b.iadd(index, one)])
    b.switch_to_block(exit)
    b.return_([if escaping_phi { index } else { one }])
    let function = b.finalize()
    function.verify()
    hoist_loop_invariants(function, guard_entries=true) |> ignore
    function.verify()
    assert_eq(function.blocks.length(), if escaping_phi { 4 } else { 6 })
  }
}

///|
test "invocation control writes preserve payload metadata versions but opaque writes revoke them" {
  for unknown_store in [false, true] {
    let b = @milkir.FunctionBuilder("control_metadata_versions")
    let object = b.add_param(Ref)
    b.add_result(Ptr)
    b.add_result(Ptr)
    let first = projection(b, object)
    b.emit_void_ext_inst(
      ExtOp(
        "memory-test",
        "control_write",
        [],
        effects=Some({
          read: None,
          write: Some(if unknown_store { Other } else { Control }),
          may_trap: false,
          observable: true,
          pointer_region: None,
          pointer_bytes: 0,
        }),
      ),
      [],
    )
    let second = projection(b, object)
    b.return_([first, second])
    let function = b.finalize()
    optimize_with_level(function, O2) |> ignore
    let mut count = 0
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        if function.instruction_by_id(id).unwrap().opcode is Ext(op, _) &&
          op.opcode == "project" {
          count += 1
        }
      }
    }
    assert_eq(count, if unknown_store { 2 } else { 1 })
  }
}

///|
test "control reads are invalidated by control and opaque writes" {
  for unknown_store in [false, true] {
    let b = @milkir.FunctionBuilder("control_read_versions")
    b.add_result(I32)
    b.add_result(I32)
    let read : @milkir.ExtOp = ExtOp(
      "memory-test",
      "control_read",
      [],
      effects=Some({
        read: Some(Control),
        write: None,
        may_trap: false,
        observable: false,
        pointer_region: None,
        pointer_bytes: 0,
      }),
    )
    let first = b.emit_ext_inst(I32, read, [])
    b.emit_void_ext_inst(
      ExtOp(
        "memory-test",
        "write",
        [],
        effects=Some({
          read: None,
          write: Some(if unknown_store { Other } else { Control }),
          may_trap: false,
          observable: true,
          pointer_region: None,
          pointer_bytes: 0,
        }),
      ),
      [],
    )
    let second = b.emit_ext_inst(I32, read, [])
    b.return_([first, second])
    let function = b.finalize()
    optimize_with_level(function, O2) |> ignore
    let mut count = 0
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        if function.instruction_by_id(id).unwrap().opcode is Ext(op, _) &&
          op.opcode == "control_read" {
          count += 1
        }
      }
    }
    assert_eq(count, 2)
  }
}
