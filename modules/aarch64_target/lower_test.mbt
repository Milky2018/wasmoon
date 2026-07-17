///|
test "AArch64 lowering selects scalar SSA and preserves source metadata" {
  let builder = @semantic.FunctionBuilder::new(
    "selected_add",
    Platform,
    [I64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let sum = builder.emit_with_metadata(
      IntBinary(Add),
      parameters,
      [I64],
      @semantic.InstructionMetadata::new(
        Some(@semantic.SourceLocation::new("selected.wat", 3, 9)),
        [],
      ),
    )[0]
  builder.return_([sum])
  let selected = lower(builder.finish(), test_lowering_context())
  inspect(
    selected.summary(),
    content=(
      #|vcode selected_add(v0:i64, v1:i64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(I64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v2:any@late]
      #|  i1 IncomingReg(I64, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v3:any@late]
      #|  i2 IntBinary(W64, Add) uses=[v2:any@early, v3:any@early] defs=[v4:any@late] source={ file: "selected.wat", line: 3, column: 9 }
      #|  i3 OutgoingReg(I64, p0:int) uses=[v4:any@early]
      #|  i4 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering rejects unsupported valid operations structurally" {
  let builder = @semantic.FunctionBuilder::new(
    "unsupported_float",
    Platform,
    [F32, F32],
    [F32],
  )
  let value = builder.emit(FloatBinary(Min), builder.parameters(), [F32])[0]
  builder.return_([value])
  try lower(builder.finish(), test_lowering_context()) |> ignore catch {
    error =>
      inspect(
        error,
        content=(
          #|UnsupportedOperation(
          #|  block_index=0,
          #|  instruction_index=0,
          #|  operation=FloatBinary(Min),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected unsupported float selection to fail")
  }
}

///|
test "AArch64 lowering inserts explicit traps before signed division" {
  let builder = @semantic.FunctionBuilder::new(
    "checked_divide",
    Platform,
    [I64, I64],
    [I64],
  )
  let value = builder.emit(IntBinary(SignedDiv), builder.parameters(), [I64])[0]
  builder.return_([value])
  inspect(
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode checked_divide(v0:i64, v1:i64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(I64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v2:any@late]
      #|  i1 IncomingReg(I64, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v3:any@late]
      #|  i2 TrapIfZero(W64) uses=[v3:any@early] trap=IntegerDivisionByZero
      #|  i3 TrapIfSignedDivOverflow(W64) uses=[v2:any@early, v3:any@early] trap=IntegerOverflow
      #|  i4 IntBinary(W64, Sdiv) uses=[v2:any@early, v3:any@early] defs=[v4:any@late]
      #|  i5 OutgoingReg(I64, p0:int) uses=[v4:any@early]
      #|  i6 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering selects a direct platform call with explicit ABI facts" {
  let builder = @semantic.FunctionBuilder::new(
    "direct_platform_call",
    Platform,
    [I64, F64],
    [I64],
  )
  let call = @semantic.SemanticCall::new(
    External(@semantic.ExternalSymbol::new("runtime.helper")),
    @semantic.Signature::new([I64, F64], [I64]),
    Platform,
    @semantic.CallBehavior::new(ReadWrite, true, true, true, true),
  )
  let result = builder.emit_with_metadata(
      Call(call),
      builder.parameters(),
      [I64],
      @semantic.InstructionMetadata::new(
        Some(@semantic.SourceLocation::new("call.wat", 7, 11)),
        [],
      ),
    )[0]
  builder.return_([result])
  inspect(
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode direct_platform_call(v0:i64, v1:f64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(I64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v2:any@late]
      #|  i1 IncomingReg(F64, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v3:any@late]
      #|  i2 PlatformCall(
      #|  { name: "runtime.helper" },
      #|  { params: [I64, F64], results: [I64] },
      #|) uses=[v2:any@early, v3:any@early] clobbers=[p0:int, p1:int, p2:int, p3:int, p4:int, p5:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p12:int, p13:int, p14:int, p15:int, p16:int, p17:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec, p16:fpvec, p17:fpvec, p18:fpvec, p19:fpvec, p20:fpvec, p21:fpvec, p22:fpvec, p23:fpvec, p24:fpvec, p25:fpvec, p26:fpvec, p27:fpvec, p28:fpvec, p29:fpvec, p30:fpvec, p31:fpvec] source={ file: "call.wat", line: 7, column: 11 } safepoint=GcAndCancellation
      #|  i3 IncomingCallResult(I64, p0:int) defs=[v4:any@late]
      #|  i4 OutgoingReg(I64, p0:int) uses=[v4:any@early]
      #|  i5 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering derives internal entry and direct-call layouts" {
  let builder = @semantic.FunctionBuilder::new(
    "direct_internal_call",
    Internal,
    [Ptr64, I64, F64],
    [I64],
  )
  let call = @semantic.SemanticCall::new(
    Internal(@semantic.CodeSymbol::new("wasm.func.7")),
    @semantic.Signature::new([Ptr64, I64, F64], [I64]),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, true, true),
  )
  let result = builder.emit(Call(call), builder.parameters(), [I64])[0]
  builder.return_([result])
  inspect(
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode direct_internal_call(v0:ptr64, v1:i64, v2:f64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v3:any@late]
      #|  i1 IncomingReg(I64, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v4:any@late]
      #|  i2 IncomingReg(F64, p0:fpvec) uses=[v2:fixed(p0:fpvec)@early] defs=[v5:any@late]
      #|  i3 InternalCall(
      #|  { name: "wasm.func.7" },
      #|  { params: [Ptr64, I64, F64], results: [I64] },
      #|  {
      #|    arguments: [CallRegister(p0:int), CallRegister(p1:int), CallRegister(p0:fpvec)],
      #|    results: [p0:int],
      #|    stack_size: 0,
      #|  },
      #|) uses=[v3:any@early, v4:any@early, v5:any@early] clobbers=[p0:int, p1:int, p2:int, p3:int, p4:int, p5:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p12:int, p13:int, p14:int, p15:int, p16:int, p17:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec, p16:fpvec, p17:fpvec, p18:fpvec, p19:fpvec, p20:fpvec, p21:fpvec, p22:fpvec, p23:fpvec, p24:fpvec, p25:fpvec, p26:fpvec, p27:fpvec, p28:fpvec, p29:fpvec, p30:fpvec, p31:fpvec] safepoint=GcAndCancellation
      #|  i4 IncomingCallResult(I64, p0:int) defs=[v6:any@late]
      #|  i5 OutgoingReg(I64, p0:int) uses=[v6:any@early]
      #|  i6 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering keeps the indirect callee outside the logical signature" {
  let builder = @semantic.FunctionBuilder::new(
    "indirect_internal_call",
    Internal,
    [Ptr64, Ptr64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let call = @semantic.SemanticCall::new(
    Indirect,
    @semantic.Signature::new([Ptr64, I64], [I64]),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  let result = builder.emit(
      Call(call),
      [parameters[1], parameters[0], parameters[2]],
      [I64],
    )[0]
  builder.return_([result])
  inspect(
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode indirect_internal_call(v0:ptr64, v1:ptr64, v2:i64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v3:any@late]
      #|  i1 IncomingReg(Ptr64, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v4:any@late]
      #|  i2 IncomingReg(I64, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v5:any@late]
      #|  i3 InternalCallIndirect(
      #|  { params: [Ptr64, I64], results: [I64] },
      #|  {
      #|    arguments: [CallRegister(p0:int), CallRegister(p1:int)],
      #|    results: [p0:int],
      #|    stack_size: 0,
      #|  },
      #|) uses=[v4:any@early, v3:any@early, v5:any@early] clobbers=[p0:int, p1:int, p2:int, p3:int, p4:int, p5:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p12:int, p13:int, p14:int, p15:int, p16:int, p17:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec, p16:fpvec, p17:fpvec, p18:fpvec, p19:fpvec, p20:fpvec, p21:fpvec, p22:fpvec, p23:fpvec, p24:fpvec, p25:fpvec, p26:fpvec, p27:fpvec, p28:fpvec, p29:fpvec, p30:fpvec, p31:fpvec]
      #|  i4 IncomingCallResult(I64, p0:int) defs=[v6:any@late]
      #|  i5 OutgoingReg(I64, p0:int) uses=[v6:any@early]
      #|  i6 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering selects a compatible true internal tail call" {
  let builder = @semantic.FunctionBuilder::new(
    "direct_tail_call",
    Internal,
    [Ptr64, I64],
    [I64],
  )
  let call = @semantic.SemanticCall::new(
    Internal(@semantic.CodeSymbol::new("wasm.func.9")),
    @semantic.Signature::new([Ptr64, I64], [I64]),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.tail_call(call, builder.parameters())
  inspect(
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode direct_tail_call(v0:ptr64, v1:i64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v2:any@late]
      #|  i1 IncomingReg(I64, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v3:any@late]
      #|  i2 TailCallDirect(
      #|  { name: "wasm.func.9" },
      #|  { params: [Ptr64, I64], results: [I64] },
      #|  {
      #|    arguments: [CallRegister(p0:int), CallRegister(p1:int)],
      #|    results: [p0:int],
      #|    stack_size: 0,
      #|  },
      #|) uses=[v2:any@early, v3:any@early] clobbers=[p0:int, p1:int, p2:int, p3:int, p4:int, p5:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p12:int, p13:int, p14:int, p15:int, p16:int, p17:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec, p16:fpvec, p17:fpvec, p18:fpvec, p19:fpvec, p20:fpvec, p21:fpvec, p22:fpvec, p23:fpvec, p24:fpvec, p25:fpvec, p26:fpvec, p27:fpvec, p28:fpvec, p29:fpvec, p30:fpvec, p31:fpvec]
      #|
    ),
  )
}

///|
test "AArch64 rejects tail stack arguments that cannot replace the incoming area" {
  let builder = @semantic.FunctionBuilder::new(
    "oversized_tail_call",
    Internal,
    [Ptr64],
    [],
  )
  let operands = [builder.parameters()[0]]
  for index in 0..<8 {
    operands.push(builder.emit(I64Const(index.to_uint64()), [], [I64])[0])
  }
  let call = @semantic.SemanticCall::new(
    Internal(@semantic.CodeSymbol::new("wasm.func.10")),
    @semantic.Signature::new([Ptr64, I64, I64, I64, I64, I64, I64, I64, I64], []),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.tail_call(call, operands)
  try lower(builder.finish(), test_lowering_context()) |> ignore catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidTarget(
          #|  cause=InvalidInstruction(
          #|    instruction=i9,
          #|    message="tail-call plan is not compatible with the current function",
          #|  ),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected an oversized true tail call to be rejected")
  }
}

///|
test "AArch64 lowering selects typed scalar memory operations and traps" {
  let builder = @semantic.FunctionBuilder::new(
    "scalar_memory",
    Internal,
    [Ptr64, I32, I64, F32, F64],
    [I64],
  )
  let parameters = builder.parameters()
  builder.emit_with_metadata(
    Load(
      @semantic.LoadSpec::new(
        W8,
        Signed,
        I32,
        3UL,
        Little,
        Some(MemoryOutOfBounds),
      ),
    ),
    [parameters[0]],
    [I32],
    @semantic.InstructionMetadata::new(
      Some(@semantic.SourceLocation::new("memory.wat", 4, 7)),
      [],
    ),
  )
  |> ignore
  let loaded = builder.emit(
      Load(
        @semantic.LoadSpec::new(
          W32,
          Unsigned,
          I64,
          12UL,
          Little,
          Some(MemoryOutOfBounds),
        ),
      ),
      [parameters[0]],
      [I64],
    )[0]
  builder.emit(
    Load(@semantic.LoadSpec::new(W64, None, Ptr64, 16UL, Little, None)),
    [parameters[0]],
    [Ptr64],
  )
  |> ignore
  builder.emit(
    Load(@semantic.LoadSpec::new(W32, None, F32, 20UL, Little, None)),
    [parameters[0]],
    [F32],
  )
  |> ignore
  builder.emit(
    Load(@semantic.LoadSpec::new(W64, None, F64, 24UL, Little, None)),
    [parameters[0]],
    [F64],
  )
  |> ignore
  builder.emit(
    Store(@semantic.StoreSpec::new(W16, I32, 6UL, Little, None)),
    [parameters[0], parameters[1]],
    [],
  )
  |> ignore
  builder.emit(
    Store(@semantic.StoreSpec::new(W64, I64, 32UL, Little, None)),
    [parameters[0], parameters[2]],
    [],
  )
  |> ignore
  builder.emit(
    Store(@semantic.StoreSpec::new(W32, F32, 40UL, Little, None)),
    [parameters[0], parameters[3]],
    [],
  )
  |> ignore
  builder.emit(
    Store(@semantic.StoreSpec::new(W64, F64, 48UL, Little, None)),
    [parameters[0], parameters[4]],
    [],
  )
  |> ignore
  builder.return_([loaded])
  inspect(
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_memory(v0:ptr64, v1:i32, v2:i64, v3:f32, v4:f64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v5:any@late]
      #|  i1 IncomingReg(I32, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v6:any@late]
      #|  i2 IncomingReg(I64, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v7:any@late]
      #|  i3 IncomingReg(F32, p0:fpvec) uses=[v3:fixed(p0:fpvec)@early] defs=[v8:any@late]
      #|  i4 IncomingReg(F64, p1:fpvec) uses=[v4:fixed(p1:fpvec)@early] defs=[v9:any@late]
      #|  i5 ScalarLoad(W8, Signed, I32, 3) uses=[v5:any@early] defs=[v10:any@late] source={ file: "memory.wat", line: 4, column: 7 } trap=MemoryOutOfBounds
      #|  i6 ScalarLoad(W32, Unsigned, I64, 12) uses=[v5:any@early] defs=[v11:any@late] trap=MemoryOutOfBounds
      #|  i7 ScalarLoad(W64, None, Ptr64, 16) uses=[v5:any@early] defs=[v12:any@late]
      #|  i8 ScalarLoad(W32, None, F32, 20) uses=[v5:any@early] defs=[v13:any@late]
      #|  i9 ScalarLoad(W64, None, F64, 24) uses=[v5:any@early] defs=[v14:any@late]
      #|  i10 ScalarStore(W16, I32, 6) uses=[v5:any@early, v6:any@early]
      #|  i11 ScalarStore(W64, I64, 32) uses=[v5:any@early, v7:any@early]
      #|  i12 ScalarStore(W32, F32, 40) uses=[v5:any@early, v8:any@early]
      #|  i13 ScalarStore(W64, F64, 48) uses=[v5:any@early, v9:any@early]
      #|  i14 OutgoingReg(I64, p0:int) uses=[v11:any@early]
      #|  i15 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering rejects non-native scalar memory endianness" {
  let builder = @semantic.FunctionBuilder::new(
    "big_endian_load",
    Internal,
    [Ptr64],
    [I32],
  )
  let loaded = builder.emit(
      Load(
        @semantic.LoadSpec::new(
          W32,
          None,
          I32,
          0UL,
          Big,
          Some(MemoryOutOfBounds),
        ),
      ),
      builder.parameters(),
      [I32],
    )[0]
  builder.return_([loaded])
  try lower(builder.finish(), test_lowering_context()) |> ignore catch {
    error =>
      inspect(
        error,
        content=(
          #|UnsupportedOperation(
          #|  block_index=0,
          #|  instruction_index=0,
          #|  operation=Load(
          #|    {
          #|      width: W32,
          #|      extension: None,
          #|      result_type: I32,
          #|      offset: 0,
          #|      endianness: Big,
          #|      trap: Some(MemoryOutOfBounds),
          #|    },
          #|  ),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected big-endian scalar memory lowering to fail")
  }
}

///|
test "AArch64 lowering selects non-trapping scalar floating-point operations" {
  let builder = @semantic.FunctionBuilder::new(
    "scalar_float",
    Internal,
    [Ptr64, F32, F32, F64, F64],
    [F32, F64, I32, I32],
  )
  let parameters = builder.parameters()
  let one = builder.emit(F32Const(0x3F800000U), [], [F32])[0]
  let negated = builder.emit(FloatUnary(Negate), [parameters[1]], [F32])[0]
  let sum = builder.emit(FloatBinary(Add), [negated, one], [F32])[0]
  let two = builder.emit(F64Const(0x4000000000000000UL), [], [F64])[0]
  let rooted = builder.emit(FloatUnary(SquareRoot), [parameters[3]], [F64])[0]
  let quotient = builder.emit(FloatBinary(Div), [rooted, two], [F64])[0]
  let less = builder.emit(
      FloatCompare(LessThan),
      [parameters[1], parameters[2]],
      [I32],
    )[0]
  let not_equal = builder.emit(
      FloatCompare(NotEqual),
      [parameters[3], parameters[4]],
      [I32],
    )[0]
  builder.return_([sum, quotient, less, not_equal])
  inspect(
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_float(v0:ptr64, v1:f32, v2:f32, v3:f64, v4:f64) -> (f32, f64, i32, i32)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v5:any@late]
      #|  i1 IncomingReg(F32, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v6:any@late]
      #|  i2 IncomingReg(F32, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v7:any@late]
      #|  i3 IncomingReg(F64, p2:fpvec) uses=[v3:fixed(p2:fpvec)@early] defs=[v8:any@late]
      #|  i4 IncomingReg(F64, p3:fpvec) uses=[v4:fixed(p3:fpvec)@early] defs=[v9:any@late]
      #|  i5 LoadFloatConstant(F32, 1065353216) defs=[v10:any@late]
      #|  i6 FloatUnary(F32, Negate) uses=[v6:any@early] defs=[v11:any@late]
      #|  i7 FloatBinary(F32, Add) uses=[v11:any@early, v10:any@early] defs=[v12:any@late]
      #|  i8 LoadFloatConstant(F64, 4611686018427387904) defs=[v13:any@late]
      #|  i9 FloatUnary(F64, SquareRoot) uses=[v8:any@early] defs=[v14:any@late]
      #|  i10 FloatBinary(F64, Div) uses=[v14:any@early, v13:any@early] defs=[v15:any@late]
      #|  i11 FloatCompareSet(F32, LessThan) uses=[v6:any@early, v7:any@early] defs=[v16:any@late]
      #|  i12 FloatCompareSet(F64, NotEqual) uses=[v8:any@early, v9:any@early] defs=[v17:any@late]
      #|  i13 OutgoingReg(F32, p0:fpvec) uses=[v12:any@early]
      #|  i14 OutgoingReg(F64, p1:fpvec) uses=[v15:any@early]
      #|  i15 OutgoingReg(I32, p0:int) uses=[v16:any@early]
      #|  i16 OutgoingReg(I32, p1:int) uses=[v17:any@early]
      #|  i17 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering selects non-trapping scalar conversions" {
  let builder = @semantic.FunctionBuilder::new(
    "scalar_conversions",
    Internal,
    [Ptr64, I32, I64, F32, F64],
    [I32, I64, F32, F64],
  )
  let parameters = builder.parameters()
  let wrapped0 = builder.emit(Convert(I32WrapI64), [parameters[2]], [I32])[0]
  let signed8 = builder.emit(Convert(SignExtend(I32, W8)), [wrapped0], [I32])[0]
  let bits32 = builder.emit(Convert(Bitcast(I32, F32)), [signed8], [F32])[0]
  let wrapped = builder.emit(Convert(Bitcast(F32, I32)), [bits32], [I32])[0]
  let signed = builder.emit(Convert(I64ExtendI32(Signed)), [parameters[1]], [
      I64,
    ])[0]
  let unsigned = builder.emit(
      Convert(I64ExtendI32(Unsigned)),
      [parameters[1]],
      [I64],
    )[0]
  let combined = builder.emit(IntBinary(Add), [signed, unsigned], [I64])[0]
  let signed16 = builder.emit(Convert(SignExtend(I64, W16)), [combined], [I64])[0]
  let bits64 = builder.emit(Convert(Bitcast(I64, F64)), [signed16], [F64])[0]
  let extended = builder.emit(Convert(Bitcast(F64, I64)), [bits64], [I64])[0]
  let demoted = builder.emit(Convert(F32DemoteF64), [parameters[4]], [F32])[0]
  let int_float32 = builder.emit(
      Convert(IntToFloat(I32, F32, Signed)),
      [parameters[1]],
      [F32],
    )[0]
  let float32 = builder.emit(FloatBinary(Add), [demoted, int_float32], [F32])[0]
  let promoted = builder.emit(Convert(F64PromoteF32), [parameters[3]], [F64])[0]
  let int_float64 = builder.emit(
      Convert(IntToFloat(I64, F64, Unsigned)),
      [parameters[2]],
      [F64],
    )[0]
  let float64 = builder.emit(FloatBinary(Add), [promoted, int_float64], [F64])[0]
  builder.return_([wrapped, extended, float32, float64])
  inspect(
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_conversions(v0:ptr64, v1:i32, v2:i64, v3:f32, v4:f64) -> (i32, i64, f32, f64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v5:any@late]
      #|  i1 IncomingReg(I32, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v6:any@late]
      #|  i2 IncomingReg(I64, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v7:any@late]
      #|  i3 IncomingReg(F32, p0:fpvec) uses=[v3:fixed(p0:fpvec)@early] defs=[v8:any@late]
      #|  i4 IncomingReg(F64, p1:fpvec) uses=[v4:fixed(p1:fpvec)@early] defs=[v9:any@late]
      #|  i5 Convert(WrapI64ToI32) uses=[v7:any@early] defs=[v10:any@late]
      #|  i6 Convert(SignExtend(I32, W8)) uses=[v10:any@early] defs=[v11:any@late]
      #|  i7 Convert(Bitcast(I32, F32)) uses=[v11:any@early] defs=[v12:any@late]
      #|  i8 Convert(Bitcast(F32, I32)) uses=[v12:any@early] defs=[v13:any@late]
      #|  i9 Convert(ExtendI32ToI64(Signed)) uses=[v6:any@early] defs=[v14:any@late]
      #|  i10 Convert(ExtendI32ToI64(Unsigned)) uses=[v6:any@early] defs=[v15:any@late]
      #|  i11 IntBinary(W64, Add) uses=[v14:any@early, v15:any@early] defs=[v16:any@late]
      #|  i12 Convert(SignExtend(I64, W16)) uses=[v16:any@early] defs=[v17:any@late]
      #|  i13 Convert(Bitcast(I64, F64)) uses=[v17:any@early] defs=[v18:any@late]
      #|  i14 Convert(Bitcast(F64, I64)) uses=[v18:any@early] defs=[v19:any@late]
      #|  i15 Convert(DemoteF64ToF32) uses=[v9:any@early] defs=[v20:any@late]
      #|  i16 Convert(IntToFloat(I32, F32, Signed)) uses=[v6:any@early] defs=[v21:any@late]
      #|  i17 FloatBinary(F32, Add) uses=[v20:any@early, v21:any@early] defs=[v22:any@late]
      #|  i18 Convert(PromoteF32ToF64) uses=[v8:any@early] defs=[v23:any@late]
      #|  i19 Convert(IntToFloat(I64, F64, Unsigned)) uses=[v7:any@early] defs=[v24:any@late]
      #|  i20 FloatBinary(F64, Add) uses=[v23:any@early, v24:any@early] defs=[v25:any@late]
      #|  i21 OutgoingReg(I32, p0:int) uses=[v13:any@early]
      #|  i22 OutgoingReg(I64, p1:int) uses=[v19:any@early]
      #|  i23 OutgoingReg(F32, p0:fpvec) uses=[v22:any@early]
      #|  i24 OutgoingReg(F64, p1:fpvec) uses=[v25:any@early]
      #|  i25 Return
      #|
    ),
  )
}
