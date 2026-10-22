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
    for
      suffix in [
        "gc.struct_get_heap", "gc.struct_set_heap", "gc.array_get_heap", "gc.array_set_heap",
        "gc.array_len_heap",
      ] {
      assert_true(diagnostics.code_object.contains(suffix))
    }
  }
}
