///|
test "simple function signatures include abstract GC reference types" {
  let expected : @types.FuncType = {
    params: [StructRef, RefStructAbs],
    results: [ArrayRef, RefArrayAbs],
  }
  let actual : @types.FuncType = {
    params: [StructRef, RefStructAbs],
    results: [ArrayRef, RefArrayAbs],
  }
  let different : @types.FuncType = {
    params: [ArrayRef, RefArrayAbs],
    results: [StructRef, RefStructAbs],
  }
  assert_true(@types.func_types_equal(actual, expected))
  assert_false(@types.func_types_equal(different, expected))
  assert_true(
    @types.TypeEquivalenceContext::cross_module(
      [@types.SubType::from_func(actual)],
      [@types.SubType::from_func(expected)],
    ).types_equivalent(0, 0),
  )
}

///|
test "type comparison rejects indices outside its defining graph" {
  let definitions : Array[@types.SubType] = [
    @types.SubType::from_func({ params: [], results: [], }),
  ]
  let subtyping = @types.SubtypingContext::same_module(definitions)
  let equality = @types.TypeEquivalenceContext::same_module(definitions)
  assert_true(subtyping.is_subtype(0, 0))
  assert_true(equality.types_equivalent(0, 0))
  for index in [-1, 1, 99] {
    assert_false(subtyping.is_subtype(index, index))
    assert_false(equality.types_equivalent(index, index))
  }
  assert_false(equality.types_equivalent(-1, 99))
}

///|
test "mutable reference fields compare types in their defining graphs" {
  let actual : Array[@types.SubType] = [
    @types.SubType::simple(
      Struct({ fields: [{ storage_type: Val(I32), mutable: false, }], }),
    ),
    @types.SubType::simple(
      Array({
        element: { storage_type: Val(RefNullStruct(0)), mutable: true, },
      }),
    ),
  ]
  let different : Array[@types.SubType] = [
    @types.SubType::simple(
      Struct({ fields: [{ storage_type: Val(I64), mutable: false, }], }),
    ),
    {
      final_: false,
      supertypes: [],
      composite: Array({
        element: { storage_type: Val(RefNullStruct(0)), mutable: true, },
      }),
    },
  ]
  assert_false(
    @types.SubtypingContext::cross_module(actual, different).validate_declared_subtype(
      1, 1,
    ),
  )
  let recursive : Array[@types.SubType] = [
    @types.SubType::simple(
      Struct({
        fields: [{ storage_type: Val(RefNullStruct(0)), mutable: false, }],
      }),
    ),
    actual[1],
  ]
  let shifted : Array[@types.SubType] = [
    @types.SubType::from_func({ params: [], results: [], }),
    @types.SubType::simple(
      Struct({
        fields: [{ storage_type: Val(RefNullStruct(1)), mutable: false, }],
      }),
    ),
    {
      final_: false,
      supertypes: [],
      composite: Array({
        element: { storage_type: Val(RefNullStruct(1)), mutable: true, },
      }),
    },
  ]
  assert_true(
    @types.SubtypingContext::cross_module(recursive, shifted).validate_declared_subtype(
      1, 2,
    ),
  )
}
