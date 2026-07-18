///|
test "x64 code-object relocations retain cwasm patch coordinates" {
  let object = @code_object.build(
    X64,
    [
      b'\xE8', b'\x00', b'\x00', b'\x00', b'\x00', b'\x48', b'\xB8', b'\x00', b'\x00',
      b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\xC3',
    ],
    relocations=[
      @code_object.Relocation::new(
        1,
        X64PcRelative32,
        Code(@semantic_machv.CodeSymbol::new("wasm.func.3")),
      ),
      @code_object.Relocation::new(
        7,
        Absolute64,
        External(
          @semantic_machv.ExternalSymbol::new("wasmoon.runtime.cancel_poll"),
        ),
      ),
    ],
  )
  let (addresses, calls) = x64_cwasm_fixups(object)
  debug_inspect(
    (
      addresses.map(fixup => (fixup.offset, fixup.func_idx, fixup.reg)),
      calls.map(fixup => (fixup.offset, fixup.func_idx, fixup.veneer_offset)),
    ),
    content="([(5, -21014, 0)], [(0, 3, -1)])",
  )
}
