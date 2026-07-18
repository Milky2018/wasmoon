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
      #|]
    ),
  )
}

///|
test "X64 linker rejects out-of-range relative targets" {
  let target = @code_object.External(@semantic.ExternalSymbol::new("far"))
  let object = @code_object.build(
    X64,
    [b'\xe8', b'\x00', b'\x00', b'\x00', b'\x00'],
    relocations=[@code_object.Relocation::new(1, X64PcRelative32, target)],
  )
  try prepare_x64_link(object).link(0L, fn(_) { Some(0x100000000L) }) catch {
    error => debug_inspect(error, content="RelocationOutOfRange(index=0)")
  } noraise {
    _ => fail("expected out-of-range relocation to be rejected")
  }
}
