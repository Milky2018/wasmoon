///|
fn verify_gc_borrows(function : @milkir.Function) -> Bool {
  gc_borrow_error(function) is None
}

///|
test "memory SSA rejects physical borrows across every moving or reentrant route" {
  for
    barrier in [
      "none", "alias", "call", "allocation", "raw_write", "chain", "join", "partial_join",
    ] {
    let builder = @milkir.FunctionBuilder("borrow_\{barrier}")
    let object = builder.add_param(Ref)
    let address = builder.add_param(Ptr)
    let condition = builder.add_param(I32)
    builder.add_result(I64)
    let pointer = builder.emit_ext_inst(Ptr, projection_opcode(ArrayData(8)), [
      object,
    ])
    let offset = builder.iconst_i64(16L)
    if barrier == "call" {
      let symbol = builder
        .get_function()
        .declare_external_symbol("moving_or_reentrant")
      builder.call_symbol(symbol, None, []) |> ignore
    } else if barrier == "allocation" {
      @wasm_milkir.array_new_default(builder, 0, condition) |> ignore
    } else if barrier == "raw_write" {
      builder.store_ptr(I64, address, builder.iconst_i64(0L), offset)
    } else if barrier == "alias" {
      builder.store_ptr(I64, pointer, builder.iconst_i64(42L), offset)
    } else if barrier == "chain" {
      let next = builder.create_block()
      builder.jump(next, [])
      builder.switch_to_block(next)
    } else if barrier == "join" || barrier == "partial_join" {
      let left = builder.create_block()
      let right = builder.create_block()
      let join = builder.create_block()
      builder.branch(condition, left, [], right, [])
      builder.switch_to_block(left)
      if barrier == "partial_join" {
        let symbol = builder
          .get_function()
          .declare_external_symbol("reentry_on_one_path")
        builder.call_symbol(symbol, None, []) |> ignore
      }
      builder.jump(join, [])
      builder.switch_to_block(right)
      builder.jump(join, [])
      builder.switch_to_block(join)
    }
    let value = builder.load_ptr(I64, pointer, offset)
    builder.return_([value])
    let function = builder.finalize()
    function.verify()
    assert_eq(
      verify_gc_borrows(function),
      barrier == "none" ||
      barrier == "alias" ||
      barrier == "chain" ||
      barrier == "join",
    )
  }
}

///|
test "memory SSA cannot keep a projection alive around a collecting backedge" {
  for collecting in [false, true] {
    let builder = @milkir.FunctionBuilder("loop_borrow")
    let object = builder.add_param(Ref)
    let count = builder.add_param(I32)
    let pointer = builder.emit_ext_inst(Ptr, projection_opcode(ArrayData(8)), [
      object,
    ])
    let offset = builder.iconst_i64(16L)
    let header = builder.create_block()
    let index = builder.add_block_param(header, I32)
    let body = builder.create_block()
    let exit = builder.create_block()
    builder.jump(header, [builder.iconst_i32(0)])
    builder.switch_to_block(header)
    builder.branch(builder.icmp_ult(index, count), body, [], exit, [])
    builder.switch_to_block(body)
    builder.load_ptr(I64, pointer, offset) |> ignore
    if collecting {
      @wasm_milkir.array_new_default(builder, 0, count) |> ignore
    }
    builder.jump(header, [builder.iadd(index, builder.iconst_i32(1))])
    builder.switch_to_block(exit)
    builder.return_([])
    let function = builder.finalize()
    function.verify()
    assert_eq(verify_gc_borrows(function), !collecting)
  }
}

///|
test "native memory contracts cannot be smuggled into semantic Wasm optimization" {
  let builder = @milkir.FunctionBuilder("forged_effects")
  let object = builder.add_param(Ref)
  let extension = annotate_semantic(
    @wasm_milkir.encode(ArrayLen),
    Signature([Ref], [I32]),
  )
  builder.emit_ext_inst(I32, extension, [object]) |> ignore
  builder.return_([])
  let function = builder.finalize()
  try
    @wasm_milkir.verify_function_with_context(function, array_access_context())
  catch {
    _ => ()
  } noraise {
    _ => fail("semantic verifier accepted unchecked optimizer effects")
  }
}
