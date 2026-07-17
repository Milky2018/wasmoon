///|
test "AArch64 allocation honors incoming and return ABI constraints" {
  let builder = @semantic.FunctionBuilder::new(
    "allocated_add",
    Internal,
    [I64, I64],
    [I64],
  )
  let sum = builder.emit(IntBinary(Add), builder.parameters(), [I64])[0]
  builder.return_([sum])
  let function = lower(builder.finish())
  let allocation = allocate(function)
  inspect(
    allocation.summary(),
    content=(
      #|allocation allocated_add
      #|  v0:i64 -> p0:int
      #|  v1:i64 -> p1:int
      #|  v2:i64 -> p2:int
      #|  v3:i64 -> p0:int
      #|  v4:i64 -> p1:int
      #|  i0 operand0 -> p0:int
      #|  i0 operand1 -> p2:int
      #|  i1 operand0 -> p1:int
      #|  i1 operand1 -> p0:int
      #|  i2 operand0 -> p2:int
      #|  i2 operand1 -> p0:int
      #|  i2 operand2 -> p1:int
      #|  i3 operand0 -> p1:int
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
    Internal,
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
  let function = lower(builder.finish())
  let allocation = allocate(function)
  inspect(
    plan_frame(function, allocation).summary(),
    content=(
      #|aarch64 frame size=144 align=16
      #|  place stack0 at sp+0
      #|  place stack1 at sp+8
      #|  place stack2 at sp+16
      #|  place stack3 at sp+24
      #|  place stack4 at sp+32
      #|  place stack5 at sp+40
      #|  place stack6 at sp+48
      #|  save p19:int at sp+56
      #|  save p20:int at sp+64
      #|  save p21:int at sp+72
      #|  save p22:int at sp+80
      #|  save p23:int at sp+88
      #|  save p24:int at sp+96
      #|  save p25:int at sp+104
      #|  save p26:int at sp+112
      #|  save p27:int at sp+120
      #|  save p28:int at sp+128
      #|
    ),
  )
}

///|
test "AArch64 allocation keeps values live across a direct call out of clobbers" {
  let builder = @semantic.FunctionBuilder::new(
    "call_clobber",
    Internal,
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
  let function = lower(builder.finish())
  let allocation = allocate(function)
  inspect(
    allocation.summary(),
    content=(
      #|allocation call_clobber
      #|  v0:i64 -> p0:int
      #|  v1:i64 -> p19:int
      #|  v2:i64 -> p0:int
      #|  v3:i64 -> p1:int
      #|  i0 operand0 -> p0:int
      #|  i0 operand1 -> p19:int
      #|  i2 operand0 -> p0:int
      #|  i3 operand0 -> p19:int
      #|  i3 operand1 -> p0:int
      #|  i3 operand2 -> p1:int
      #|  i4 operand0 -> p1:int
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
