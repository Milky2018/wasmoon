///|
test "encode empty module" {
  debug_inspect(
    @encoder.encode(@types.Module::empty()),
    content="[0, 97, 115, 109, 1, 0, 0, 0]",
  )
}

///|
test "encode UTF-8 export name" {
  let module_ = @types.Module::empty()
  module_.exports.push({ name: "é😀", desc: Func(0), })
  debug_inspect(
    @encoder.encode(module_),
    content=(
      #|[
      #|  0,
      #|  97,
      #|  115,
      #|  109,
      #|  1,
      #|  0,
      #|  0,
      #|  0,
      #|  7,
      #|  10,
      #|  1,
      #|  6,
      #|  195,
      #|  169,
      #|  240,
      #|  159,
      #|  152,
      #|  128,
      #|  0,
      #|  0,
      #|]
    ),
  )
}

///|
test "SIMD operations round trip through the binary encoder" {
  let body : ReadOnlyArray[@types.Instruction] = [
    I32Const(1),
    I32x4Splat,
    I32Const(2),
    I32x4Splat,
    I32x4Add,
    I32x4ExtractLane(0),
  ]
  let module_ = @types.Module::simple([], [I32], body, "run")
  let bytes = Bytes::from_array(
    @encoder.encode(module_).map(byte => byte.to_byte()),
  )
  let decoded = @parser.parse_module(bytes)
  @validator.validate_module(decoded)
  assert_eq(decoded.codes[0].body, body)
}

///|
test "active funcref elements retain null reference expressions" {
  let module_ = @types.Module::empty()
  module_.tables.push({
    type_: {
      elem_type: FuncRef,
      limits: { min: 1L, max: None, },
      is_table64: false,
    },
    init: None,
  })
  module_.elems.push({
    mode: Active(0, [I32Const(0)]),
    type_: FuncRef,
    init: [[RefNull(NullFuncRef)]],
  })
  @validator.validate_module(module_)
  let bytes = Bytes::from_array(
    @encoder.encode(module_).map(byte => byte.to_byte()),
  )
  let decoded = @parser.parse_module(bytes)
  @validator.validate_module(decoded)
  assert_true(decoded.elems[0].init[0][0] is RefNull(_))
}

///|
test "memory operands retain the index and 64-bit offset" {
  let body : ReadOnlyArray[@types.Instruction] = [
    I64Const(0L),
    I32Load(1, 2, 0x1_0000_0000L),
    Drop,
    I64Const(0L),
    Atomic(0x10, 1, 2, 0x1_0000_0000L),
    Drop,
    I64Const(0L),
    V128Load(1, 4, 0x1_0000_0000L),
    Drop,
  ]
  let module_ = @types.Module::simple([], [], body, "run")
  module_.memories.push({
    limits: { min: 1L, max: None, },
    is_memory64: false,
    is_shared: false,
    page_size_log2: 16,
  })
  module_.memories.push({
    limits: { min: 1L, max: Some(1L), },
    is_memory64: true,
    is_shared: true,
    page_size_log2: 16,
  })
  @validator.validate_module(module_)
  let bytes = Bytes::from_array(
    @encoder.encode(module_).map(byte => byte.to_byte()),
  )
  let decoded = @parser.parse_module(bytes)
  @validator.validate_module(decoded)
  assert_eq(decoded.codes[0].body, body)
}
