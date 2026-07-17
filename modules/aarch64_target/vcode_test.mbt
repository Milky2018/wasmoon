///|
test "AArch64 owns a statically typed Target VCode checkpoint" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new_with_results(
    "a64_add",
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
      #|vcode a64_add(v0:i64, v1:i64) -> (i64)
      #|block0:
      #|  i0 IntBinary(W64, Add) uses=[v0:any@early, v1:any@early] defs=[v2:any@late]
      #|  i1 OutgoingReg(I64, p0:int) uses=[v2:any@early]
      #|  i2 Return
      #|
    ),
  )
}

///|
test "AArch64 verifier rejects an invalid 32-bit constant" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new("bad_const", [])
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
test "AArch64 verifier rejects a vector splat with the wrong scalar bank" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new(
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
test "AArch64 verifier rejects an untied vector lane replacement" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new(
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
test "AArch64 verifier rejects an out-of-range vector shuffle lane" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new(
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
test "AArch64 verifier rejects floating lanes for vector integer operations" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new(
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
  for index in 0..<18 {
    clobbers.push(@vcode.PhysicalReg::new(index, Int))
  }
  for index in 0..<32 {
    clobbers.push(@vcode.PhysicalReg::new(index, FpVector))
  }
  clobbers
}

///|
test "AArch64 verifier rejects a call with missing ABI results" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new(
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
test "AArch64 verifier rejects an incomplete call clobber set" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new(
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
test "AArch64 verifier rejects non-byte vector population count" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new(
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
test "AArch64 verifier rejects malformed widening vector operations" {
  let operations : Array[AArch64Inst] = [
    VectorIntUnary(I8x16, ExtendAddPairwise(Signed)),
    VectorIntBinary(I8x16, ExtendMultiply(Low, Signed)),
    VectorIntBinary(I16x8, Dot16To32Signed),
    VectorIntBinary(I32x4, Q15MultiplyRoundedSaturating),
  ]
  let errors : Array[TargetVCodeVerifyError] = []
  for operation in operations {
    let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new(
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
test "AArch64 verifier rejects a non-widened vector extension destination" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new(
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
test "AArch64 verifier rejects an invalid vector narrowing destination" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new(
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
test "AArch64 verifier rejects floating lanes for all-true" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new(
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
test "AArch64 verifier rejects floating lanes for bitmask" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new(
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
