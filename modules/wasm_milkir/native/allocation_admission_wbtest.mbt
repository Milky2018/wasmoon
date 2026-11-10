///|
test "allocation admission is shared by collecting loop sites and restores input" {
  for barrier in [false, true] {
    let b = @milkir.FunctionBuilder("loop_allocation_admission")
    let count = b.add_param(I32)
    let header = b.create_block()
    let body = b.create_block()
    let exit = b.create_block()
    let index = b.add_block_param(header, I32)
    b.jump(header, [b.iconst_i32(0)])
    b.switch_to_block(header)
    b.branch(b.icmp_slt(index, count), body, [], exit, [])
    b.switch_to_block(body)
    @wasm_milkir.struct_new_default(b, 0) |> ignore
    if barrier {
      b.emit_void_ext_inst(@wasm_milkir.encode(WasmCall(0)), [])
    }
    @wasm_milkir.struct_new_default(b, 0) |> ignore
    b.jump(header, [b.iadd(index, b.iconst_i32(1))])
    b.switch_to_block(exit)
    b.return_([])
    let function = b.finalize()
    let original = function.print()
    let sites : Map[Int32, Bool] = Map([])
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        if @wasm_milkir.decode_opcode(
            function.instruction_by_id(id).unwrap().opcode,
          )
          is Some(StructNewDefault(_)) {
          sites[id] = true
        }
      }
    }
    let edit = prepare_allocation_admission(
      function,
      allocation_contract_context(),
      sites,
    )
    if barrier {
      assert_true(edit is None)
    } else {
      guard edit is Some(edit) else {
        fail("collecting allocations preserve admission metadata")
      }
      assert_eq(
        edit.operations.values().filter(op => op is Acquire(_)).count(),
        1,
      )
      assert_eq(
        edit.operations.values().filter(op => op is New(_, _)).count(),
        2,
      )
      (edit.restore)()
    }
    assert_eq(function.print(), original)
  }
}

///|
test "allocation admission rejects wrong origins and all incoming barriers" {
  for mode in ["valid", "type", "forged", "join", "backedge"] {
    let b = @milkir.FunctionBuilder("admission_lifetime_\{mode}")
    let condition = b.add_param(I32)
    let acquire : AllocationAdmission = Acquire(0)
    let token = b.emit_ext_inst(Ptr, acquire.opcode(), [])
    let header = b.create_block()
    let yes = b.create_block()
    let no = b.create_block()
    let join = b.create_block()
    let exit = b.create_block()
    b.jump(header, [])
    b.switch_to_block(header)
    b.branch(condition, yes, [], no, [])
    b.switch_to_block(yes)
    if mode == "join" {
      b.emit_void_ext_inst(@wasm_milkir.encode(WasmCall(0)), [])
    }
    b.jump(join, [])
    b.switch_to_block(no)
    b.jump(join, [])
    b.switch_to_block(join)
    let used = if mode == "forged" { b.add_param(Ptr) } else { token }
    let allocation : AllocationAdmission = New(
      if mode == "type" {
        1
      } else {
        0
      },
      true,
    )
    b.emit_ext_inst(Ref, allocation.opcode(), [used]) |> ignore
    if mode == "backedge" {
      b.emit_void_ext_inst(@wasm_milkir.encode(WasmCall(0)), [])
    }
    b.branch(condition, header, [], exit, [])
    b.switch_to_block(exit)
    b.return_([])
    let error = allocation_admission_error(b.finalize())
    assert_eq(error is None, mode == "valid", msg=mode)
  }
}

///|
test "collecting fallback invalidates admission cells for other types" {
  let b = @milkir.FunctionBuilder("different_admission_cells")
  let first : AllocationAdmission = Acquire(0)
  let second : AllocationAdmission = Acquire(1)
  let a = b.emit_ext_inst(Ptr, first.opcode(), [])
  let c = b.emit_ext_inst(Ptr, second.opcode(), [])
  let allocation : AllocationAdmission = New(0, true)
  b.emit_ext_inst(Ref, allocation.opcode(), [a]) |> ignore
  let stale : AllocationAdmission = New(1, true)
  b.emit_ext_inst(Ref, stale.opcode(), [c]) |> ignore
  b.return_([])
  assert_true(allocation_admission_error(b.finalize()) is Some(_))
}

///|
test "allocation admission recognizes prepared noncollecting projections" {
  let b = @milkir.FunctionBuilder("prepared_allocation_admission")
  let count = b.add_param(I32)
  let header = b.create_block()
  let body = b.create_block()
  let exit = b.create_block()
  let index = b.add_block_param(header, I32)
  b.jump(header, [b.iconst_i32(0)])
  b.switch_to_block(header)
  b.branch(b.icmp_slt(index, count), body, [], exit, [])
  b.switch_to_block(body)
  let object = @wasm_milkir.struct_new_default(b, 0)
  @wasm_milkir.struct_get(b, 0, 0, object, I64) |> ignore
  @wasm_milkir.struct_new_default(b, 0) |> ignore
  b.jump(header, [b.iadd(index, b.iconst_i32(1))])
  b.switch_to_block(exit)
  b.return_([])
  let function = b.finalize()
  prepare_gc_memory(function, allocation_contract_context())
  assert_true(
    function.blocks.any(block => {
      function
      .block_instruction_ids(block)
      .any(id => {
        function.instruction_by_id(id).unwrap().opcode is Ext(op, _) &&
        decode_projection(op) is Some(_)
      })
    }),
  )
  let sites : Map[Int32, Bool] = Map([])
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      if @wasm_milkir.decode_opcode(
          function.instruction_by_id(id).unwrap().opcode,
        )
        is Some(StructNewDefault(_)) {
        sites[id] = true
      }
    }
  }
  guard prepare_allocation_admission(
      function,
      allocation_contract_context(),
      sites,
    )
    is Some(edit) else {
    fail(
      "prepared noncollecting projections must not count as unknown allocations",
    )
  }
  (edit.restore)()
}
