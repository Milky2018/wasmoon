///|
test "render empty module" {
  inspect(render(@types.Module::empty()), content="(module\n)\n")
}

///|
test "render f32 literals preserves IEEE sign and NaN payload" {
  let module_ = @types.Module::simple(
    [],
    [],
    [
      F32Const(Float::reinterpret_from_uint(0x3fc00000U)),
      F32Const(Float::reinterpret_from_uint(0x80000000U)),
      F32Const(Float::reinterpret_from_uint(0x7f800000U)),
      F32Const(Float::reinterpret_from_uint(0xffc12345U)),
    ],
    "float32",
  )
  let wat = render(module_)
  assert_true(wat.contains("f32.const 1.5"))
  assert_true(wat.contains("f32.const -0"))
  assert_true(wat.contains("f32.const inf"))
  assert_true(wat.contains("f32.const -nan:0x412345"))
}

///|
test "render f64 literals preserves IEEE sign and NaN payload" {
  let module_ = @types.Module::simple(
    [],
    [],
    [
      F64Const(0x3ff8000000000000UL.reinterpret_as_double()),
      F64Const(0x8000000000000000UL.reinterpret_as_double()),
      F64Const(0x7ff0000000000000UL.reinterpret_as_double()),
      F64Const(0xfff8123456789abcUL.reinterpret_as_double()),
    ],
    "float64",
  )
  let wat = render(module_)
  assert_true(wat.contains("f64.const 1.5"))
  assert_true(wat.contains("f64.const -0"))
  assert_true(wat.contains("f64.const inf"))
  assert_true(wat.contains("f64.const -nan:0x8123456789abc"))
}

///|
test "render one function uses the canonical module instruction spelling" {
  let module_ = @types.Module::simple(
    [I32],
    [I32],
    [LocalGet(0), I32Const(1), I32Add],
    "increment",
  )
  inspect(
    render_function(module_, 0),
    content=(
      #|(func (;0;) (type 0) (param i32) (result i32)
      #|  local.get 0
      #|  i32.const 1
      #|  i32.add
      #|)
      #|
    ),
  )
}

///|
test "render module names as escaped UTF-8 strings" {
  let module_ = @types.Module::empty()
  module_.exports.push({ name: "x\"\\\né", desc: Func(0), })
  assert_true(render(module_).contains("(export \"x\\22\\5c\\0a\\c3\\a9\""))
}

///|
test "reject malformed instruction immediates" {
  let malformed_v128 = @types.Module::simple(
    [],
    [],
    [V128Const(Bytes::from_array([0]))],
    "malformed-v128",
  )
  let v128_error : WatPrintError? = try {
    let _ = render(malformed_v128)
    None
  } catch {
    error => Some(error)
  }
  match v128_error {
    Some(InvalidV128ConstantLength(1)) => ()
    _ => fail("expected malformed v128 constant to be rejected")
  }
  let malformed_shuffle = @types.Module::simple(
    [],
    [],
    [I8x16Shuffle(FixedArray::make(15, 0))],
    "malformed-shuffle",
  )
  let shuffle_error : WatPrintError? = try {
    let _ = render(malformed_shuffle)
    None
  } catch {
    error => Some(error)
  }
  match shuffle_error {
    Some(InvalidShuffleLaneCount(15)) => ()
    _ => fail("expected malformed shuffle to be rejected")
  }
  let malformed_atomic = @types.Module::simple(
    [],
    [],
    [Atomic(67, 0, 0, 0L)],
    "malformed-atomic",
  )
  let atomic_error : WatPrintError? = try {
    let _ = render(malformed_atomic)
    None
  } catch {
    error => Some(error)
  }
  match atomic_error {
    Some(InvalidAtomicSubopcode(67)) => ()
    _ => fail("expected malformed atomic subopcode to be rejected")
  }
}

///|
test "render custom memory page sizes" {
  let module_ = @types.Module::empty()
  module_.memories.push({
    limits: { min: 1L, max: Some(2L), },
    is_memory64: true,
    page_size_log2: 8,
  })
  assert_true(render(module_).contains("(memory (;0;) i64 1 2 (pagesize 256))"))
}
