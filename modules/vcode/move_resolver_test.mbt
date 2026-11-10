///|
test "parallel move planner accepts empty inputs with concrete scratch roles" {
  debug_inspect(
    @vcode.plan_parallel_moves(
      [],
      @vcode.PhysicalReg::new(16, Int),
      @vcode.PhysicalReg::new(16, FpVector),
    ),
    content="{ steps: [], requires_emergency: false }",
  )
}

///|
test "parallel move resolver preserves cycles and stack transfers" {
  let int0 = @vcode.PhysicalReg::new(0, Int)
  let int1 = @vcode.PhysicalReg::new(1, Int)
  let int16 = @vcode.PhysicalReg::new(16, Int)
  let function : @vcode.Builder[TestInst] = @vcode.Builder::new("move_slots", [])
  let allocation = @vcode.Allocation::for_function(function.finish())
  let stack0 = allocation.create_stack_slot(I64, 8, 8)
  let stack1 = allocation.create_stack_slot(I64, 8, 8)
  debug_inspect(
    @vcode.plan_parallel_moves(
      [
        @vcode.ParallelMove::new(I64, Register(int0), Register(int1)),
        @vcode.ParallelMove::new(I64, Register(int1), Register(int0)),
        @vcode.ParallelMove::new(I64, Stack(stack0), Stack(stack1)),
      ],
      int16,
      @vcode.PhysicalReg::new(16, FpVector),
    ),
    content=(
      #|{
      #|  steps: [
      #|    Transfer({ ty: I64, from: stack0, to: p16:int }),
      #|    Transfer({ ty: I64, from: p16:int, to: stack1 }),
      #|    Transfer({ ty: I64, from: p1:int, to: p16:int }),
      #|    Transfer({ ty: I64, from: p0:int, to: p1:int }),
      #|    Transfer({ ty: I64, from: p16:int, to: p0:int }),
      #|  ],
      #|  requires_emergency: false,
      #|}
    ),
  )
}

///|
test "parallel move resolver shares the physical FP and SIMD bank" {
  let fp0 = @vcode.PhysicalReg::new(0, FpVector)
  let fp1 = @vcode.PhysicalReg::new(1, FpVector)
  let fp16 = @vcode.PhysicalReg::new(16, FpVector)
  debug_inspect(
    @vcode.plan_parallel_moves(
      [
        @vcode.ParallelMove::new(F32, Register(fp0), Register(fp1)),
        @vcode.ParallelMove::new(V128, Register(fp1), Register(fp0)),
      ],
      @vcode.PhysicalReg::new(16, Int),
      fp16,
    ),
    content=(
      #|{
      #|  steps: [
      #|    Transfer({ ty: V128, from: p1:fpvec, to: p16:fpvec }),
      #|    Transfer({ ty: F32, from: p0:fpvec, to: p1:fpvec }),
      #|    Transfer({ ty: V128, from: p16:fpvec, to: p0:fpvec }),
      #|  ],
      #|  requires_emergency: false,
      #|}
    ),
  )
}

///|
test "parallel move resolver never reuses a final destination as scratch" {
  let int0 = @vcode.PhysicalReg::new(0, Int)
  let int1 = @vcode.PhysicalReg::new(1, Int)
  let int2 = @vcode.PhysicalReg::new(2, Int)
  let int16 = @vcode.PhysicalReg::new(16, Int)
  let int17 = @vcode.PhysicalReg::new(17, Int)
  debug_inspect(
    @vcode.plan_parallel_moves(
      [
        @vcode.ParallelMove::new(I64, Register(int0), Register(int1)),
        @vcode.ParallelMove::new(I64, Register(int1), Register(int0)),
        @vcode.ParallelMove::new(I64, Register(int2), Register(int16)),
      ],
      int17,
      @vcode.PhysicalReg::new(16, FpVector),
    ),
    content=(
      #|{
      #|  steps: [
      #|    Transfer({ ty: I64, from: p2:int, to: p16:int }),
      #|    Transfer({ ty: I64, from: p1:int, to: p17:int }),
      #|    Transfer({ ty: I64, from: p0:int, to: p1:int }),
      #|    Transfer({ ty: I64, from: p17:int, to: p0:int }),
      #|  ],
      #|  requires_emergency: false,
      #|}
    ),
  )
}

///|
test "parallel move planner rejects scratch registers used by transfers" {
  for class in [@vcode.RegClass::Int, FpVector] {
    let scratch = @vcode.PhysicalReg::new(16, class)
    let other = @vcode.PhysicalReg::new(0, class)
    let ty : @vcode.ValueType = if class == Int { I64 } else { F64 }
    for (from, to) in [(scratch, other), (other, scratch)] {
      try
        @vcode.plan_parallel_moves(
          [@vcode.ParallelMove::new(ty, Register(from), Register(to))],
          @vcode.PhysicalReg::new(16, Int),
          @vcode.PhysicalReg::new(16, FpVector),
        )
        |> ignore
      catch {
        NoSafeCycleScratch(class=actual) => assert_eq(actual, class)
        error => fail("unexpected move resolution error: \{error}")
      } noraise {
        _ => fail("expected a scratch register collision error")
      }
    }
  }
}

///|
test "call transfer planner snapshots stack arguments before register cycles" {
  let int0 = @vcode.PhysicalReg::new(0, Int)
  let int1 = @vcode.PhysicalReg::new(1, Int)
  let int16 = @vcode.PhysicalReg::new(16, Int)
  let function : @vcode.Builder[TestInst] = @vcode.Builder::new(
    "call_transfer_slots",
    [],
  )
  let allocation = @vcode.Allocation::for_function(function.finish())
  let stack0 = allocation.create_stack_slot(I64, 8, 8)
  debug_inspect(
    @vcode.plan_resolved_call_transfers(
      allocation,
      [
        @vcode.CallTransfer::to_stack(I64, Register(int0), 0),
        @vcode.CallTransfer::to_register(I64, Register(int1), int0),
        @vcode.CallTransfer::to_stack(I64, Stack(stack0), 8),
        @vcode.CallTransfer::to_register(I64, Register(int0), int1),
      ],
      0,
      16,
      [int16],
      [@vcode.PhysicalReg::new(16, FpVector)],
      @vcode.PhysicalReg::new(16, Int),
      @vcode.PhysicalReg::new(16, FpVector),
      [],
    ),
    content=(
      #|{
      #|  stack_transfers: [
      #|    { ty: I64, source: p0:int, offset: 0, scratch: None },
      #|    { ty: I64, source: stack0, offset: 8, scratch: Some(p16:int) },
      #|  ],
      #|  register_moves: {
      #|    steps: [
      #|      Transfer({ ty: I64, from: p0:int, to: p16:int }),
      #|      Transfer({ ty: I64, from: p1:int, to: p0:int }),
      #|      Transfer({ ty: I64, from: p16:int, to: p1:int }),
      #|    ],
      #|    requires_emergency: false,
      #|  },
      #|}
    ),
  )
}

///|
test "call transfer planner protects safepoint root homes" {
  let int0 = @vcode.PhysicalReg::new(0, Int)
  let int1 = @vcode.PhysicalReg::new(1, Int)
  let function : @vcode.Builder[TestInst] = @vcode.Builder::new(
    "protected_call",
    [],
  )
  let allocation = @vcode.Allocation::for_function(function.finish())
  try
    @vcode.plan_resolved_call_transfers(
      allocation,
      [@vcode.CallTransfer::to_register(I64, Register(int1), int0)],
      0,
      0,
      [@vcode.PhysicalReg::new(16, Int)],
      [@vcode.PhysicalReg::new(16, FpVector)],
      @vcode.PhysicalReg::new(16, Int),
      @vcode.PhysicalReg::new(16, FpVector),
      [Register(int0)],
    )
  catch {
    error =>
      debug_inspect(
        error,
        content="ProtectedLocationOverwrite(index=0, location=p0:int)",
      )
  } noraise {
    _ => fail("expected a protected root overwrite error")
  }
}

///|
test "call transfer planner rejects overlapping outgoing slots" {
  let int0 = @vcode.PhysicalReg::new(0, Int)
  let int1 = @vcode.PhysicalReg::new(1, Int)
  let function : @vcode.Builder[TestInst] = @vcode.Builder::new(
    "overlapping_call",
    [],
  )
  let allocation = @vcode.Allocation::for_function(function.finish())
  try
    @vcode.plan_resolved_call_transfers(
      allocation,
      [
        @vcode.CallTransfer::to_stack(I64, Register(int0), 0),
        @vcode.CallTransfer::to_stack(I32, Register(int1), 4),
      ],
      0,
      16,
      [@vcode.PhysicalReg::new(16, Int)],
      [@vcode.PhysicalReg::new(16, FpVector)],
      @vcode.PhysicalReg::new(16, Int),
      @vcode.PhysicalReg::new(16, FpVector),
      [],
    )
  catch {
    error =>
      debug_inspect(
        error,
        content="OverlappingStackDestination(first=0, second=1)",
      )
  } noraise {
    _ => fail("expected an overlapping stack destination error")
  }
}

///|
test "call transfer planner covers duplicate sources mixed banks and call metadata" {
  let int0 = @vcode.PhysicalReg::new(0, Int)
  let int1 = @vcode.PhysicalReg::new(1, Int)
  let callee = @vcode.PhysicalReg::new(2, Int)
  let result_area = @vcode.PhysicalReg::new(3, Int)
  let fp0 = @vcode.PhysicalReg::new(0, FpVector)
  let fp1 = @vcode.PhysicalReg::new(1, FpVector)
  let function : @vcode.Builder[TestInst] = @vcode.Builder::new("mixed_call", [])
  let allocation = @vcode.Allocation::for_function(function.finish())
  let float_slot = allocation.create_stack_slot(F64, 8, 8)
  debug_inspect(
    @vcode.plan_resolved_call_transfers(
      allocation,
      [
        @vcode.CallTransfer::to_register(Ptr64, Register(callee), int0),
        @vcode.CallTransfer::to_register(Ptr64, Register(result_area), int1),
        @vcode.CallTransfer::to_register(F64, Stack(float_slot), fp0),
        @vcode.CallTransfer::to_stack(V128, Register(fp1), 16),
        @vcode.CallTransfer::to_stack(I64, Register(callee), 0),
      ],
      0,
      32,
      [@vcode.PhysicalReg::new(16, Int)],
      [@vcode.PhysicalReg::new(16, FpVector)],
      @vcode.PhysicalReg::new(16, Int),
      @vcode.PhysicalReg::new(16, FpVector),
      [],
    ),
    content=(
      #|{
      #|  stack_transfers: [
      #|    { ty: V128, source: p1:fpvec, offset: 16, scratch: None },
      #|    { ty: I64, source: p2:int, offset: 0, scratch: None },
      #|  ],
      #|  register_moves: {
      #|    steps: [
      #|      Transfer({ ty: Ptr64, from: p2:int, to: p0:int }),
      #|      Transfer({ ty: Ptr64, from: p3:int, to: p1:int }),
      #|      Transfer({ ty: F64, from: stack0, to: p0:fpvec }),
      #|    ],
      #|    requires_emergency: false,
      #|  },
      #|}
    ),
  )
}

///|
test "call transfer planner validates source stack ownership type and layout" {
  let function : @vcode.Builder[TestInst] = @vcode.Builder::new(
    "source_contract",
    [],
  )
  let allocation = @vcode.Allocation::for_function(function.finish())
  let foreign_function : @vcode.Builder[TestInst] = @vcode.Builder::new(
    "foreign",
    [],
  )
  let foreign_allocation = @vcode.Allocation::for_function(
    foreign_function.finish(),
  )
  let foreign = foreign_allocation.create_stack_slot(I64, 8, 8)
  let wrong_type = allocation.create_stack_slot(F64, 8, 8)
  let invalid_layout = allocation.create_stack_slot(I64, 4, 4)
  let cases : Array[(@vcode.StackSlot, String)] = [
    (foreign, "ForeignSourceStack(index=0)"),
    (wrong_type, "InvalidSourceStackType(index=0, expected=I64, actual=F64)"),
    (invalid_layout, "InvalidSourceStackLayout(index=0)"),
  ]
  for (source, expected) in cases {
    try
      @vcode.plan_resolved_call_transfers(
        allocation,
        [
          @vcode.CallTransfer::to_register(
            I64,
            Stack(source),
            @vcode.PhysicalReg::new(0, Int),
          ),
        ],
        0,
        0,
        [@vcode.PhysicalReg::new(16, Int)],
        [@vcode.PhysicalReg::new(16, FpVector)],
        @vcode.PhysicalReg::new(16, Int),
        @vcode.PhysicalReg::new(16, FpVector),
        [],
      )
      |> ignore
    catch {
      error => debug_inspect(error, content=expected)
    } noraise {
      _ => fail("expected a source stack contract error")
    }
  }
}

///|
test "call transfer planner enforces the outgoing stack interval" {
  let function : @vcode.Builder[TestInst] = @vcode.Builder::new(
    "outgoing_range",
    [],
  )
  let allocation = @vcode.Allocation::for_function(function.finish())
  try
    @vcode.plan_resolved_call_transfers(
      allocation,
      [
        @vcode.CallTransfer::to_stack(
          I64,
          Register(@vcode.PhysicalReg::new(0, Int)),
          8,
        ),
      ],
      0,
      8,
      [@vcode.PhysicalReg::new(16, Int)],
      [@vcode.PhysicalReg::new(16, FpVector)],
      @vcode.PhysicalReg::new(16, Int),
      @vcode.PhysicalReg::new(16, FpVector),
      [],
    )
  catch {
    error =>
      debug_inspect(
        error,
        content="OutgoingStackDestinationOutOfRange(index=0, offset=8)",
      )
  } noraise {
    _ => fail("expected an outgoing stack range error")
  }
}

///|
test "call transfer planner does not destroy protected or pending scratch sources" {
  let function : @vcode.Builder[TestInst] = @vcode.Builder::new(
    "scratch_contract",
    [],
  )
  let allocation = @vcode.Allocation::for_function(function.finish())
  let source_slot = allocation.create_stack_slot(I64, 8, 8)
  let int0 = @vcode.PhysicalReg::new(0, Int)
  let int1 = @vcode.PhysicalReg::new(1, Int)
  let int2 = @vcode.PhysicalReg::new(2, Int)
  debug_inspect(
    @vcode.plan_resolved_call_transfers(
      allocation,
      [
        @vcode.CallTransfer::to_stack(I64, Stack(source_slot), 0),
        @vcode.CallTransfer::to_stack(I64, Register(int0), 8),
      ],
      0,
      16,
      [int0, int1, int2],
      [@vcode.PhysicalReg::new(16, FpVector)],
      @vcode.PhysicalReg::new(16, Int),
      @vcode.PhysicalReg::new(16, FpVector),
      [Register(int1)],
    ),
    content=(
      #|{
      #|  stack_transfers: [
      #|    { ty: I64, source: stack0, offset: 0, scratch: Some(p2:int) },
      #|    { ty: I64, source: p0:int, offset: 8, scratch: None },
      #|  ],
      #|  register_moves: { steps: [], requires_emergency: false },
      #|}
    ),
  )
}

///|
test "call transfer planner rejects invalid class destination and scratch contracts" {
  let function : @vcode.Builder[TestInst] = @vcode.Builder::new(
    "invalid_contracts",
    [],
  )
  let allocation = @vcode.Allocation::for_function(function.finish())
  let int0 = @vcode.PhysicalReg::new(0, Int)
  let int1 = @vcode.PhysicalReg::new(1, Int)
  let fp0 = @vcode.PhysicalReg::new(0, FpVector)
  let int16 = @vcode.PhysicalReg::new(16, Int)
  let fp16 = @vcode.PhysicalReg::new(16, FpVector)
  let source_slot = allocation.create_stack_slot(I64, 8, 8)
  let cases : Array[
    (Array[@vcode.CallTransfer], Int32, Array[@vcode.PhysicalReg], String),
  ] = [
    (
      [@vcode.CallTransfer::to_register(I64, Register(fp0), int0)],
      0,
      [int16],
      "InvalidSourceClass(index=0)",
    ),
    (
      [@vcode.CallTransfer::to_register(I64, Register(int0), fp0)],
      0,
      [int16],
      "InvalidDestinationClass(index=0)",
    ),
    (
      [
        @vcode.CallTransfer::to_register(I64, Register(int0), int1),
        @vcode.CallTransfer::to_register(I64, Register(int1), int1),
      ],
      0,
      [int16],
      "DuplicateRegisterDestination(index=1, register=p1:int)",
    ),
    (
      [@vcode.CallTransfer::to_stack(I32, Register(int0), 2)],
      8,
      [int16],
      "InvalidStackOffset(index=0, offset=2)",
    ),
    (
      [@vcode.CallTransfer::to_stack(I64, Stack(source_slot), 0)],
      8,
      [],
      "MoveResolutionFailed(cause=MissingScratch(class=Int))",
    ),
    (
      [@vcode.CallTransfer::to_stack(I64, Stack(source_slot), 0)],
      8,
      [fp0],
      "MoveResolutionFailed(cause=InvalidScratch(reg=p0:fpvec, expected=Int))",
    ),
  ]
  for (transfers, size, stack_scratch, expected) in cases {
    try
      @vcode.plan_resolved_call_transfers(
        allocation,
        transfers,
        0,
        size,
        stack_scratch,
        [fp16],
        int16,
        fp16,
        [],
      )
      |> ignore
    catch {
      error => debug_inspect(error, content=expected)
    } noraise {
      _ => fail("expected a call transfer contract error")
    }
  }
}
