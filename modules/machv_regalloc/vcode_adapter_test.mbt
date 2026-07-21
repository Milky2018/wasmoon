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
      #|  v1:i64 -> p0:int
      #|  i0 operand0 -> p0:int
      #|  i0 operand1 -> p0:int
      #|  i1 operand0 -> p0:int
      #|
    ),
  )
}

///|
test "location-aware inputs remain in spill slots without scratch reloads" {
  let builder : @vcode.Builder[Unit] = @vcode.Builder::new(
    "location_aware_inputs",
    [I64, I64],
  )
  let entry = builder.entry_block()
  builder.set_terminator(
    entry,
    (),
    [
      @vcode.Input::any_location(builder.parameter(0)),
      @vcode.Input::any_location(builder.parameter(1)),
    ],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let allocation = allocate_vcode(
    builder.finish(),
    VCodeAllocationEnvironment::new([@vcode.PhysicalReg::new(0, Int)], []),
  )
  inspect(
    allocation.summary(),
    content=(
      #|allocation location_aware_inputs
      #|  v0:i64 -> p0:int
      #|  v1:i64 -> stack0:i64(size=8, align=8)
      #|  i0 operand0 -> p0:int
      #|  i0 operand1 -> stack0
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
    VCodeAllocationEnvironment::new(
      [
        @vcode.PhysicalReg::new(0, FpVector),
        @vcode.PhysicalReg::new(1, FpVector),
      ],
      [@vcode.PhysicalReg::new(2, FpVector)],
    ),
  )
  inspect(
    allocation.summary(),
    content=(
      #|allocation fp_vector_alias
      #|  v0:f64 -> p0:fpvec
      #|  v1:v128 -> p1:fpvec
      #|  i0 operand0 -> p0:fpvec
      #|  i0 operand1 -> p1:fpvec
      #|
    ),
  )
}

///|
test "fixed operands are instruction-point constraints rather than value homes" {
  let builder : @vcode.Builder[Unit] = @vcode.Builder::new("fixed_point", [
    I64,
    I64,
  ])
  let entry = builder.entry_block()
  let (_, results) = builder.append_body(
    entry,
    (),
    [
      @vcode.Input::fixed(builder.parameter(0), @vcode.PhysicalReg::new(0, Int)),
      @vcode.Input::fixed(builder.parameter(1), @vcode.PhysicalReg::new(2, Int)),
    ],
    [@vcode.Output::fixed(I64, @vcode.PhysicalReg::new(0, Int))],
    [@vcode.PhysicalReg::new(1, Int)],
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
  let allocation = allocate_vcode(
    builder.finish(),
    VCodeAllocationEnvironment::new(
      [@vcode.PhysicalReg::new(0, Int), @vcode.PhysicalReg::new(1, Int)],
      [@vcode.PhysicalReg::new(2, Int)],
    ),
  )
  inspect(
    allocation.summary(),
    content=(
      #|allocation fixed_point
      #|  v0:i64 -> p0:int
      #|  v1:i64 -> p1:int
      #|  v2:i64 -> p0:int
      #|  i0 operand0 -> p0:int
      #|  i0 operand1 -> p2:int
      #|  i0 operand2 -> p0:int
      #|  i1 operand0 -> p0:int
      #|  before(i0): move v1 p1:int -> p2:int
      #|
    ),
  )
}

///|
test "generic adapter validates selected VCode before allocation" {
  let builder : @vcode.Builder[Unit] = @vcode.Builder::new("invalid_selected", [])
  let error = try {
    allocate_vcode(builder.finish(), VCodeAllocationEnvironment::new([], []))
    |> ignore
    "accepted"
  } catch {
    error => error.to_string()
  }
  inspect(
    error,
    content="InvalidSelected(cause=MissingTerminator(block=block0))",
  )
}
