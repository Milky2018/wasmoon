///|
fn epoch_barrier(b : @milkir.FunctionBuilder) -> Unit {
  b.emit_void_ext_inst(
    ExtOp(
      "memory-test",
      "move",
      [],
      effects=Some({
        read: None,
        write: None,
        may_trap: false,
        observable: true,
        invalidates_addresses: true,
        pointer_region: None,
        pointer_bytes: 0,
      }),
    ),
    [],
  )
}

///|
test "address-invalidating read results never erase their epoch transition" {
  let b = @milkir.FunctionBuilder("observable_address_transition")
  b.add_result(I32)
  b.add_result(I32)
  let read : @milkir.ExtOp = ExtOp(
    "memory-test",
    "moving_read",
    [],
    effects=Some({
      read: Some(Context),
      write: None,
      may_trap: false,
      observable: false,
      invalidates_addresses: true,
      pointer_region: None,
      pointer_bytes: 0,
    }),
  )
  let first = b.emit_ext_inst(I32, read, [])
  let second = b.emit_ext_inst(I32, read, [])
  b.return_([first, second])
  let function = b.finalize()
  optimize_with_level(function, O3) |> ignore
  let mut transitions = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      if function.instruction_by_id(id).unwrap().opcode is Ext(extension, _) &&
        extension.opcode == "moving_read" {
        transitions += 1
      }
    }
  }
  assert_eq(transitions, 2)
}

///|
test "address epochs expire projections without writing logical fields" {
  for budget in [0, 1, 100] {
    let b = @milkir.FunctionBuilder("independent_memory_epochs")
    let object = b.add_param(Ref)
    b.add_result(Ptr)
    b.add_result(Ptr)
    b.add_result(I32)
    b.add_result(I32)
    let read : @milkir.ExtOp = ExtOp(
      "memory-test",
      "logical",
      [],
      effects=Some({
        read: Some(Heap(-1)),
        write: None,
        may_trap: true,
        observable: false,
        invalidates_addresses: false,
        pointer_region: None,
        pointer_bytes: 0,
      }),
    )
    let first_pointer = projection(b, object)
    let first = b.emit_ext_inst(I32, read, [object])
    epoch_barrier(b)
    let second_pointer = projection(b, object)
    let second = b.emit_ext_inst(I32, read, [object])
    b.return_([first_pointer, second_pointer, first, second])
    let function = b.finalize()
    run_acyclic_optimization_with_budget_and_analysis(
      function,
      budget,
      FunctionAnalysis::build(function),
    )
    |> ignore
    function.verify()
    let mut projections = 0
    let mut reads = 0
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        if function.instruction_by_id(id).unwrap().opcode is Ext(extension, _) {
          if extension.opcode == "project" {
            projections += 1
          }
          if extension.opcode == "logical" {
            reads += 1
          }
        }
      }
    }
    assert_eq(projections, 2)
    assert_eq(reads, 1)
  }
}

///|
test "raw load CSE and forwarding respect address epochs" {
  for store in [false, true] {
    let b = @milkir.FunctionBuilder("physical_memory_epochs")
    let address = b.add_param(Ptr)
    let value = b.add_param(I32)
    b.add_result(I32)
    b.add_result(I32)
    let zero = b.iconst_i64(0L)
    let first = if store {
      b.store_ptr(I32, address, value, zero)
      value
    } else {
      b.load_ptr(I32, address, zero)
    }
    epoch_barrier(b)
    let second = b.load_ptr(I32, address, zero)
    b.return_([first, second])
    let function = b.finalize()
    optimize_with_level(function, O2) |> ignore
    let mut loads = 0
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        if function.instruction_by_id(id).unwrap().opcode is Memory(Load(_)) {
          loads += 1
        }
      }
    }
    assert_eq(loads, if store { 1 } else { 2 })
  }
}

///|
test "conditional address invalidation reaches loop headers after budgets expire" {
  for budget in [0, 2, 100] {
    let b = @milkir.FunctionBuilder("conditional_address_epoch")
    let object = b.add_param(Ref)
    let condition = b.add_param(I32)
    b.add_result(I32)
    let before = projection(b, object)
    b.load_ptr(I32, before, b.iconst_i64(0L)) |> ignore
    let header = b.create_block()
    let moving = b.create_block()
    let join = b.create_block()
    let exit = b.create_block()
    b.jump(header, [])
    b.switch_to_block(header)
    let current = projection(b, object)
    let value = b.load_ptr(I32, current, b.iconst_i64(0L))
    b.branch(condition, moving, [], join, [])
    b.switch_to_block(moving)
    epoch_barrier(b)
    b.jump(join, [])
    b.switch_to_block(join)
    b.branch(condition, header, [], exit, [])
    b.switch_to_block(exit)
    b.return_([value])
    let function = b.finalize()
    run_acyclic_optimization_with_budget_and_analysis(
      function,
      budget,
      FunctionAnalysis::build(function),
    )
    |> ignore
    let mut projections = 0
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        if function.instruction_by_id(id).unwrap().opcode is Ext(extension, _) &&
          extension.opcode == "project" {
          projections += 1
        }
      }
    }
    assert_eq(projections, 2)
  }
}

///|
test "LICM never moves physical projections across address invalidation" {
  let b = @milkir.FunctionBuilder("loop_address_epoch")
  let object = b.add_param(Ref)
  let condition = b.add_param(I32)
  b.add_result(I32)
  let header = b.create_block()
  let exit = b.create_block()
  b.jump(header, [])
  b.switch_to_block(header)
  epoch_barrier(b)
  let pointer = projection(b, object)
  let value = b.load_ptr(I32, pointer, b.iconst_i64(0L))
  b.branch(condition, header, [], exit, [])
  b.switch_to_block(exit)
  b.return_([value])
  let function = b.finalize()
  optimize_with_level(function, O3) |> ignore
  let cfg = @milkir.CFG::build(function)
  let loops = cfg.find_loops()
  assert_false(loops.is_empty())
  for loop_ in loops {
    assert_true(
      function.blocks.any(block => {
        loop_.contains(block.id) &&
        function
        .block_instruction_ids(block)
        .any(id => {
          function.instruction_by_id(id).unwrap().opcode is Ext(extension, _) &&
          extension.opcode == "project"
        })
      }),
    )
  }
}
