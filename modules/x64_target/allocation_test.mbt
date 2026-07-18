///|
test "x64 target allocates selected scalar VCode" {
  let builder = @semantic.FunctionBuilder::new(
    "allocated_add",
    Internal,
    [Ptr64, I64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let sum = builder.emit(IntBinary(Add), [parameters[1], parameters[2]], [I64])[0]
  builder.return_([sum])
  let selected = lower(builder.finish(), test_lowering_context())
  inspect(
    allocate(selected).summary(),
    content=(
      #|allocation allocated_add
      #|  v0:ptr64 -> p0:int
      #|  v1:i64 -> p1:int
      #|  v2:i64 -> p2:int
      #|  v3:ptr64 -> p3:int
      #|  v4:i64 -> p0:int
      #|  v5:i64 -> p1:int
      #|  v6:i64 -> p0:int
      #|  i0 operand0 -> p7:int
      #|  i0 operand1 -> p3:int
      #|  i1 operand0 -> p6:int
      #|  i1 operand1 -> p0:int
      #|  i2 operand0 -> p2:int
      #|  i2 operand1 -> p1:int
      #|  i3 operand0 -> p0:int
      #|  i3 operand1 -> p1:int
      #|  i3 operand2 -> p0:int
      #|  i4 operand0 -> p0:int
      #|  before(i0): move v0 p0:int -> p7:int
      #|  before(i1): move v1 p1:int -> p6:int
      #|
    ),
  )
}
