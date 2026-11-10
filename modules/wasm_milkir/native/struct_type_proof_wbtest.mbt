///|
test "struct type facts survive allocation but physical views expire" {
  for reentry in [false, true] {
    let b = @milkir.FunctionBuilder("struct_type_epoch")
    let object = b.add_param(Ref)
    b.add_result(I32)
    let first = b.emit_ext_inst(Ptr, projection_opcode(StructData(0)), [object])
    let field = b.emit_ext_inst(
      Ptr,
      projection_opcode(FieldData(0, 0, 4, 0, true)),
      [first],
    )
    b.load_ptr(I32, field, b.iconst_i64(0L)) |> ignore
    @wasm_milkir.struct_new(b, 0, [b.iconst_i32(9)]) |> ignore
    if reentry {
      let symbol = b.get_function().declare_external_symbol("opaque")
      b.call_symbol(symbol, None, [object]) |> ignore
    }
    let second = b.emit_ext_inst(Ptr, projection_opcode(StructData(0)), [object])
    let value = b.emit_ext_inst(
      Ptr,
      projection_opcode(FieldData(0, 0, 4, 0, true)),
      [second],
    )
    b.return_([b.load_ptr(I32, value, b.iconst_i64(0L))])
    let function = b.finalize()
    assert_true(verify_gc_borrows(function))
    let sites = checked_struct_projection_sites(function)
    assert_false(sites.contains(function.defining_inst(first).unwrap().id))
    assert_eq(
      sites.contains(function.defining_inst(second).unwrap().id),
      !reentry,
    )
  }
}

///|
test "struct type facts intersect at joins without conflating references or types" {
  for mode in 0..<4 {
    let b = @milkir.FunctionBuilder("joined_struct_type_epoch")
    let object = b.add_param(Ref)
    let other = b.add_param(Ref)
    let choice = b.add_param(I32)
    let left = b.create_block()
    let right = b.create_block()
    let join = b.create_block()
    b.branch(choice, left, [], right, [])
    b.switch_to_block(left)
    b.emit_ext_inst(Ptr, projection_opcode(StructData(0)), [object]) |> ignore
    b.jump(join, [])
    b.switch_to_block(right)
    if mode != 1 {
      b.emit_ext_inst(
        Ptr,
        projection_opcode(StructData(if mode == 2 { 1 } else { 0 })),
        [if mode == 3 { other } else { object }],
      )
      |> ignore
    }
    b.jump(join, [])
    b.switch_to_block(join)
    let view = b.emit_ext_inst(Ptr, projection_opcode(StructData(0)), [object])
    b.return_([])
    let function = b.finalize()
    assert_true(verify_gc_borrows(function))
    assert_eq(
      checked_struct_projection_sites(function).contains(
        function.defining_inst(view).unwrap().id,
      ),
      mode == 0,
    )
  }
}

///|
test "only verified payload stores preserve struct type facts" {
  for known in [false, true] {
    let b = @milkir.FunctionBuilder("stored_struct_type_epoch")
    let object = b.add_param(Ref)
    let pointer = b.add_param(Ptr)
    let view = b.emit_ext_inst(Ptr, projection_opcode(StructData(0)), [object])
    let field = b.emit_ext_inst(
      Ptr,
      projection_opcode(FieldData(0, 0, 4, 0, false)),
      [view],
    )
    b.store_ptr(
      I32,
      if known {
        field
      } else {
        pointer
      },
      b.iconst_i32(42),
      b.iconst_i64(0L),
    )
    let later = b.emit_ext_inst(Ptr, projection_opcode(StructData(0)), [object])
    b.return_([])
    let function = b.finalize()
    assert_true(verify_gc_borrows(function))
    assert_eq(
      checked_struct_projection_sites(function).contains(
        function.defining_inst(later).unwrap().id,
      ),
      known,
    )
  }
}

///|
test "loop backedges cannot invent a first struct check" {
  let b = @milkir.FunctionBuilder("loop_struct_type_epoch")
  let object = b.add_param(Ref)
  let condition = b.add_param(I32)
  let header = b.create_block()
  let exit = b.create_block()
  b.jump(header, [])
  b.switch_to_block(header)
  let first = b.emit_ext_inst(Ptr, projection_opcode(StructData(0)), [object])
  let second = b.emit_ext_inst(Ptr, projection_opcode(StructData(0)), [object])
  b.branch(condition, header, [], exit, [])
  b.switch_to_block(exit)
  b.return_([])
  let function = b.finalize()
  assert_true(verify_gc_borrows(function))
  let sites = checked_struct_projection_sites(function)
  assert_false(sites.contains(function.defining_inst(first).unwrap().id))
  assert_true(sites.contains(function.defining_inst(second).unwrap().id))
}

///|
test "cached poll slow paths revoke struct type facts" {
  for fresh in [false, true] {
    let b = @milkir.FunctionBuilder("cached_poll_type_epoch")
    let object = b.add_param(Ref)
    b.emit_ext_inst(Ptr, projection_opcode(StructData(0)), [object]) |> ignore
    let layout : PollCacheLayout = {
      execution: -224,
      controls: 64,
      callback: 0,
      budget: 16,
    }
    b.emit_ext_inst(
      I32,
      CachedPoll::Step(layout, fresh).opcode(),
      if fresh {
        []
      } else {
        [b.iconst_i32(2)]
      },
    )
    |> ignore
    let later = b.emit_ext_inst(Ptr, projection_opcode(StructData(0)), [object])
    b.return_([])
    let function = b.finalize()
    assert_true(verify_gc_borrows(function))
    assert_false(
      checked_struct_projection_sites(function).contains(
        function.defining_inst(later).unwrap().id,
      ),
    )
  }
}

///|
test "struct type fact budgets preserve the high mask bit without aliasing overflow" {
  let b = @milkir.FunctionBuilder("many_struct_type_keys")
  let object = b.add_param(Ref)
  for type_ in 0..<65 {
    b.emit_ext_inst(Ptr, projection_opcode(StructData(type_)), [object])
    |> ignore
  }
  let checks : Array[@milkir.Value] = []
  for type_ in 0..<65 {
    checks.push(
      b.emit_ext_inst(Ptr, projection_opcode(StructData(type_)), [object]),
    )
  }
  b.return_([])
  let function = b.finalize()
  assert_true(verify_gc_borrows(function))
  let sites = checked_struct_projection_sites(function)
  for type_ in 0..<65 {
    assert_eq(
      sites.contains(function.defining_inst(checks[type_]).unwrap().id),
      type_ < 64,
    )
  }
}
