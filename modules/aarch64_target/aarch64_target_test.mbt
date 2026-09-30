///|
test "AArch64 rejects an internal ABI that reuses the context register" {
  try
    @aarch64_target.InternalAbi::new(0, 8, [0, 1, 2], [0, 1], [0, 1], [0, 1])
    |> ignore
  catch {
    error => inspect(error, content="ContextRegisterReused(index=0)")
  } noraise {
    _ => fail("expected the internal ABI contract to be rejected")
  }
}

///|
test "AArch64 reserves the internal result-area register" {
  try
    @aarch64_target.InternalAbi::new(0, 1, [1, 2], [0, 1], [0, 1], [0, 1])
    |> ignore
  catch {
    error => inspect(error, content="ResultAreaRegisterReused(index=1)")
  } noraise {
    _ => fail("expected the result-area ABI register to be reserved")
  }
}

///|
test "AArch64 trusted direct selection skips redundant VCode validation" {
  let abi = @aarch64_target.InternalAbi::new(
    0,
    8,
    [1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let saw_validation = Ref(false)
  let session = @aarch64_target.DirectLoweringSession::new(
    "trusted",
    Internal,
    [Ptr64],
    [],
    @aarch64_target.LoweringContext::new(abi),
    on_event=fn(event) {
      if event is TargetValidationStarted {
        saw_validation.val = true
      }
    },
  )
  let sink = session.sink()
  inspect(sink.folds_unsigned_index_into_memory(), content="true")
  let builder = @lowering.DirectBuilder::new([Ptr64], sink)
  builder.return_([])
  builder.finish()
  session.finish_selected(verify_selected=false) |> ignore
  inspect(saw_validation.val, content="false")
}

///|
test "AArch64 direct selection erases raw-word pointer bitcasts" {
  let abi = @aarch64_target.InternalAbi::new(
    0,
    8,
    [1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let session = @aarch64_target.DirectLoweringSession::new(
    "raw_word_alias",
    Internal,
    [Ptr64, I64],
    [I64],
    @aarch64_target.LoweringContext::new(abi),
  )
  let builder = @lowering.DirectBuilder::new([Ptr64, I64], session.sink())
  let pointer = builder.emit_with_metadata(
      Convert(Bitcast(I64, Ptr64)),
      [builder.parameters()[1]],
      [Ptr64],
      @lowering.InstructionMetadata::empty(),
    )[0]
  let offset = builder.emit_with_metadata(
      I64Const(8UL),
      [],
      [I64],
      @lowering.InstructionMetadata::empty(),
    )[0]
  let adjusted = builder.emit_with_metadata(
      PointerOffset,
      [pointer, offset],
      [Ptr64],
      @lowering.InstructionMetadata::empty(),
    )[0]
  let bits = builder.emit_with_metadata(
      Convert(Bitcast(Ptr64, I64)),
      [adjusted],
      [I64],
      @lowering.InstructionMetadata::empty(),
    )[0]
  builder.return_([bits])
  builder.finish()
  session.finish_selected() |> ignore
}

///|
test "AArch64 direct arithmetic selects modular negative immediates" {
  let abi = @aarch64_target.InternalAbi::new(
    0,
    8,
    [1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let cases : Array[(@native.ValueType, @lowering.IntBinaryOp, UInt64, UInt?)] = [
    (I32, Add, 0xffffffc0UL, Some(0x51010020U)),
    (I32, Sub, 0xffffffc0UL, Some(0x11010020U)),
    (I64, Add, 0xffffffffffffffc0UL, Some(0xd1010020U)),
    (I64, Sub, 0xffffffffffffffc0UL, Some(0x91010020U)),
    (I32, Add, 0xfffff000UL, Some(0x51400420U)),
    (I64, Sub, 0xfffffffffffff000UL, Some(0x91400420U)),
    (I32, Add, 0xff001000UL, Some(0x517ffc20U)),
    (I64, Sub, 0xffffffffff001000UL, Some(0x917ffc20U)),
    (I32, Add, 64UL, Some(0x11010020U)),
    (I64, Sub, 64UL, Some(0xd1010020U)),
    (I32, Add, 0xffffefffUL, None),
    (I64, Sub, 0xffffffffffffefffUL, None),
    (I32, Add, 0x80000000UL, None),
    (I64, Sub, 0x8000000000000000UL, None),
  ]
  for (ty, operation, bits, expected) in cases {
    let session = @aarch64_target.DirectLoweringSession::new(
      "negative_immediate",
      Internal,
      [Ptr64, ty],
      [ty],
      @aarch64_target.LoweringContext::new(abi),
    )
    let builder = @lowering.DirectBuilder::new([Ptr64, ty], session.sink())
    let result = builder.emit_with_metadata(
        IntBinaryImmediate(operation, bits),
        [builder.parameters()[1]],
        [ty],
        @lowering.InstructionMetadata::empty(),
      )[0]
    builder.return_([result])
    builder.finish()
    let diagnostics = @aarch64_target.diagnose_selected(
      session.finish_selected(),
    )
    match expected {
      Some(word) => {
        let code = diagnostics.object.code()
        inspect(code.length(), content="8")
        let actual = code[0].to_uint() |
          (code[1].to_uint() << 8) |
          (code[2].to_uint() << 16) |
          (code[3].to_uint() << 24)
        inspect(actual == word, content="true")
      }
      None =>
        inspect(
          diagnostics.target_vcode.contains("LoadConstant"),
          content="true",
        )
    }
  }
}

///|
test "AArch64 value comparisons use immediate encoding only when eligible" {
  let abi = @aarch64_target.InternalAbi::new(
    0,
    8,
    [1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )

  let cases : Array[(@native.ValueType, UInt64, UInt?)] = [
    (I32, 42UL, Some(0x7100a83fU)),
    (I64, 42UL, Some(0xf100a83fU)),
    (I64, 4096UL, Some(0xf140043fU)),
    (I32, 4097UL, None),
    (I64, 0xffffffffffffffffUL, None),
  ]
  for (ty, bits, expected) in cases {
    let session = @aarch64_target.DirectLoweringSession::new(
      "compare_immediate",
      Internal,
      [Ptr64, ty],
      [I32],
      @aarch64_target.LoweringContext::new(abi),
    )
    let sink = session.sink()
    inspect(
      sink.supports_int_compare_immediate(ty, bits) == (expected is Some(_)),
      content="true",
    )
    let builder = @lowering.DirectBuilder::new([Ptr64, ty], sink)
    let result = builder.emit_with_metadata(
        IntCompareImmediate(Equal, bits),
        [builder.parameters()[1]],
        [I32],
        @lowering.InstructionMetadata::empty(),
      )[0]
    builder.return_([result])
    builder.finish()
    let diagnostics = @aarch64_target.diagnose_selected(
      session.finish_selected(),
    )
    match expected {
      Some(word) => {
        let code = diagnostics.object.code()
        inspect(code.length(), content="12")
        let actual = code[0].to_uint() |
          (code[1].to_uint() << 8) |
          (code[2].to_uint() << 16) |
          (code[3].to_uint() << 24)
        inspect(actual == word, content="true")
      }
      None =>
        inspect(
          diagnostics.target_vcode.contains("LoadConstant"),
          content="true",
        )
    }
  }
}
