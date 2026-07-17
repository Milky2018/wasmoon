///|
test "generic adapter allocates Target VCode without reading target instructions" {
  let builder : @vcode.Builder[Unit] = @vcode.Builder::new("adapter", [I64])
  let entry = builder.entry_block()
  let value = builder.parameter(0)
  let (_, results) = builder.append_body(
    entry,
    (),
    [@vcode.Input::any(value)],
    [@vcode.Output::any(I64)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  builder.set_terminator(
    entry,
    (),
    [@vcode.Input::any(results[0])],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let function = builder.finish()
  let allocation = allocate_vcode(
    function,
    VCodeAllocationEnvironment::new([@vcode.PhysicalReg::new(0, Int)], [
      @vcode.PhysicalReg::new(1, Int),
    ]),
  )
  inspect(
    allocation.summary(),
    content=(
      #|allocation adapter
      #|  v0:i64 -> p0:int
      #|  v1:i64 -> stack0:i64(size=8, align=8)
      #|  i0 operand0 -> p0:int
      #|  i0 operand1 -> p1:int
      #|  i1 operand0 -> p1:int
      #|  after(i0): spill v1 p1:int -> stack0
      #|  before(i1): reload v1 stack0 -> p1:int
      #|
    ),
  )
}

///|
test "floating-point and SIMD values share one physical register bank" {
  let builder : @vcode.Builder[Unit] = @vcode.Builder::new("fp_vector_alias", [
    F64,
    V128,
  ])
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    (),
    [
      @vcode.Input::any(builder.parameter(0)),
      @vcode.Input::any(builder.parameter(1)),
    ],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    (),
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let allocation = allocate_vcode(
    builder.finish(),
    VCodeAllocationEnvironment::new([@vcode.PhysicalReg::new(0, FpVector)], [
      @vcode.PhysicalReg::new(1, FpVector),
    ]),
  )
  inspect(
    allocation.summary(),
    content=(
      #|allocation fp_vector_alias
      #|  v0:f64 -> p0:fpvec
      #|  v1:v128 -> stack0:v128(size=16, align=16)
      #|  i0 operand0 -> p0:fpvec
      #|  i0 operand1 -> p1:fpvec
      #|  before(i0): reload v1 stack0 -> p1:fpvec
      #|
    ),
  )
}
