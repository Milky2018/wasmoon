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
