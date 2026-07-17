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
    [],
    [F32],
  )
  let value = builder.emit(F32Const(0x3F800000U), [], [F32])[0]
  builder.return_([value])
  try lower(builder.finish(), test_lowering_context()) |> ignore catch {
    error =>
      inspect(
        error,
        content=(
          #|UnsupportedOperation(
          #|  block_index=0,
          #|  instruction_index=0,
          #|  operation=F32Const(1065353216),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected unsupported float selection to fail")
  }
}

///|
test "AArch64 lowering does not silently select non-trapping hardware divide" {
  let builder = @semantic.FunctionBuilder::new(
    "checked_divide",
    Platform,
    [I64, I64],
    [I64],
  )
  let value = builder.emit(IntBinary(SignedDiv), builder.parameters(), [I64])[0]
  builder.return_([value])
  try lower(builder.finish(), test_lowering_context()) |> ignore catch {
    error =>
      inspect(
        error,
        content=(
          #|UnsupportedOperation(
          #|  block_index=0,
          #|  instruction_index=0,
          #|  operation=IntBinary(SignedDiv),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected unchecked hardware division selection to fail")
  }
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
