///|
test "X64 linker applies relative and absolute relocations" {
  let call = @code_object.External(@semantic.ExternalSymbol::new("callee"))
  let data = @code_object.Data(@semantic.DataSymbol::new("fixture.data"))
  let object = @code_object.build(
    X64,
    [
      b'\xe8', b'\x00', b'\x00', b'\x00', b'\x00', b'\x48', b'\xb8', b'\x00', b'\x00',
      b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    ],
    relocations=[
      @code_object.Relocation::new(1, X64PcRelative32, call),
      @code_object.Relocation::new(7, Absolute64, data),
    ],
  )
  debug_inspect(
    prepare_x64_link(object).link(0x1000L, fn(target) {
      match target {
        External(_) => Some(0x2000L)
        Data(_) => Some(0x123456789ABCDEFL)
        Code(_) => None
      }
    }),
    content=(
      #|[
      #|  0xe8,
      #|  0xfb,
      #|  0x0f,
      #|  0x00,
      #|  0x00,
      #|  0x48,
      #|  0xb8,
      #|  0xef,
      #|  0xcd,
      #|  0xab,
      #|  0x89,
      #|  0x67,
      #|  0x45,
      #|  0x23,
      #|  0x01,
      #|  0xff,
      #|  0x25,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
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
}

///|
test "X64 linker routes out-of-range relative targets through a veneer" {
  let target = @code_object.External(@semantic.ExternalSymbol::new("far"))
  let object = @code_object.build(
    X64,
    [b'\xe8', b'\x00', b'\x00', b'\x00', b'\x00'],
    relocations=[@code_object.Relocation::new(1, X64PcRelative32, target)],
  )
  debug_inspect(
    prepare_x64_link(object).link(0L, fn(_) { Some(0x100000000L) }),
    content=(
      #|[
      #|  0xe8,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0xff,
      #|  0x25,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
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
test "X64 linker deduplicates call veneers by target and addend" {
  let target = @code_object.External(@semantic.ExternalSymbol::new("callee"))
  let object = @code_object.build(
    X64,
    [
      b'\xe8', b'\x00', b'\x00', b'\x00', b'\x00', b'\xe8', b'\x00', b'\x00', b'\x00',
      b'\x00',
    ],
    relocations=[
      @code_object.Relocation::new(1, X64PcRelative32, target),
      @code_object.Relocation::new(6, X64PcRelative32, target),
    ],
  )
  let plan = prepare_x64_link(object)
  debug_inspect(
    (plan.code(), plan.veneer_offsets()),
    content=(
      #|(
      #|  [
      #|    0xe8,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0xe8,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0xff,
      #|    0x25,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|  ],
      #|  [10, 10],
      #|)
    ),
  )
}
