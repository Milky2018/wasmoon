///|
test "AArch64 allocation honors incoming and return ABI constraints" {
  let builder = @semantic.FunctionBuilder::new(
    "allocated_add",
    Platform,
    [I64, I64],
    [I64],
  )
  let sum = builder.emit(IntBinary(Add), builder.parameters(), [I64])[0]
  builder.return_([sum])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  inspect(
    allocation.summary(),
    content=(
      #|allocation allocated_add
      #|  v0:i64 -> p0:int
      #|  v1:i64 -> p1:int
      #|  v2:i64 -> p0:int
      #|  v3:i64 -> p1:int
      #|  v4:i64 -> p0:int
      #|  i0 operand0 -> p0:int
      #|  i0 operand1 -> p0:int
      #|  i1 operand0 -> p1:int
      #|  i1 operand1 -> p1:int
      #|  i2 operand0 -> p0:int
      #|  i2 operand1 -> p1:int
      #|  i2 operand2 -> p0:int
      #|  i3 operand0 -> p0:int
      #|
    ),
  )
  inspect(
    plan_frame(function, allocation).summary(),
    content=(
      #|aarch64 frame size=0 align=16
      #|
    ),
  )
}

///|
test "AArch64 frame plans spills and callee-saved registers" {
  let builder = @semantic.FunctionBuilder::new(
    "register_pressure",
    Platform,
    [],
    [I64],
  )
  let values : Array[@semantic.Value] = []
  for index in 0..<32 {
    values.push(builder.emit(I64Const(index.to_uint64()), [], [I64])[0])
  }
  let mut sum = values[0]
  for index in 1..<values.length() {
    sum = builder.emit(IntBinary(Add), [sum, values[index]], [I64])[0]
  }
  builder.return_([sum])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  inspect(
    plan_frame(function, allocation).summary(),
    content=(
      #|aarch64 frame size=0 align=16
      #|
    ),
  )
}

///|
test "AArch64 allocation keeps values live across a direct call out of clobbers" {
  let builder = @semantic.FunctionBuilder::new(
    "call_clobber",
    Platform,
    [I64],
    [I64],
  )
  let call = @semantic.SemanticCall::new(
    External(@semantic.ExternalSymbol::new("runtime.value")),
    @semantic.Signature::new([], [I64]),
    Platform,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  let called = builder.emit(Call(call), [], [I64])[0]
  let result = builder.emit(IntBinary(Add), [builder.parameters()[0], called], [
      I64,
    ])[0]
  builder.return_([result])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  inspect(
    allocation.summary(),
    content=(
      #|allocation call_clobber
      #|  v0:i64 -> p0:int
      #|  v1:i64 -> p19:int
      #|  v2:i64 -> p0:int
      #|  v3:i64 -> p0:int
      #|  i0 operand0 -> p0:int
      #|  i0 operand1 -> p19:int
      #|  i2 operand0 -> p0:int
      #|  i3 operand0 -> p19:int
      #|  i3 operand1 -> p0:int
      #|  i3 operand2 -> p0:int
      #|  i4 operand0 -> p0:int
      #|
    ),
  )
  inspect(
    plan_frame(function, allocation).summary(),
    content=(
      #|aarch64 frame size=16 align=16
      #|  save p19:int at sp+0
      #|  save p30:int at sp+8
      #|
    ),
  )
}

///|
test "AArch64 allocation preserves state across both returns from setjmp" {
  let builder = @semantic.FunctionBuilder::new(
    "allocated_returns_twice",
    Platform,
    [Ptr64, I32, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let call = @semantic.SemanticCall::new(
    External(@semantic.ExternalSymbol::new("runtime.sigsetjmp")),
    @semantic.Signature::new([Ptr64, I32], [I32]),
    Platform,
    @semantic.CallBehavior::new(
      ReadWrite,
      false,
      false,
      false,
      false,
      returns_twice=true,
    ),
  )
  let result = builder.emit(Call(call), [parameters[0], parameters[1]], [I32])[0]
  let widened = builder.emit(Convert(I64ExtendI32(Unsigned)), [result], [I64])[0]
  let sum = builder.emit(IntBinary(Add), [parameters[2], widened], [I64])[0]
  builder.return_([sum])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  inspect(
    allocation.summary(),
    content=(
      #|allocation allocated_returns_twice
      #|  v0:ptr64 -> p0:int
      #|  v1:i32 -> p1:int
      #|  v2:i64 -> p2:int
      #|  v3:ptr64 -> p0:int
      #|  v4:i32 -> p1:int
      #|  v5:i64 -> p19:int
      #|  v6:i32 -> p0:int
      #|  v7:i64 -> p0:int
      #|  v8:i64 -> p0:int
      #|  i0 operand0 -> p0:int
      #|  i0 operand1 -> p0:int
      #|  i1 operand0 -> p1:int
      #|  i1 operand1 -> p1:int
      #|  i2 operand0 -> p2:int
      #|  i2 operand1 -> p19:int
      #|  i3 operand0 -> p0:int
      #|  i3 operand1 -> p1:int
      #|  i4 operand0 -> p0:int
      #|  i5 operand0 -> p0:int
      #|  i5 operand1 -> p0:int
      #|  i6 operand0 -> p19:int
      #|  i6 operand1 -> p0:int
      #|  i6 operand2 -> p0:int
      #|  i7 operand0 -> p0:int
      #|
    ),
  )
  inspect(
    plan_frame(function, allocation).summary(),
    content=(
      #|aarch64 frame size=16 align=16
      #|  save p19:int at sp+0
      #|  save p30:int at sp+8
      #|
    ),
  )
}

///|
test "AArch64 call inputs may remain in spill slots" {
  let parameter_types : Array[@semantic.ValueType] = Array::make(32, I64)
  let builder = @semantic.FunctionBuilder::new(
    "spilled_call_inputs",
    Platform,
    parameter_types,
    [],
  )
  let call = @semantic.SemanticCall::new(
    External(@semantic.ExternalSymbol::new("runtime.many")),
    @semantic.Signature::new(parameter_types, []),
    Platform,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.emit(Call(call), builder.parameters(), []) |> ignore
  builder.return_([])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  inspect(
    allocation.summary(),
    content=(
      #|allocation spilled_call_inputs
      #|  v0:i64 -> p0:int
      #|  v1:i64 -> p1:int
      #|  v2:i64 -> stack0:i64(size=8, align=8)
      #|  v3:i64 -> stack1:i64(size=8, align=8)
      #|  v4:i64 -> stack2:i64(size=8, align=8)
      #|  v5:i64 -> stack3:i64(size=8, align=8)
      #|  v6:i64 -> stack4:i64(size=8, align=8)
      #|  v7:i64 -> stack5:i64(size=8, align=8)
      #|  v8:i64 -> p8:int
      #|  v9:i64 -> p9:int
      #|  v10:i64 -> p10:int
      #|  v11:i64 -> p11:int
      #|  v12:i64 -> p12:int
      #|  v13:i64 -> p13:int
      #|  v14:i64 -> p14:int
      #|  v15:i64 -> p15:int
      #|  v16:i64 -> p19:int
      #|  v17:i64 -> p20:int
      #|  v18:i64 -> p21:int
      #|  v19:i64 -> p22:int
      #|  v20:i64 -> p23:int
      #|  v21:i64 -> p24:int
      #|  v22:i64 -> p25:int
      #|  v23:i64 -> p26:int
      #|  v24:i64 -> p27:int
      #|  v25:i64 -> p28:int
      #|  v26:i64 -> p7:int
      #|  v27:i64 -> p6:int
      #|  v28:i64 -> p5:int
      #|  v29:i64 -> p4:int
      #|  v30:i64 -> p3:int
      #|  v31:i64 -> p2:int
      #|  v32:i64 -> stack6:i64(size=8, align=8)
      #|  v33:i64 -> stack7:i64(size=8, align=8)
      #|  v34:i64 -> stack0:i64(size=8, align=8)
      #|  v35:i64 -> stack1:i64(size=8, align=8)
      #|  v36:i64 -> stack2:i64(size=8, align=8)
      #|  v37:i64 -> stack3:i64(size=8, align=8)
      #|  v38:i64 -> p6:int
      #|  v39:i64 -> p7:int
      #|  v40:i64 -> p8:int
      #|  v41:i64 -> p9:int
      #|  v42:i64 -> p10:int
      #|  v43:i64 -> p11:int
      #|  v44:i64 -> p12:int
      #|  v45:i64 -> p13:int
      #|  v46:i64 -> p14:int
      #|  v47:i64 -> p15:int
      #|  v48:i64 -> p19:int
      #|  v49:i64 -> p20:int
      #|  v50:i64 -> p21:int
      #|  v51:i64 -> p22:int
      #|  v52:i64 -> p23:int
      #|  v53:i64 -> p24:int
      #|  v54:i64 -> p25:int
      #|  v55:i64 -> p26:int
      #|  v56:i64 -> p27:int
      #|  v57:i64 -> p28:int
      #|  v58:i64 -> p0:int
      #|  v59:i64 -> p1:int
      #|  v60:i64 -> p2:int
      #|  v61:i64 -> p3:int
      #|  v62:i64 -> p4:int
      #|  v63:i64 -> p5:int
      #|  i0 operand0 -> p0:int
      #|  i0 operand1 -> stack6
      #|  i1 operand0 -> p1:int
      #|  i1 operand1 -> stack7
      #|  i2 operand0 -> p2:int
      #|  i2 operand1 -> stack0
      #|  i3 operand0 -> p3:int
      #|  i3 operand1 -> stack1
      #|  i4 operand0 -> p4:int
      #|  i4 operand1 -> stack2
      #|  i5 operand0 -> p5:int
      #|  i5 operand1 -> stack3
      #|  i6 operand0 -> p6:int
      #|  i6 operand1 -> p6:int
      #|  i7 operand0 -> p7:int
      #|  i7 operand1 -> p7:int
      #|  i8 operand0 -> p8:int
      #|  i9 operand0 -> p9:int
      #|  i10 operand0 -> p10:int
      #|  i11 operand0 -> p11:int
      #|  i12 operand0 -> p12:int
      #|  i13 operand0 -> p13:int
      #|  i14 operand0 -> p14:int
      #|  i15 operand0 -> p15:int
      #|  i16 operand0 -> p19:int
      #|  i17 operand0 -> p20:int
      #|  i18 operand0 -> p21:int
      #|  i19 operand0 -> p22:int
      #|  i20 operand0 -> p23:int
      #|  i21 operand0 -> p24:int
      #|  i22 operand0 -> p25:int
      #|  i23 operand0 -> p26:int
      #|  i24 operand0 -> p27:int
      #|  i25 operand0 -> p28:int
      #|  i26 operand0 -> p0:int
      #|  i27 operand0 -> p1:int
      #|  i28 operand0 -> p2:int
      #|  i29 operand0 -> p3:int
      #|  i30 operand0 -> p4:int
      #|  i31 operand0 -> p5:int
      #|  i32 operand0 -> stack6
      #|  i32 operand1 -> stack7
      #|  i32 operand2 -> stack0
      #|  i32 operand3 -> stack1
      #|  i32 operand4 -> stack2
      #|  i32 operand5 -> stack3
      #|  i32 operand6 -> p6:int
      #|  i32 operand7 -> p7:int
      #|  i32 operand8 -> p8:int
      #|  i32 operand9 -> p9:int
      #|  i32 operand10 -> p10:int
      #|  i32 operand11 -> p11:int
      #|  i32 operand12 -> p12:int
      #|  i32 operand13 -> p13:int
      #|  i32 operand14 -> p14:int
      #|  i32 operand15 -> p15:int
      #|  i32 operand16 -> p19:int
      #|  i32 operand17 -> p20:int
      #|  i32 operand18 -> p21:int
      #|  i32 operand19 -> p22:int
      #|  i32 operand20 -> p23:int
      #|  i32 operand21 -> p24:int
      #|  i32 operand22 -> p25:int
      #|  i32 operand23 -> p26:int
      #|  i32 operand24 -> p27:int
      #|  i32 operand25 -> p28:int
      #|  i32 operand26 -> p0:int
      #|  i32 operand27 -> p1:int
      #|  i32 operand28 -> p2:int
      #|  i32 operand29 -> p3:int
      #|  i32 operand30 -> p4:int
      #|  i32 operand31 -> p5:int
      #|  before(i2): reload v2 stack0 -> p2:int
      #|  before(i3): reload v3 stack1 -> p3:int
      #|  before(i4): reload v4 stack2 -> p4:int
      #|  before(i5): reload v5 stack3 -> p5:int
      #|  before(i6): reload v6 stack4 -> p6:int
      #|  before(i7): reload v7 stack5 -> p7:int
      #|
    ),
  )
  emit(function, allocation, plan_frame(function, allocation)) |> ignore
}

///|
test "AArch64 allocation honors internal call register affinities" {
  let builder = @semantic.FunctionBuilder::new(
    "internal_call_affinity",
    Internal,
    [Ptr64],
    [Ptr64],
  )
  let one = builder.emit(I64Const(1UL), [], [I64])[0]
  let call = @semantic.SemanticCall::new(
    Internal(@semantic.CodeSymbol::new("wasm.func.affinity")),
    @semantic.Signature::new([Ptr64, I64], []),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.emit(Call(call), [builder.parameters()[0], one], []) |> ignore
  builder.return_([builder.parameters()[0]])
  let function = lower(builder.finish(), test_lowering_context())
  inspect(
    allocate(function).summary(),
    content=(
      #|allocation internal_call_affinity
      #|  v0:ptr64 -> p0:int
      #|  v1:ptr64 -> p19:int
      #|  v2:i64 -> p1:int
      #|  i0 operand0 -> p0:int
      #|  i0 operand1 -> p19:int
      #|  i1 operand0 -> p1:int
      #|  i2 operand0 -> p19:int
      #|  i2 operand1 -> p1:int
      #|  i3 operand0 -> p19:int
      #|
    ),
  )
}

///|
test "AArch64 frame reserves one aligned outgoing stack-argument area" {
  let parameter_types : Array[@semantic.ValueType] = Array::make(9, I64)
  let builder = @semantic.FunctionBuilder::new(
    "stack_call_frame",
    Platform,
    parameter_types,
    [],
  )
  let call = @semantic.SemanticCall::new(
    External(@semantic.ExternalSymbol::new("runtime.many")),
    @semantic.Signature::new(parameter_types, []),
    Platform,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.emit(Call(call), builder.parameters(), []) |> ignore
  builder.return_([])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  inspect(
    plan_frame(function, allocation).summary(),
    content=(
      #|aarch64 frame size=32 align=16
      #|  outgoing 16 bytes at sp+0
      #|  save p30:int at sp+16
      #|
    ),
  )
}

///|
test "AArch64 frame separates semantic objects from outgoing spills and saves" {
  let parameter_types : Array[@semantic.ValueType] = Array::make(9, I64)
  let builder = @semantic.FunctionBuilder::new(
    "stack_object_frame",
    Platform,
    parameter_types,
    [Ptr64],
  )
  builder.create_stack_object(3, 1) |> ignore
  builder.create_stack_object(16, 16) |> ignore
  let object = builder.create_stack_object(24, 8)
  let call = @semantic.SemanticCall::new(
    External(@semantic.ExternalSymbol::new("runtime.many")),
    @semantic.Signature::new(parameter_types, []),
    Platform,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.emit(Call(call), builder.parameters(), []) |> ignore
  let address = builder.emit(StackAddress(object), [], [Ptr64])[0]
  let values : Array[@semantic.Value] = []
  for index in 0..<32 {
    values.push(builder.emit(I64Const(index.to_uint64()), [], [I64])[0])
  }
  let mut sum = values[0]
  for index in 1..<values.length() {
    sum = builder.emit(IntBinary(Add), [sum, values[index]], [I64])[0]
  }
  let result = builder.emit(PointerOffset, [address, sum], [Ptr64])[0]
  builder.return_([result])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  inspect(
    plan_frame(function, allocation).summary(),
    content=(
      #|aarch64 frame size=96 align=16
      #|  outgoing 16 bytes at sp+0
      #|  stack-objects 64 bytes at sp+16
      #|  save p30:int at sp+80
      #|
    ),
  )
}
