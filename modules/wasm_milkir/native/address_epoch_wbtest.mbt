///|
test "logical field values survive collection while physical projections expire" {
  for same_field in [false, true] {
    let b = @milkir.FunctionBuilder("logical_and_physical_lifetimes")
    let object = b.add_param(Ref)
    let initial = b.add_param(I64)
    b.add_result(I64)
    b.add_result(I64)
    let first = @wasm_milkir.struct_get(b, 0, 0, object, I64)
    @wasm_milkir.struct_new(b, 0, [initial, initial]) |> ignore
    let second = @wasm_milkir.struct_get(
      b,
      0,
      if same_field {
        0
      } else {
        1
      },
      object,
      I64,
    )
    b.return_([first, second])
    let function = b.get_function()
    prepare_gc_memory(function, allocation_contract_context())
    let mut reads = 0
    let mut projections = 0
    let mut allocations = 0
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        let inst = function.instruction_by_id(id).unwrap()
        if inst.opcode is Memory(Load(I64)) {
          reads += 1
        }
        if inst.opcode is Ext(extension, _) &&
          decode_projection(extension) is Some(StructData(_)) {
          projections += 1
        }
        if @wasm_milkir.decode_opcode(inst.opcode) is Some(StructNew(_)) {
          allocations += 1
        }
      }
    }
    assert_eq(reads, if same_field { 1 } else { 2 })
    assert_eq(projections, if same_field { 1 } else { 2 })
    assert_eq(allocations, 1)
    assert_eq(gc_borrow_error(function), None)
  }
}

///|
test "logical reads still expire after alias writes and reentrant polls" {
  for poll in [false, true] {
    let b = @milkir.FunctionBuilder("logical_mutation_barriers")
    let object = b.add_param(Ref)
    let other = b.add_param(Ref)
    let initial = b.add_param(I64)
    b.add_result(I64)
    b.add_result(I64)
    let first = @wasm_milkir.struct_get(b, 0, 0, object, I64)
    if poll {
      b.emit_void_ext_inst(@wasm_milkir.encode(SafepointPoll(-8, 0, 16, 24)), [])
    } else {
      @wasm_milkir.struct_set(b, 0, 0, other, initial)
    }
    let second = @wasm_milkir.struct_get(b, 0, 0, object, I64)
    b.return_([first, second])
    let function = b.get_function()
    prepare_gc_memory(function, allocation_contract_context())
    assert_eq(gc_read_count(function), 2)
    assert_eq(gc_borrow_error(function), None)
  }
}
