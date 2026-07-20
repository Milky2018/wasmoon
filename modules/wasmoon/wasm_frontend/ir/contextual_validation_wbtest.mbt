///|
test "frontend validation context resolves linked and module-local contracts" {
  let mod_ = @types.Module::empty()
  mod_.types.push(@types.SubType::func([I32], [I64]))
  mod_.types.push(
    @types.SubType::simple(
      Struct({ fields: [{ storage_type: Val(F64), mutable: true }] }),
    ),
  )
  mod_.types.push(
    @types.SubType::simple(
      Array({ element: { storage_type: Packed(I8), mutable: true } }),
    ),
  )
  mod_.types.push(@types.SubType::func([I32, F64], []))
  mod_.funcs.push(0)
  mod_.tables.push({
    type_: {
      limits: { min: 0L, max: None },
      elem_type: FuncRef,
      is_table64: true,
    },
    init: None,
  })
  mod_.tags.push({ type_idx: 3 })
  mod_.datas.push({ memory_idx: 0, offset: [], init: Bytes::from_array([]) })
  let translation_context = TranslationContext::from_module(
    mod_,
    EmbeddingEnvironment(),
    func_base=10,
  )
  let validation_context = translation_context.wasm_validation_context()

  let direct = @milkir.FunctionBuilder::FunctionBuilder("linked_call")
  let direct_argument = direct.add_param(I32)
  direct.add_result(I64)
  let direct_results = @wasm_milkir.call_multi(direct, 10, [I64], [
    direct_argument,
  ])
  direct.return_(direct_results)
  @wasm_milkir.verify_function_with_context(
    direct.get_function(),
    validation_context,
  )

  let indirect = @milkir.FunctionBuilder::FunctionBuilder("table64_call")
  let table_index = indirect.add_param(I64)
  let indirect_argument = indirect.add_param(I32)
  indirect.add_result(I64)
  let indirect_results = @wasm_milkir.call_indirect_multi(
    indirect,
    0,
    0,
    [I64],
    table_index,
    [indirect_argument],
  )
  indirect.return_(indirect_results)
  @wasm_milkir.verify_function_with_context(
    indirect.get_function(),
    validation_context,
  )

  let aggregate = @milkir.FunctionBuilder::FunctionBuilder("aggregate")
  let reference = aggregate.add_param(Ref)
  aggregate.add_result(F64)
  let field = @wasm_milkir.struct_get(aggregate, 1, 0, reference, F64)
  aggregate.return_([field])
  @wasm_milkir.verify_function_with_context(
    aggregate.get_function(),
    validation_context,
  )

  let thrown = @milkir.FunctionBuilder::FunctionBuilder("throw")
  let integer = thrown.add_param(I32)
  let float = thrown.add_param(F64)
  @wasm_milkir.emit_throw(thrown, 0, [integer, float])
  thrown.trap("unreachable after throw")
  @wasm_milkir.verify_function_with_context(
    thrown.get_function(),
    validation_context,
  )
}
