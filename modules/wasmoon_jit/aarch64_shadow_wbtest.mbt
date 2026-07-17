///|
test "AArch64 shadow compiles semantic MachV through the final target seams" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "shadow_integer_add",
    Internal,
    [Ptr64, I64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let result = builder.emit(IntBinary(Add), [parameters[1], parameters[2]], [
      I64,
    ])[0]
  builder.return_([result])
  debug_inspect(
    build_aarch64_shadow(builder.finish()),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xe3,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0x02,
      #|    0x00,
      #|    0x01,
      #|    0x8b,
      #|    0xe0,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 shadow binds product environment fields explicitly" {
  let field = @semantic_machv.EnvironmentField::new(
    "wasmoon.test.pointer",
    Ptr64,
  )
  let builder = @semantic_machv.FunctionBuilder::new(
    "shadow_environment_field",
    Internal,
    [Ptr64],
    [Ptr64],
  )
  let result = builder.emit(
      EnvironmentField(field),
      [builder.parameters()[0]],
      [Ptr64],
    )[0]
  builder.return_([result])
  debug_inspect(
    build_aarch64_shadow(builder.finish(), environment_field_path=fn(
      candidate,
    ) {
      if candidate == field {
        Some([16])
      } else {
        None
      }
    }),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xe1,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0x20,
      #|    0x08,
      #|    0x40,
      #|    0xf9,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}
