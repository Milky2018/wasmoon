///|
test "verified code object snapshots complete typed metadata" {
  let object = build(
    AArch64,
    [b'\x00', b'\x00', b'\x00', b'\x94'],
    relocations=[
      Relocation::new(
        0,
        AArch64Call26,
        External(@semantic.ExternalSymbol::new("runtime.poll")),
      ),
    ],
    sources=[
      SourceSite::new(0, @semantic.SourceLocation::new("fixture.wat", 8, 3)),
    ],
    traps=[TrapSite::new(0, MemoryOutOfBounds)],
    safepoints=[
      SafepointSite::new(0, Gc, [Register(Int, 0), Stack(offset=16, ty=GcRef64)]),
    ],
  )
  debug_inspect(
    object,
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [0x00, 0x00, 0x00, 0x94],
      #|  relocations: [
      #|    {
      #|      offset: 0,
      #|      kind: AArch64Call26,
      #|      target: External({ name: "runtime.poll" }),
      #|      addend: 0,
      #|    },
      #|  ],
      #|  sources: [{ offset: 0, source: { file: "fixture.wat", line: 8, column: 3 } }],
      #|  traps: [{ offset: 0, reason: MemoryOutOfBounds, source: None }],
      #|  safepoints: [
      #|    {
      #|      offset: 0,
      #|      kind: Gc,
      #|      roots: [Register(Int, 0), Stack(offset=16, ty=GcRef64)],
      #|      source: None,
      #|    },
      #|  ],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "code object rejects target-mismatched relocations before escape" {
  try
    build(AArch64, [b'\x1f', b'\x20', b'\x03', b'\xd5'], relocations=[
      Relocation::new(
        0,
        X64PcRelative32,
        Code(@semantic.CodeSymbol::new("callee")),
      ),
    ])
    |> ignore
  catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidRelocation(
          #|  index=0,
          #|  message="kind, alignment, or range does not match the code object",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected a target-mismatched relocation to fail")
  }
}

///|
test "code object rejects a call relocation on a non-call instruction" {
  try
    build(AArch64, [b'\x1f', b'\x20', b'\x03', b'\xd5'], relocations=[
      Relocation::new(
        0,
        AArch64Call26,
        External(@semantic.ExternalSymbol::new("runtime.poll")),
      ),
    ])
    |> ignore
  catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidRelocation(
          #|  index=0,
          #|  message="kind, alignment, or range does not match the code object",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected a relocation/encoding mismatch to fail")
  }
}
