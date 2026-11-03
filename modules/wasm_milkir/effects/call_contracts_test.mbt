///|
fn call_context() -> @wasm_milkir.WasmValidationContext {
  @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(_) { Some({ params: [Ref], results: [I64], }) },
    defined_type_contract: fn(_) {
      Some(
        Struct([{ storage: Value(I64), mutable_: true, defaultable: true, }]),
      )
    },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
}

///|
fn call_body(calls : Array[Int32], mode~ : String = "read") -> @milkir.Function {
  let b = @milkir.FunctionBuilder("read_only_template")
  b.add_param(I64) |> ignore
  let object = b.add_param(Ref)
  b.add_result(I64)
  b.emit_void_ext_inst(
    @wasm_milkir.encode(
      SafepointPoll(-224, 64, 0, if mode == "layout" { 20 } else { 16 }),
    ),
    [],
  )
  for target in calls {
    @wasm_milkir.call_multi(b, target, [I64], [object]) |> ignore
  }
  let result = @wasm_milkir.struct_get(
    b,
    0,
    if mode == "invalid" {
      1
    } else {
      0
    },
    object,
    I64,
  )
  if mode == "write" {
    @wasm_milkir.struct_set(b, 0, 0, object, result)
  }
  if mode == "allocate" {
    @wasm_milkir.struct_new(b, 0, [result]) |> ignore
  }
  b.return_([result])
  b.get_function()
}

///|
test "direct read-only contracts count transitive polls and repeated call edges" {
  let context = call_context()
  let contracts = @effects.read_only_call_contracts(
    Map([(0, call_body([])), (1, call_body([0, 0])), (2, call_body([1]))]),
    context,
  )
  assert_eq(contracts.length(), 3)
  assert_eq(contracts[0].polls, 1)
  assert_eq(contracts[1].polls, 3)
  assert_eq(contracts[2].polls, 4)
  assert_eq(contracts[2].layout, Some((-224, 64, 0, 16)))
  let bound = context.with_read_only_call_contracts(contracts)
  contracts.clear()
  assert_eq(bound.read_only_call_contract(2).map(c => c.polls), Some(4))
}

///|
test "unknown recursive mutable collecting and mismatched direct bodies fail closed" {
  let context = call_context()
  for mode in ["write", "allocate", "invalid"] {
    assert_eq(
      @effects.read_only_call_contracts(
        Map([(0, call_body([], mode~)), (1, call_body([0]))]),
        context,
      ).length(),
      0,
      msg=mode,
    )
  }
  assert_eq(
    @effects.read_only_call_contracts(
      Map([(0, call_body([1])), (1, call_body([0])), (2, call_body([99]))]),
      context,
    ).length(),
    0,
  )
  let different = @effects.read_only_call_contracts(
    Map([(0, call_body([], mode="layout")), (1, call_body([0]))]),
    context,
  )
  assert_eq(different.length(), 1)
  let wrong_signature = @milkir.FunctionBuilder("wrong_template_signature")
  wrong_signature.add_param(I64) |> ignore
  wrong_signature.add_result(I64)
  wrong_signature.return_([wrong_signature.iconst_i64(0L)])
  assert_eq(
    @effects.read_only_call_contracts(
      Map([(0, wrong_signature.get_function())]),
      context,
    ).length(),
    0,
  )
}
