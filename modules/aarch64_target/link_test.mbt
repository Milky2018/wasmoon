///|
test "AArch64 link plans share veneers and preserve branch kinds" {
  let target = @code_object.External(@native.ExternalSymbol::new("callee"))
  let object = @code_object.build(
    AArch64,
    [b'\x00', b'\x00', b'\x00', b'\x94', b'\x00', b'\x00', b'\x00', b'\x14'],
    relocations=[
      @code_object.Relocation::new(0, AArch64Call26, target),
      @code_object.Relocation::new(4, AArch64Jump26, target),
    ],
  )
  let plan = prepare_aarch64_link(object)
  debug_inspect(
    plan,
    content=(
      #|{
      #|  code: [
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x94,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0x50,
      #|    0x00,
      #|    0x00,
      #|    0x58,
      #|    0x00,
      #|    0x02,
      #|    0x1f,
      #|    0xd6,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|  ],
      #|  relocations: [
      #|    {
      #|      offset: 0,
      #|      kind: AArch64Call26,
      #|      target: External({ name: "callee" }),
      #|      addend: 0,
      #|    },
      #|    {
      #|      offset: 4,
      #|      kind: AArch64Jump26,
      #|      target: External({ name: "callee" }),
      #|      addend: 0,
      #|    },
      #|  ],
      #|  veneer_offsets: [8, 8],
      #|}
    ),
  )
  debug_inspect(
    plan.link(0x1000L, fn(_) { Some(0x2000L) }),
    content=(
      #|[
      #|  0x00,
      #|  0x04,
      #|  0x00,
      #|  0x94,
      #|  0xff,
      #|  0x03,
      #|  0x00,
      #|  0x14,
      #|  0x50,
      #|  0x00,
      #|  0x00,
      #|  0x58,
      #|  0x00,
      #|  0x02,
      #|  0x1f,
      #|  0xd6,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|]
    ),
  )
  debug_inspect(
    plan.link(0x1000L, fn(_) { Some(0x100000000L) }),
    content=(
      #|[
      #|  0x02,
      #|  0x00,
      #|  0x00,
      #|  0x94,
      #|  0x01,
      #|  0x00,
      #|  0x00,
      #|  0x14,
      #|  0x50,
      #|  0x00,
      #|  0x00,
      #|  0x58,
      #|  0x00,
      #|  0x02,
      #|  0x1f,
      #|  0xd6,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x01,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|]
    ),
  )
}

///|
test "AArch64 linker applies page and absolute relocations" {
  let target = @code_object.Data(@native.DataSymbol::new("fixture.data"))
  let object = @code_object.build(
    AArch64,
    [
      b'\x00', b'\x00', b'\x00', b'\x90', b'\x00', b'\x00', b'\x00', b'\x91', b'\x00',
      b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    ],
    relocations=[
      @code_object.Relocation::new(0, AArch64Page21, target),
      @code_object.Relocation::new(4, AArch64PageOffset12, target),
      @code_object.Relocation::new(8, Absolute64, target),
    ],
  )
  debug_inspect(
    prepare_aarch64_link(object).link(0x1000L, fn(_) { Some(0x2345L) }),
    content=(
      #|[
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0xb0,
      #|  0x00,
      #|  0x14,
      #|  0x0d,
      #|  0x91,
      #|  0x45,
      #|  0x23,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|]
    ),
  )
}
