///|
test "reference box promotion exposes constructor field SSA in the same pipeline" {
  let context = @wasm_milkir.WasmValidationContext::new({
    function_contract: _ => None,
    defined_type_contract: index => {
      if index == 0 {
        Some(
          Struct([{ storage: Value(I32), mutable_: false, defaultable: true, }]),
        )
      } else {
        Some(
          Struct([{ storage: Value(Ref), mutable_: true, defaultable: true, }]),
        )
      }
    },
    table_contract: _ => None,
    tag_contract: _ => None,
    memory_exists: _ => false,
    data_segment_exists: _ => false,
    element_segment_type: _ => None,
  })
  let b = @milkir.FunctionBuilder("reference_box_fields")
  let initial = b.add_param(Ref)
  let limit = b.add_param(I32)
  b.add_result(I32)
  let box = @wasm_milkir.struct_new(b, 1, [initial])
  let header = b.create_block()
  let index = b.add_block_param(header, I32)
  let body = b.create_block()
  let exit = b.create_block()
  b.jump(header, [b.iconst_i32(0)])
  b.switch_to_block(header)
  let object = @wasm_milkir.struct_get(b, 1, 0, box, Ref)
  let value = @wasm_milkir.struct_get(b, 0, 0, object, I32)
  b.branch(b.icmp_slt(index, limit), body, [], exit, [])
  b.switch_to_block(body)
  let next = @wasm_milkir.struct_new(b, 0, [b.iadd(value, b.iconst_i32(1))])
  @wasm_milkir.struct_set(b, 1, 0, box, next)
  b.jump(header, [b.iadd(index, b.iconst_i32(1))])
  b.switch_to_block(exit)
  b.return_([value])
  let function = b.finalize()
  optimize_with_level(function, context, O2) |> ignore
  let cfg = @milkir.CFG::build(function)
  for loop_ in cfg.find_loops() {
    for block in function.blocks {
      if loop_.contains(block.id) {
        assert_false(
          function
          .block_instruction_ids(block)
          .any(id => {
            @wasm_milkir.decode_opcode(
              function.instruction_by_id(id).unwrap().opcode,
            )
            is Some(StructGet(_, _))
          }),
        )
      }
    }
  }
  assert_true(function.print().contains("struct_new"))
  @wasm_milkir.verify_function_with_context(function, context)
}
