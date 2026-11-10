///|
test "borrow reuse requires both a read-only proof and its exact validated annotation" {
  let proof = test_context(function_effects=Map([(7, NonCollectingReadOnly)]))
  let mutable_context = test_context(
    function_effects=Map([(7, NonCollectingReadWrite)]),
  )
  let b = @milkir.FunctionBuilder("readonly_borrow")
  b.add_param(I64) |> ignore
  let object = b.add_param(Ref)
  b.add_result(I32)
  let pointer = b.emit_ext_inst(Ptr, projection_opcode(StructData(0)), [object])
  let field = b.emit_ext_inst(
    Ptr,
    projection_opcode(FieldData(0, 0, 4, 0, true)),
    [pointer],
  )
  let call = annotate_semantic(
    @wasm_milkir.encode(WasmCall(7)),
    Signature([Ref], []),
    validation_context=Some(proof),
  )
  b.emit_void_ext_inst(call, [object])
  let result = b.load_ptr(I32, field, b.iconst_i64(0L))
  b.return_([result])
  let function = b.finalize()
  assert_eq(gc_borrow_error(function, validation_context=Some(proof)), None)
  assert_true(gc_borrow_error(function).unwrap().contains("outlived"))
  assert_true(
    gc_borrow_error(function, validation_context=Some(mutable_context))
    .unwrap()
    .contains("outlived"),
  )
  let original = function.print()
  try prepare_gc_memory(function, mutable_context) catch {
    error =>
      assert_true(
        error.to_string().contains("invalid refined Wasm memory effects"),
      )
  } noraise {
    _ => fail("unproved call annotation was accepted")
  }
  assert_eq(function.print(), original)
  prepare_gc_memory(function, proof)
}

///|
fn readonly_value_call_count(function : @milkir.Function) -> Int32 {
  let mut count = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      if @wasm_milkir.decode_opcode(
          function.instruction_by_id(id).unwrap().opcode,
        )
        is Some(WasmCall(8)) {
        count += 1
      }
    }
  }
  count
}

///|
test "read-only value calls reuse only the same receiver in the same memory and address epoch" {
  for scenario in 0..<6 {
    let b = @milkir.FunctionBuilder("readonly_values")
    b.add_param(I64) |> ignore
    let object = b.add_param(Ref)
    let other = b.add_param(Ref)
    b.add_result(I32)
    let field = @wasm_milkir.struct_get(b, 0, 0, object, I32)
    let first = @wasm_milkir.call_multi(b, 8, [I32], [object])[0]
    match scenario {
      1 => @wasm_milkir.struct_new_default(b, 0) |> ignore
      2 => @wasm_milkir.struct_set(b, 0, 0, object, b.iconst_i32(9))
      3 => @wasm_milkir.call_multi(b, 7, [], [object]) |> ignore
      _ => ()
    }
    let second = @wasm_milkir.call_multi(b, 8, [I32], [
        if scenario == 4 {
          other
        } else {
          object
        },
      ])[0]
    b.return_([b.iadd(field, b.iadd(first, second))])
    let function = b.finalize()
    let effects = if scenario == 5 {
      Map([])
    } else {
      Map([
        (7, @wasm_milkir.WasmFunctionEffects::NonCollectingReadWrite),
        (8, NonCollectingReadOnly),
      ])
    }
    optimize_memory_test(function, test_context(function_effects=effects), O2)
    |> ignore
    assert_eq(
      readonly_value_call_count(function),
      if scenario == 0 {
        1
      } else {
        2
      },
    )
  }
}

///|
test "read-only value call reuse does not cross conditional movement or side entries" {
  for moving in [false, true] {
    let b = @milkir.FunctionBuilder("readonly_join")
    b.add_param(I64) |> ignore
    let object = b.add_param(Ref)
    let condition = b.add_param(I32)
    b.add_result(I32)
    let field = @wasm_milkir.struct_get(b, 0, 0, object, I32)
    let left = b.create_block()
    let right = b.create_block()
    let join = b.create_block()
    let incoming = b.add_block_param(join, I32)
    let before = if moving {
      @wasm_milkir.call_multi(b, 8, [I32], [object])[0]
    } else {
      field
    }
    b.branch(condition, left, [], right, [])
    b.switch_to_block(left)
    let value = if moving {
      @wasm_milkir.struct_new_default(b, 0) |> ignore
      before
    } else {
      @wasm_milkir.call_multi(b, 8, [I32], [object])[0]
    }
    b.jump(join, [value])
    b.switch_to_block(right)
    b.jump(join, [before])
    b.switch_to_block(join)
    let after = @wasm_milkir.call_multi(b, 8, [I32], [object])[0]
    b.return_([b.iadd(incoming, after)])
    let function = b.finalize()
    optimize_memory_test(
      function,
      test_context(function_effects=Map([(8, NonCollectingReadOnly)])),
      O2,
    )
    |> ignore
    assert_eq(readonly_value_call_count(function), 2)
  }
}

///|
test "address-epoch hints require exact native validation and are rejected at the semantic seam" {
  let proof = test_context(function_effects=Map([(8, NonCollectingReadOnly)]))
  let plain = @wasm_milkir.encode(WasmCall(8))
  let refined = annotate_semantic(
    plain,
    Signature([Ref], [I32]),
    validation_context=Some(proof),
  )
  for effects in [None, refined.effects] {
    let b = @milkir.FunctionBuilder("forged_epoch")
    b.add_param(I64) |> ignore
    let object = b.add_param(Ref)
    b.add_result(I32)
    let result = b.emit_ext_inst(
      I32,
      ExtOp(
        plain.dialect,
        plain.opcode,
        plain.immediates,
        effects~,
        reads_address_epoch=effects is None,
      ),
      [object],
    )
    b.return_([result])
    let function = b.finalize()
    let before = function.print()
    try @wasm_milkir.verify_function_with_context(function, proof) catch {
      error =>
        assert_true(error.to_string().contains("unchecked optimizer effects"))
    } noraise {
      _ => fail("semantic seam accepted an optimizer hint")
    }
    try prepare_gc_memory(function, proof) catch {
      error =>
        assert_true(
          error.to_string().contains("invalid refined Wasm memory effects"),
        )
    } noraise {
      _ => fail("native seam accepted an incomplete epoch hint")
    }
    assert_eq(function.print(), before)
  }
}

///|
test "separate shared-global address constants do not hide equivalent read-only call receivers" {
  let b = @milkir.FunctionBuilder("shared_cell_readonly")
  let context = b.add_param(I64)
  let index = b.add_param(I32)
  b.add_result(I32)
  let globals = b.load_ptr(I64, context, b.iconst_i64(32L))
  let cell = b.load_ptr(I64, globals, b.iconst_i64(256L))
  let object = b.load_ptr(Ref, cell, b.iconst_i64(0L))
  let first = @wasm_milkir.call_multi(b, 8, [I32], [object])[0]
  let field = @wasm_milkir.struct_get(b, 0, 0, object, I32)
  let globals_again = b.load_ptr(I64, context, b.iconst_i64(32L))
  let cell_again = b.load_ptr(I64, globals_again, b.iconst_i64(256L))
  let object_again = b.load_ptr(Ref, cell_again, b.iconst_i64(0L))
  let second = @wasm_milkir.call_multi(b, 8, [I32], [object_again])[0]
  b.return_([b.iadd(index, b.iadd(field, b.iadd(first, second)))])
  let function = b.finalize()
  optimize_memory_test(
    function,
    test_context(function_effects=Map([(8, NonCollectingReadOnly)])),
    O2,
  )
  |> ignore
  assert_eq(readonly_value_call_count(function), 1)
}
