///|
test "both targets select explicit heap GC word helper contracts" {
  let context = @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(index) {
      match index {
        0 =>
          Some(
            Struct([{ storage: Packed8, mutable_: true, defaultable: true, }]),
          )
        1 =>
          Some(
            Array({ storage: Value(I32), mutable_: true, defaultable: true, }),
          )
        _ => None
      }
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
  let builder = @milkir.FunctionBuilder::FunctionBuilder("planned_gc_access")
  builder.add_param(Ptr) |> ignore
  let struct_ref = builder.add_param(Ref)
  let array_ref = builder.add_param(Ref)
  let index = builder.add_param(I32)
  let value = builder.add_param(I32)
  builder.add_result(I32)
  @wasm_milkir.struct_set(builder, 0, 0, struct_ref, value)
  @wasm_milkir.array_set(builder, 1, array_ref, index, value)
  let field = @wasm_milkir.struct_get_u(builder, 0, 0, struct_ref, 1)
  let element = @wasm_milkir.array_get(builder, 1, array_ref, index, I32)
  let length = @wasm_milkir.array_len(builder, array_ref)
  let sum = builder.iadd(field, element)
  builder.return_([builder.iadd(sum, length)])
  for target in [@wasmoon_jit.NativeTarget::X64, AArch64] {
    let diagnostics = @wasmoon_jit.compile_wasm_body_diagnostics_for_target(
      builder.get_function(),
      context,
      target,
    )
    assert_true(diagnostics.code_object.contains("gc.array_data_heap"))
    for
      suffix in [
        "gc.struct_get_heap", "gc.struct_set_heap", "gc.array_get_heap", "gc.array_set_heap",
        "gc.array_len_heap",
      ] {
      assert_true(diagnostics.code_object.contains(suffix))
    }
  }
}

///|
test "both targets materialize one preheader view for an entire array loop" {
  let context = @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(_) {
      Some(Array({ storage: Value(I32), mutable_: true, defaultable: true, }))
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
  let b = @milkir.FunctionBuilder::FunctionBuilder("borrowed_array_loop")
  b.add_param(Ptr) |> ignore
  let a = b.add_param(Ref)
  b.add_result(I32)
  let length = @wasm_milkir.array_len(b, a)
  let header = b.create_block()
  let i = b.add_block_param(header, I32)
  let body = b.create_block()
  let exit = b.create_block()
  b.jump(header, [b.iconst_i32(0)])
  b.switch_to_block(header)
  b.branch(b.icmp_ult(i, length), body, [], exit, [])
  b.switch_to_block(body)
  let old = @wasm_milkir.array_get(b, 0, a, i, I32)
  @wasm_milkir.array_set(b, 0, a, i, b.iadd(old, b.iconst_i32(1)))
  b.jump(header, [b.iadd(i, b.iconst_i32(1))])
  b.switch_to_block(exit)
  b.return_([length])
  for target in [@wasmoon_jit.NativeTarget::X64, AArch64] {
    let code = @wasmoon_jit.compile_wasm_body_artifact_function(
      b.get_function(),
      context,
      target,
      function_index=0,
      signature=@native.Signature::new([GcRef64], [I32]),
    )
    let views = code.relocations.filter(r => {
      r.target is External(symbol) &&
      symbol.name == "wasmoon.runtime.gc.array_data_heap"
    })
    assert_eq(views.length(), 1)
  }
}
