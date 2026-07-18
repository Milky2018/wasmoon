///|
test "X64 owns a statically typed Target VCode checkpoint" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new_with_results(
    "x64_add",
    [I64, I64],
    [I64],
  )
  let entry = builder.entry_block()
  let (_, result) = builder.append_body(
    entry,
    IntBinary(W64, Add),
    [
      @vcode.Input::any(builder.parameter(0)),
      @vcode.Input::any(builder.parameter(1)),
    ],
    [@vcode.Output::any(I64)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  builder.append_body(
    entry,
    OutgoingReg(I64, @vcode.PhysicalReg::new(0, Int)),
    [@vcode.Input::any(result[0])],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let function = builder.finish()
  verify_vcode(function)
  inspect(
    function.summary(),
    content=(
      #|vcode x64_add(v0:i64, v1:i64) -> (i64)
      #|block0:
      #|  i0 IntBinary(W64, Add) uses=[v0:any@early, v1:any@early] defs=[v2:any@late]
      #|  i1 OutgoingReg(I64, p0:int) uses=[v2:any@early]
      #|  i2 Return
      #|
    ),
  )
}

///|
test "X64 verifier rejects an invalid 32-bit constant" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new("bad_const", [])
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    LoadConstant(W32, 0x100000000UL),
    [],
    [@vcode.Output::any(I32)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="32-bit constant has non-zero high bits",
          #|)
        ),
      )
  }
}

///|
test "X64 verifier rejects duplicate switch cases" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new("bad_switch", [
    I32,
  ])
  let entry = builder.entry_block()
  let target = builder.create_block([])
  builder.set_terminator(
    entry,
    Switch(W32, [1UL, 1UL]),
    [@vcode.Input::any(builder.parameter(0))],
    [
      @vcode.Edge::new(target, []),
      @vcode.Edge::new(target, []),
      @vcode.Edge::new(target, []),
    ],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    target,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  try verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="switch cases must be unique values of the index width",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected duplicate switch cases to be rejected")
  }
}

///|
test "X64 verifier requires typed trap metadata" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new("bad_trap", [])
  builder.set_terminator(
    builder.entry_block(),
    Trap(Unreachable),
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  try verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="trap terminator metadata does not match its reason",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected an untyped trap terminator to be rejected")
  }
}

///|
test "X64 verifier rejects a vector splat with the wrong scalar bank" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "bad_vector_splat",
    [I64],
  )
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    VectorSplat(F64x2),
    [@vcode.Input::any(builder.parameter(0))],
    [@vcode.Output::any(V128)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  try verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content="InvalidInstruction(instruction=i0, message=\"invalid use value type\")",
      )
  } noraise {
    _ => fail("expected the invalid vector splat to be rejected")
  }
}

///|
test "X64 verifier rejects an untied vector lane replacement" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "untied_vector_lane_replacement",
    [V128, I32],
  )
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    VectorReplaceLane(I32x4, 0),
    [
      @vcode.Input::any(builder.parameter(0)),
      @vcode.Input::any(builder.parameter(1)),
    ],
    [@vcode.Output::any(V128)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  try verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="vector lane replacement result must be tied to its source vector",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected the untied vector lane replacement to be rejected")
  }
}

///|
test "X64 verifier rejects an out-of-range vector shuffle lane" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "invalid_vector_shuffle",
    [V128, V128],
  )
  let entry = builder.entry_block()
  let mask : FixedArray[Int] = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 32,
  ]
  builder.append_body(
    entry,
    VectorShuffle(mask),
    [
      @vcode.Input::any(builder.parameter(0)),
      @vcode.Input::any(builder.parameter(1)),
    ],
    [@vcode.Output::any(V128)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  try verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="vector shuffle lane index is out of range",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected the invalid vector shuffle to be rejected")
  }
}

///|
test "X64 verifier rejects floating lanes for vector integer operations" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "invalid_vector_integer_lane",
    [V128],
  )
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    VectorIntUnary(F32x4, Absolute),
    [@vcode.Input::any(builder.parameter(0))],
    [@vcode.Output::any(V128)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  try verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="vector integer unary operation requires integer lanes",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected the floating vector integer operation to be rejected")
  }
}

///|
fn test_platform_call_clobbers() -> Array[@vcode.PhysicalReg] {
  let clobbers : Array[@vcode.PhysicalReg] = []
  for index in [0, 1, 2, 6, 7, 8, 9, 10, 11] {
    clobbers.push(@vcode.PhysicalReg::new(index, Int))
  }
  for index in 0..<16 {
    clobbers.push(@vcode.PhysicalReg::new(index, FpVector))
  }
  clobbers
}

///|
test "X64 verifier rejects a call with missing ABI results" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "missing_call_result",
    [],
  )
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    PlatformCall(
      @semantic.ExternalSymbol::new("runtime.value"),
      @semantic.Signature::new([], [I64]),
    ),
    [],
    [],
    test_platform_call_clobbers(),
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="direct call results are not materialized in ABI order",
          #|)
        ),
      )
  }
}

///|
test "X64 verifier rejects an incomplete call clobber set" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "bad_call_clobbers",
    [],
  )
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    PlatformCall(
      @semantic.ExternalSymbol::new("runtime.effect"),
      @semantic.Signature::new([], []),
    ),
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="platform call has an invalid caller-saved clobber set",
          #|)
        ),
      )
  }
}

///|
test "X64 verifier rejects non-byte vector population count" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "bad_vector_population_count",
    [V128],
  )
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    VectorIntUnary(I16x8, PopulationCount),
    [@vcode.Input::any(builder.parameter(0))],
    [@vcode.Output::any(V128)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  try verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="vector population count requires i8x16 lanes",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected non-byte vector population count to be rejected")
  }
}

///|
test "X64 verifier rejects malformed widening vector operations" {
  let operations : Array[X64Inst] = [
    VectorIntUnary(I8x16, ExtendAddPairwise(Signed)),
    VectorIntBinary(I8x16, ExtendMultiply(Low, Signed)),
    VectorIntBinary(I16x8, Dot16To32Signed),
    VectorIntBinary(I32x4, Q15MultiplyRoundedSaturating),
  ]
  let errors : Array[TargetVCodeVerifyError] = []
  for operation in operations {
    let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
      "bad_vector_widening",
      [V128, V128],
    )
    let entry = builder.entry_block()
    let uses = match operation {
      VectorIntUnary(_, _) => [@vcode.Input::any(builder.parameter(0))]
      _ =>
        [
          @vcode.Input::any(builder.parameter(0)),
          @vcode.Input::any(builder.parameter(1)),
        ]
    }
    builder.append_body(
      entry,
      operation,
      uses,
      [@vcode.Output::any(V128)],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
    builder.set_terminator(
      entry,
      Return,
      [],
      [],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
    try verify_vcode(builder.finish()) catch {
      error => errors.push(error)
    } noraise {
      _ => fail("expected malformed widening vector operation to be rejected")
    }
  }
  debug_inspect(
    errors,
    content=(
      #|[
      #|  InvalidInstruction(
      #|    instruction=i0,
      #|    message="pairwise extending add requires widened integer lanes",
      #|  ),
      #|  InvalidInstruction(
      #|    instruction=i0,
      #|    message="extending multiply requires widened integer lanes",
      #|  ),
      #|  InvalidInstruction(
      #|    instruction=i0,
      #|    message="dot16-to32 requires i32x4 destination lanes",
      #|  ),
      #|  InvalidInstruction(
      #|    instruction=i0,
      #|    message="q15 rounded saturating multiply requires i16x8 lanes",
      #|  ),
      #|]
    ),
  )
}

///|
test "X64 verifier rejects a non-widened vector extension destination" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "bad_vector_extension",
    [V128],
  )
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    VectorConvert(ExtendLow(I8x16, Signed)),
    [@vcode.Input::any(builder.parameter(0))],
    [@vcode.Output::any(V128)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  try verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="vector extension requires widened integer lanes",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected non-widened vector extension to be rejected")
  }
}

///|
test "X64 verifier rejects an invalid vector narrowing destination" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "bad_vector_narrowing",
    [V128, V128],
  )
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    VectorConvert(Narrow(I32x4, Signed)),
    [
      @vcode.Input::any(builder.parameter(0)),
      @vcode.Input::any(builder.parameter(1)),
    ],
    [@vcode.Output::any(V128)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  try verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="vector narrowing requires i8x16 or i16x8 lanes",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected invalid vector narrowing to be rejected")
  }
}

///|
test "X64 verifier rejects floating lanes for all-true" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "bad_vector_all_true",
    [V128],
  )
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    VectorPredicate(AllTrue(F32x4)),
    [@vcode.Input::any(builder.parameter(0))],
    [@vcode.Output::any(I32)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  try verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="vector all-true predicate requires integer lanes",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected floating all-true predicate to be rejected")
  }
}

///|
test "X64 verifier rejects floating lanes for bitmask" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "bad_vector_bitmask",
    [V128],
  )
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    VectorPredicate(BitMask(F64x2)),
    [@vcode.Input::any(builder.parameter(0))],
    [@vcode.Output::any(I32)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  try verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="vector bitmask predicate requires integer lanes",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected floating bitmask predicate to be rejected")
  }
}

///|
test "X64 verifier rejects integer lanes for vector float operations" {
  let operations : Array[X64Inst] = [
    VectorFloatUnary(I32x4, Absolute),
    VectorFloatBinary(I64x2, Add),
    VectorFloatCompare(I16x8, Equal),
  ]
  let errors : Array[TargetVCodeVerifyError] = []
  for operation in operations {
    let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
      "bad_vector_float_lane",
      [V128, V128],
    )
    let entry = builder.entry_block()
    let operands = match operation {
      VectorFloatUnary(_, _) => [@vcode.Input::any(builder.parameter(0))]
      _ =>
        [
          @vcode.Input::any(builder.parameter(0)),
          @vcode.Input::any(builder.parameter(1)),
        ]
    }
    builder.append_body(
      entry,
      operation,
      operands,
      [@vcode.Output::any(V128)],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
    builder.set_terminator(
      entry,
      Return,
      [],
      [],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
    try verify_vcode(builder.finish()) catch {
      error => errors.push(error)
    } noraise {
      _ => fail("expected integer vector float operation to be rejected")
    }
  }
  debug_inspect(
    errors,
    content=(
      #|[
      #|  InvalidInstruction(
      #|    instruction=i0,
      #|    message="vector float unary operation requires floating lanes",
      #|  ),
      #|  InvalidInstruction(
      #|    instruction=i0,
      #|    message="vector float operation requires floating lanes",
      #|  ),
      #|  InvalidInstruction(
      #|    instruction=i0,
      #|    message="vector float operation requires floating lanes",
      #|  ),
      #|]
    ),
  )
}

///|
test "X64 verifier rejects integer lanes for vector float ternary" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "bad_vector_float_ternary_lane",
    [V128, V128, V128],
  )
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    VectorFloatTernary(I32x4, FusedMultiplyAdd),
    [
      @vcode.Input::any(builder.parameter(0)),
      @vcode.Input::any(builder.parameter(1)),
      @vcode.Input::any(builder.parameter(2)),
    ],
    [@vcode.Output::any(V128)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  try verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="vector float ternary operation requires floating lanes",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected integer vector float ternary to be rejected")
  }
}

///|
test "X64 verifier rejects malformed vector numeric conversions" {
  let conversions : Array[X64VectorConversion] = [
    FloatToInt(I32x4, Signed),
    IntToFloat(I64x2, Unsigned),
  ]
  let errors : Array[TargetVCodeVerifyError] = []
  for conversion in conversions {
    let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
      "bad_vector_numeric_conversion",
      [V128],
    )
    let entry = builder.entry_block()
    builder.append_body(
      entry,
      VectorConvert(conversion),
      [@vcode.Input::any(builder.parameter(0))],
      [@vcode.Output::any(V128)],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
    builder.set_terminator(
      entry,
      Return,
      [],
      [],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
    try verify_vcode(builder.finish()) catch {
      error => errors.push(error)
    } noraise {
      _ => fail("expected malformed vector numeric conversion to be rejected")
    }
  }
  debug_inspect(
    errors,
    content=(
      #|[
      #|  InvalidInstruction(
      #|    instruction=i0,
      #|    message="vector float-to-int requires f32x4 or f64x2 source lanes",
      #|  ),
      #|  InvalidInstruction(
      #|    instruction=i0,
      #|    message="vector int-to-float requires f32x4 or f64x2 result lanes",
      #|  ),
      #|]
    ),
  )
}

///|
test "X64 verifier rejects malformed vector memory operations" {
  let operations : Array[X64Inst] = [
    VectorLoadZero(W16, 0UL),
    VectorLoadExtend(I8x16, Signed, 0UL),
    VectorLoadLane(I32x4, 4, 0UL),
    VectorStoreLane(I64x2, 2, 0UL),
  ]
  let errors : Array[TargetVCodeVerifyError] = []
  for operation in operations {
    let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
      "bad_vector_memory",
      [Ptr64, V128],
    )
    let entry = builder.entry_block()
    let (inputs, outputs) = match operation {
      VectorStoreLane(_, _, _) =>
        (
          [
            @vcode.Input::any(builder.parameter(0)),
            @vcode.Input::any(builder.parameter(1)),
          ],
          [],
        )
      VectorLoadLane(_, _, _) =>
        (
          [
            @vcode.Input::any(builder.parameter(0)),
            @vcode.Input::any(builder.parameter(1)),
          ],
          [@vcode.Output::any(V128)],
        )
      _ =>
        ([@vcode.Input::any(builder.parameter(0))], [@vcode.Output::any(V128)])
    }
    builder.append_body(
      entry,
      operation,
      inputs,
      outputs,
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
    builder.set_terminator(
      entry,
      Return,
      [],
      [],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
    try verify_vcode(builder.finish()) catch {
      error => errors.push(error)
    } noraise {
      _ => fail("expected malformed vector memory to be rejected")
    }
  }
  debug_inspect(
    errors,
    content=(
      #|[
      #|  InvalidInstruction(
      #|    instruction=i0,
      #|    message="vector load-zero requires width 32 or 64",
      #|  ),
      #|  InvalidInstruction(
      #|    instruction=i0,
      #|    message="vector load-extend requires widened integer lanes",
      #|  ),
      #|  InvalidInstruction(
      #|    instruction=i0,
      #|    message="vector load-lane index is out of range",
      #|  ),
      #|  InvalidInstruction(
      #|    instruction=i0,
      #|    message="vector store-lane index is out of range",
      #|  ),
      #|]
    ),
  )
}

///|
test "X64 verifier requires early-clobber atomic loop results" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "late_atomic_result",
    [Ptr64, I32],
  )
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    AtomicRmw(W32, I32, Add),
    [
      @vcode.Input::any(builder.parameter(0)),
      @vcode.Input::any(builder.parameter(1)),
    ],
    [@vcode.Output::any(I32)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  try verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="atomic RMW result must be an early definition",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected late atomic loop result to be rejected")
  }
}

///|
test "X64 verifier rejects a safepoint marker without metadata" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "unmarked_safepoint",
    [],
  )
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    SafepointMarker,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  try verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="safepoint marker requires safepoint metadata",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected unmarked safepoint to be rejected")
  }
}
