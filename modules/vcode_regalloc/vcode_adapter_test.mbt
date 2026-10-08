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
  let allocation = @vcode_regalloc.allocate_vcode(
    function,
    @vcode_regalloc.VCodeAllocationEnvironment::new(
      [@vcode.PhysicalReg::new(0, Int)],
      [@vcode.PhysicalReg::new(1, Int)],
    ),
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
  let allocation = @vcode_regalloc.allocate_vcode(
    builder.finish(),
    @vcode_regalloc.VCodeAllocationEnvironment::new(
      [@vcode.PhysicalReg::new(0, Int)],
      [],
    ),
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
  let allocation = @vcode_regalloc.allocate_vcode(
    builder.finish(),
    @vcode_regalloc.VCodeAllocationEnvironment::new(
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
  let allocation = @vcode_regalloc.allocate_vcode(
    builder.finish(),
    @vcode_regalloc.VCodeAllocationEnvironment::new(
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
      #|  v2:i64 -> p1:int
      #|  i0 operand0 -> p0:int
      #|  i0 operand1 -> p2:int
      #|  i0 operand2 -> p0:int
      #|  i1 operand0 -> p1:int
      #|  before(i0): move v1 p1:int -> p2:int
      #|  after(i0): move v2 p0:int -> p1:int
      #|
    ),
  )
}

///|
test "fixed-only operands do not become allocator scratch registers" {
  let home = @vcode.PhysicalReg::new(0, Int)
  let fixed_only = @vcode.PhysicalReg::new(2, Int)
  let builder : @vcode.Builder[Unit] = @vcode.Builder::new(
    "fixed_only_operand",
    [I64],
  )
  let entry = builder.entry_block()
  builder.set_terminator(
    entry,
    (),
    [@vcode.Input::fixed(builder.parameter(0), fixed_only)],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let allocation = @vcode_regalloc.allocate_vcode(
    builder.finish(),
    @vcode_regalloc.VCodeAllocationEnvironment::new([home], []).with_fixed_operand_regs([
        fixed_only,
      ],
    ),
  )
  inspect(
    allocation.summary(),
    content=(
      #|allocation fixed_only_operand
      #|  v0:i64 -> p0:int
      #|  i0 operand0 -> p2:int
      #|  before(i0): move v0 p0:int -> p2:int
      #|
    ),
  )
}

///|
test "generic adapter validates selected VCode before allocation" {
  let builder : @vcode.Builder[Unit] = @vcode.Builder::new("invalid_selected", [])
  let error = try {
    @vcode_regalloc.allocate_vcode(
      builder.finish(),
      @vcode_regalloc.VCodeAllocationEnvironment::new([], []),
    )
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

///|
test "direct output preserves implicit GC operands and spilled root homes" {
  let builder : @vcode.Builder[Unit] = @vcode.Builder::new("direct_gc_output", [
    GcRef64,
    I64,
    I64,
  ])
  let entry = builder.entry_block()
  let root = builder.parameter(0)
  let (call, _) = builder.append_body(
    entry,
    (),
    [],
    [],
    [@vcode.PhysicalReg::new(0, Int)],
    @vcode.InstructionMetadata::safepoint([root]),
  )
  builder.set_terminator(
    entry,
    (),
    [
      @vcode.Input::any_location(root),
      @vcode.Input::any_location(builder.parameter(1)),
      @vcode.Input::any_location(builder.parameter(2)),
    ],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let function = builder.finish()
  let environment = @vcode_regalloc.VCodeAllocationEnvironment::new(
    [@vcode.PhysicalReg::new(0, Int)],
    [@vcode.PhysicalReg::new(1, Int)],
  )
  let session = @vcode_regalloc.AllocationSession::new()
  let checked = @vcode_regalloc.allocate_vcode(function, environment)
  let unchecked = session.allocate_selected_vcode(
    function,
    environment,
    verify=false,
  )
  assert_eq(checked.summary(), unchecked.summary())
  assert_true(checked.stack_slot_count() > 0)
  assert_eq(checked.safepoint_roots(call).length(), 1)
  // The call has no explicit operands: operand zero is the allocator's GC root.
  assert_true(checked.allocated_operand_location_at(0, 0) is Some(_))
  @vcode.verify_allocation_invariants(function, unchecked)
  let again = session.allocate_selected_vcode(function, environment)
  assert_eq(again.summary(), checked.summary())
}
