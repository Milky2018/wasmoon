///|
test "atomic verifier rejects noninteger and oversized access contracts" {
  let shapes : Array[(Type, Int)] = [(F64, 64), (I32, 64), (I64, 128), (I32, 7)]
  for pair in shapes {
    let (ty, bits) = pair
    let builder = FunctionBuilder("bad_atomic")
    let pointer = builder.add_param(Ptr)
    let offset = builder.iconst_i64(0L)
    builder.atomic_load(ty, bits, pointer, offset) |> ignore
    builder.return_([])
    expect_verify_rejection(
      builder.get_function(),
      "atomic access type and width",
    )
  }
}

///|
test "atomic verifier rejects mismatched compare-exchange values" {
  let builder = FunctionBuilder("bad_atomic_cmpxchg")
  let pointer = builder.add_param(Ptr)
  let expected = builder.add_param(I32)
  let replacement = builder.add_param(I64)
  let offset = builder.iconst_i64(0L)
  builder.atomic_compare_exchange(32, pointer, expected, replacement, offset)
  |> ignore
  builder.return_([])
  expect_verify_rejection(
    builder.get_function(),
    "atomic compare-exchange operands",
  )
}
