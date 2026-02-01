// ============================================================
// Conversion instruction tests for boundary cases
// ============================================================

///|
test "i32.trunc_f64_u: value in (-1, 0) truncates to 0" {
  let mod = @types.Module::simple(
    [@types.ValueType::F64],
    [@types.ValueType::I32],
    [LocalGet(0), I32TruncF64U],
    "trunc",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "trunc", [F64(-0.9)])
  match results[0] {
    I32(n) => inspect(n, content="0")
    _ => fail("Expected I32 result")
  }
}

///|
test "i32.trunc_f32_u: value in (-1, 0) truncates to 0" {
  let mod = @types.Module::simple(
    [@types.ValueType::F32],
    [@types.ValueType::I32],
    [LocalGet(0), I32TruncF32U],
    "trunc",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "trunc", [F32(-0.5)])
  match results[0] {
    I32(n) => inspect(n, content="0")
    _ => fail("Expected I32 result")
  }
}

///|
test "i64.trunc_f64_u: large value near 2^64" {
  let mod = @types.Module::simple(
    [@types.ValueType::F64],
    [@types.ValueType::I64],
    [LocalGet(0), I64TruncF64U],
    "trunc",
  )
  let (store, instance) = instantiate_module(mod)
  let pow2_63 = @math.pow(2.0, 63.0)
  let results = call_exported_func(store, instance, "trunc", [F64(pow2_63)])
  match results[0] {
    I64(n) => inspect(n, content="-9223372036854775808")
    _ => fail("Expected I64 result")
  }
}

///|
test "i64.trunc_sat_f64_u: large value saturates correctly" {
  let mod = @types.Module::simple(
    [@types.ValueType::F64],
    [@types.ValueType::I64],
    [LocalGet(0), I64TruncSatF64U],
    "trunc_sat",
  )
  let (store, instance) = instantiate_module(mod)
  let pow2_64 = @math.pow(2.0, 64.0)
  let results = call_exported_func(store, instance, "trunc_sat", [F64(pow2_64)])
  match results[0] {
    I64(n) => inspect(n, content="-1")
    _ => fail("Expected I64 result")
  }
}

///|
test "i64.trunc_sat_f64_u: value in range converts correctly" {
  let mod = @types.Module::simple(
    [@types.ValueType::F64],
    [@types.ValueType::I64],
    [LocalGet(0), I64TruncSatF64U],
    "trunc_sat",
  )
  let (store, instance) = instantiate_module(mod)
  let pow2_63 = @math.pow(2.0, 63.0)
  let results = call_exported_func(store, instance, "trunc_sat", [F64(pow2_63)])
  match results[0] {
    I64(n) => inspect(n, content="-9223372036854775808")
    _ => fail("Expected I64 result")
  }
}

///|
test "i32.trunc_f64_s: boundary near INT32_MIN" {
  let mod = @types.Module::simple(
    [@types.ValueType::F64],
    [@types.ValueType::I32],
    [LocalGet(0), I32TruncF64S],
    "trunc",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "trunc", [
    F64(-2147483648.0),
  ])
  match results[0] {
    I32(n) => inspect(n, content="-2147483648")
    _ => fail("Expected I32 result")
  }
}

///|
test "executor: normalize_runtime_error preserves runtime errors" {
  let errors : Array[@runtime.RuntimeError] = [
    @runtime.StackUnderflow,
    @runtime.StackOverflow,
    @runtime.TypeMismatch,
    @runtime.OutOfBoundsMemoryAccess,
    @runtime.OutOfBoundsTableAccess,
    @runtime.OutOfBoundsArrayAccess,
    @runtime.UndefinedElement,
    @runtime.UninitializedElement,
    @runtime.IndirectCallTypeMismatch,
    @runtime.DivisionByZero,
    @runtime.IntegerOverflow,
    @runtime.InvalidConversion,
    @runtime.Unreachable,
    @runtime.CallStackExhausted,
    @runtime.UnknownImport("test_mod", "test_field"),
    @runtime.LinkError,
    @runtime.LinkErrorDetail("test detail"),
    @runtime.NullReference,
    @runtime.UnalignedAtomic,
    @runtime.InvalidConstantExpression("test detail"),
  ]
  for err in errors {
    let mapped = normalize_runtime_error(err)
    assert_true(
      @runtime.format_runtime_error(mapped) ==
      @runtime.format_runtime_error(err),
    )
  }
}

///|
test "executor: normalize_runtime_error converts leaked control signals to unreachable" {
  // Whitebox test: ControlSignal is internal and should never leak as a public API error.
  let mapped = normalize_runtime_error(ControlSignal::Return)
  inspect(mapped.to_string(), content="unreachable")
}

///|
test "executor: const expr supports extern.convert_any/any.convert_extern" {
  // Mirrors spec/gc/extern.wast global initializers.
  let mod : @types.Module = {
    ..@types.Module::empty(),
    globals: [
      {
        type_: { value_type: @types.ValueType::ExternRef, mutable: false },
        init: [RefNull(@types.ValueType::AnyRef), ExternConvertAny],
      },
      {
        type_: { value_type: @types.ValueType::AnyRef, mutable: false },
        init: [RefNull(@types.ValueType::ExternRef), AnyConvertExtern],
      },
      {
        type_: { value_type: @types.ValueType::AnyRef, mutable: false },
        init: [I32Const(7), RefI31, ExternConvertAny, AnyConvertExtern],
      },
    ],
    exports: [
      { name: "g_extern_null", desc: Global(0) },
      { name: "g_any_null", desc: Global(1) },
      { name: "g_any_i31", desc: Global(2) },
    ],
  }
  let (store, instance) = instantiate_module(mod)
  inspect(get_exported_global(store, instance, "g_extern_null"), content="Null")
  inspect(get_exported_global(store, instance, "g_any_null"), content="Null")
  inspect(get_exported_global(store, instance, "g_any_i31"), content="I31(7)")
}
