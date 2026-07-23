///|
test "public context globals are function scoped and interned" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("context_global")
  let context = builder.add_param(Ptr)
  builder.add_result(I64)
  let field = @milkir.ContextField::new("demo", 0, [7], I64)
  let data = @milkir.GlobalValueData::context_field(field, Stable, Heap(7))
  let first = builder.get_function().declare_global_value(data)
  let second = builder.get_function().declare_global_value(data)
  let loaded = builder.global_value(first, context)
  builder.return_([loaded])
  let function = builder.finalize()
  debug_inspect(
    (first, second, function.global_values),
    content=(
      #|(
      #|  { id: 0 },
      #|  { id: 0 },
      #|  [
      #|    (
      #|      { id: 0 },
      #|      ContextField(
      #|        { dialect: "demo", key: 0, parameters: <FixedArray: [7]>, ty: I64 },
      #|        Stable,
      #|        Heap(7),
      #|      ),
      #|    ),
      #|  ],
      #|)
    ),
  )
  inspect(
    function.print(),
    content=(
      #|function context_global(v0:ptr) -> i64 {
      #|    gv0 = context_field demo:0[7] : i64 stable -> heap[7]
      #|block0:
      #|    v1:i64 = global_value gv0 v0
      #|    return v1
      #|}
      #|
    ),
  )
}

///|
test "public verifier rejects a foreign global value" {
  let first = @milkir.FunctionBuilder::FunctionBuilder("first")
  let first_context = first.add_param(Ptr)
  let field = @milkir.ContextField::new("demo", 0, [0], I64)
  let foreign = first
    .get_function()
    .declare_global_value(
      @milkir.GlobalValueData::context_field(field, Stable, Heap(0)),
    )
  first.global_value(foreign, first_context) |> ignore
  first.return_([])
  let second = @milkir.FunctionBuilder::FunctionBuilder("second")
  let second_context = second.add_param(Ptr)
  second.global_value(foreign, second_context) |> ignore
  second.return_([])
  try second.finalize() |> ignore catch {
    error =>
      debug_inspect(
        error,
        content=(
          #|ForeignGlobalValue(global_value_id=0)
        ),
      )
  } noraise {
    _ => fail("expected a foreign global value to be rejected")
  }
}
