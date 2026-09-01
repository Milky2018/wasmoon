///|
test "verified code object snapshots complete typed metadata" {
  let object = build(
    AArch64,
    [b'\x00', b'\x00', b'\x00', b'\x94'],
    relocations=[
      Relocation::new(
        0,
        AArch64Call26,
        External(@native.ExternalSymbol::new("runtime.poll")),
      ),
    ],
    sources=[
      SourceSite::new(0, @native.SourceLocation::new("fixture.wat", 8, 3)),
    ],
    traps=[TrapSite::new(0, MemoryOutOfBounds)],
    safepoints=[
      SafepointSite::new(
        0,
        Gc,
        [Register(Int, 0), Stack(offset=16, ty=GcRef64)],
        stack_map=@native.StackMapMetadata::new(0, argument_root_count=1),
      ),
    ],
    unwind=[UnwindDirective::new(4, StackAlloc(size=16))],
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
      #|      stack_map: Some({ id: 0, argument_root_count: 1 }),
      #|    },
      #|  ],
      #|  unwind: [{ offset: 4, operation: StackAlloc(size=16) }],
      #|}
    ),
  )
}

///|
test "code object rejects duplicate or non-dense stack-map ids" {
  try
    build(
      AArch64,
      [b'\x00', b'\x00', b'\x00', b'\x94', b'\x00', b'\x00', b'\x00', b'\x94'],
      safepoints=[
        SafepointSite::new(
          0,
          Gc,
          [],
          stack_map=@native.StackMapMetadata::new(0, argument_root_count=0),
        ),
        SafepointSite::new(
          4,
          Gc,
          [],
          stack_map=@native.StackMapMetadata::new(0, argument_root_count=0),
        ),
      ],
    )
    |> ignore
  catch {
    error => inspect(error, content="InvalidStackMap(safepoint=1)")
  } noraise {
    _ => fail("expected duplicate stack-map ids to fail")
  }
}

///|
test "code object rejects target-mismatched relocations before escape" {
  try
    build(AArch64, [b'\x1f', b'\x20', b'\x03', b'\xd5'], relocations=[
      Relocation::new(
        0,
        X64PcRelative32,
        Code(@native.CodeSymbol::new("callee")),
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
        External(@native.ExternalSymbol::new("runtime.poll")),
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

///|
test "code object rejects malformed unwind directives" {
  try
    build(AArch64, [b'\x1f', b'\x20', b'\x03', b'\xd5'], unwind=[
      UnwindDirective::new(4, StackAlloc(size=3)),
    ])
    |> ignore
  catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidUnwindDirective(
          #|  index=0,
          #|  message="stack allocation violates the target stack alignment",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected malformed unwind directives to fail verification")
  }
}

///|
test "code object rejects non-monotonic unwind offsets" {
  try
    build(
      AArch64,
      [b'\x1f', b'\x20', b'\x03', b'\xd5', b'\x1f', b'\x20', b'\x03', b'\xd5'],
      unwind=[
        UnwindDirective::new(8, StackAlloc(size=16)),
        UnwindDirective::new(4, SaveRegister(Int, 19, cfa_offset=-8)),
      ],
    )
    |> ignore
  catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidUnwindDirective(
          #|  index=1,
          #|  message="offset is out of range, misaligned, or not monotonic",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected non-monotonic unwind offsets to fail verification")
  }
}

///|
test "code object rejects invalid unwind register locations" {
  try
    build(X64, [b'\x50', b'\xc3'], unwind=[
      UnwindDirective::new(1, StackAlloc(size=8)),
      UnwindDirective::new(1, SaveRegister(Int, 16, cfa_offset=-16)),
    ])
    |> ignore
  catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidUnwindDirective(
          #|  index=1,
          #|  message="saved register or CFA-relative location is invalid",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected invalid unwind register locations to fail verification")
  }
}

///|
test "code object rejects an inconsistent frame pointer" {
  try
    build(X64, [b'\x50', b'\x48', b'\x89', b'\xe5', b'\xc3'], unwind=[
      UnwindDirective::new(1, StackAlloc(size=8)),
      UnwindDirective::new(4, SetFramePointer(Int, 5, cfa_offset=8)),
    ])
    |> ignore
  catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidUnwindDirective(
          #|  index=1,
          #|  message="frame pointer register or CFA offset is invalid",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected an inconsistent frame pointer to fail verification")
  }
}
