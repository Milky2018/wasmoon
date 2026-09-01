///|
test "X64 lowering selects scalar SSA and preserves source metadata" {
  let builder = @semantic.FunctionBuilder::new(
    "selected_add",
    Platform,
    [I64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let sum = builder.emit_with_metadata(
      IntBinary(Add),
      parameters,
      [I64],
      @semantic.InstructionMetadata::new(
        Some(@native.SourceLocation::new("selected.wat", 3, 9)),
        [],
      ),
    )[0]
  builder.return_([sum])
  let selected = lower(builder.finish_selection_plan(), test_lowering_context())
  inspect(
    selected.summary(),
    content=(
      #|vcode selected_add(v0:i64, v1:i64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(I64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v2:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(I64, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v3:any-location(prefer=p6:int)@late]
      #|  i2 IntBinary(W64, Add) uses=[v2:any@early, v3:any@early] defs=[v4:any@late] source={ file: "selected.wat", line: 3, column: 9 }
      #|  i3 OutgoingReg(I64, p0:int) uses=[v4:any@early]
      #|  i4 Return
      #|
    ),
  )
}

///|
test "X64 lowering lays out a loop for fallthrough before allocation" {
  let builder = @semantic.FunctionBuilder::new("cfg_layout", Platform, [I32], [
    I32,
  ])
  let exit = builder.create_block([I32])
  let body = builder.create_block([I32])
  let header = builder.create_block([I32])
  builder.jump(header, builder.parameters())
  builder.switch_to_block(header)
  let header_value = builder.block_parameters(header)[0]
  builder.branch(header_value, body, [header_value], exit, [header_value])
  builder.switch_to_block(body)
  builder.jump(header, builder.block_parameters(body))
  builder.switch_to_block(exit)
  builder.return_(builder.block_parameters(exit))
  let selected = lower(builder.finish_selection_plan(), test_lowering_context())
  debug_inspect(
    selected.layout().map(block => selected.block_index(block).unwrap()),
    content="[0, 3, 1, 2]",
  )
}

///|
test "X64 lowering rejects unsupported valid operations structurally" {
  let builder = @semantic.FunctionBuilder::new(
    "unsupported_big_endian_atomic",
    Platform,
    [Ptr64],
    [I32],
  )
  let loaded = builder.emit(
      AtomicLoad(
        @semantic.AtomicSpec::new(W32, I32, 0UL, Big, Some(MemoryOutOfBounds)),
      ),
      builder.parameters(),
      [I32],
    )[0]
  builder.return_([loaded])
  try
    lower(builder.finish_selection_plan(), test_lowering_context()) |> ignore
  catch {
    error =>
      inspect(
        error,
        content=(
          #|UnsupportedOperation(
          #|  block_index=0,
          #|  instruction_index=0,
          #|  operation=AtomicLoad(
          #|    {
          #|      width: W32,
          #|      value_type: I32,
          #|      offset: 0,
          #|      endianness: Big,
          #|      trap: Some(MemoryOutOfBounds),
          #|    },
          #|  ),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected big-endian atomic selection to fail")
  }
}

///|
test "X64 lowering selects sequentially consistent atomic families" {
  let builder = @semantic.FunctionBuilder::new(
    "atomic_families",
    Internal,
    [Ptr64, I32, I64],
    [I32],
  )
  let parameters = builder.parameters()
  builder.emit(
    AtomicLoad(
      @semantic.AtomicSpec::new(W8, I32, 0UL, Little, Some(MemoryOutOfBounds)),
    ),
    [parameters[0]],
    [I32],
  )
  |> ignore
  builder.emit(
    AtomicStore(
      @semantic.AtomicSpec::new(W16, I32, 2UL, Little, Some(MemoryOutOfBounds)),
    ),
    [parameters[0], parameters[1]],
    [],
  )
  |> ignore
  builder.emit(
    AtomicRmw(
      @semantic.AtomicSpec::new(W32, I32, 4UL, Little, Some(MemoryOutOfBounds)),
      Add,
    ),
    [parameters[0], parameters[1]],
    [I32],
  )
  |> ignore
  builder.emit(
    AtomicRmw(
      @semantic.AtomicSpec::new(W64, I64, 8UL, Little, Some(MemoryOutOfBounds)),
      Exchange,
    ),
    [parameters[0], parameters[2]],
    [I64],
  )
  |> ignore
  let exchanged = builder.emit(
      AtomicCompareExchange(
        @semantic.AtomicSpec::new(
          W8,
          I32,
          16UL,
          Little,
          Some(MemoryOutOfBounds),
        ),
      ),
      [parameters[0], parameters[1], parameters[1]],
      [I32],
    )[0]
  builder.emit(AtomicFence, [], []) |> ignore
  builder.return_([exchanged])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode atomic_families(v0:ptr64, v1:i32, v2:i64) -> (i32)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v3:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(I32, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v4:any-location(prefer=p6:int)@late]
      #|  i2 IncomingReg(I64, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v5:any-location(prefer=p2:int)@late]
      #|  i3 AtomicLoad(W8, I32) uses=[v3:any@early] defs=[v6:any@late] trap=MemoryOutOfBounds
      #|  i4 LoadConstant(W64, 2) defs=[v7:any@late]
      #|  i5 AddAddress uses=[v3:any@early, v7:any@early] defs=[v8:any@late]
      #|  i6 AtomicStore(W16, I32) uses=[v8:any@early, v4:fixed(p10:int)@early] trap=MemoryOutOfBounds
      #|  i7 LoadConstant(W64, 4) defs=[v9:any@late]
      #|  i8 AddAddress uses=[v3:any@early, v9:any@early] defs=[v10:any@late]
      #|  i9 AtomicRmw(W32, I32, Add) uses=[v10:any@early, v4:any@early] defs=[v11:any@late] trap=MemoryOutOfBounds
      #|  i10 LoadConstant(W64, 8) defs=[v12:any@late]
      #|  i11 AddAddress uses=[v3:any@early, v12:any@early] defs=[v13:any@late]
      #|  i12 AtomicRmw(W64, I64, Exchange) uses=[v13:any@early, v5:any@early] defs=[v14:any@late] trap=MemoryOutOfBounds
      #|  i13 LoadConstant(W64, 16) defs=[v15:any@late]
      #|  i14 AddAddress uses=[v3:any@early, v15:any@early] defs=[v16:any@late]
      #|  i15 AtomicCompareExchange(W8, I32) uses=[v16:any@early, v4:fixed(p0:int)@early, v4:any@early] defs=[v17:fixed(p0:int)@early] trap=MemoryOutOfBounds
      #|  i16 AtomicFence
      #|  i17 OutgoingReg(I32, p0:int) uses=[v17:any@early]
      #|  i18 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects standalone safepoint metadata markers" {
  let builder = @semantic.FunctionBuilder::new(
    "safepoint_marker",
    Internal,
    [Ptr64, GcRef64],
    [],
  )
  let root = builder.parameters()[1]
  builder.emit_with_metadata(
    Safepoint(GcAndCancellation),
    [],
    [],
    @semantic.InstructionMetadata::new(
      Some(@native.SourceLocation::new("safepoint.wat", 3, 5)),
      [root],
    ),
  )
  |> ignore
  builder.return_([])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode safepoint_marker(v0:ptr64, v1:gcref64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v2:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(GcRef64, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v3:any-location(prefer=p6:int)@late]
      #|  i2 SafepointMarker source={ file: "safepoint.wat", line: 3, column: 5 } safepoint=GcAndCancellation roots=[v3]
      #|  i3 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects the vector foundation" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_foundation",
    Internal,
    [Ptr64, I32, I64, F32, F64, V128, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let constant = builder.emit(
      V128Const(0x0706050403020100UL, 0x0F0E0D0C0B0A0908UL),
      [],
      [V128],
    )[0]
  let splats = [
    builder.emit(Vector(Splat(I8x16)), [parameters[1]], [V128])[0],
    builder.emit(Vector(Splat(I16x8)), [parameters[1]], [V128])[0],
    builder.emit(Vector(Splat(I32x4)), [parameters[1]], [V128])[0],
    builder.emit(Vector(Splat(I64x2)), [parameters[2]], [V128])[0],
    builder.emit(Vector(Splat(F32x4)), [parameters[3]], [V128])[0],
    builder.emit(Vector(Splat(F64x2)), [parameters[4]], [V128])[0],
  ]
  let mut value = constant
  for splat in splats {
    value = builder.emit(Vector(Bitwise(Xor)), [value, splat], [V128])[0]
  }
  value = builder.emit(Vector(Bitwise(Not)), [value], [V128])[0]
  value = builder.emit(Vector(Bitwise(And)), [value, parameters[5]], [V128])[0]
  value = builder.emit(Vector(Bitwise(Or)), [value, parameters[6]], [V128])[0]
  value = builder.emit(Vector(Bitwise(Xor)), [value, parameters[7]], [V128])[0]
  value = builder.emit(Vector(Bitwise(AndNot)), [value, constant], [V128])[0]
  value = builder.emit(
      Vector(Bitwise(BitSelect)),
      [value, parameters[5], parameters[6]],
      [V128],
    )[0]
  value = builder.emit(Select, [parameters[1], value, parameters[7]], [V128])[0]
  builder.return_([value])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_foundation(v0:ptr64, v1:i32, v2:i64, v3:f32, v4:f64, v5:v128, v6:v128, v7:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v8:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(I32, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v9:any-location(prefer=p6:int)@late]
      #|  i2 IncomingReg(I64, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v10:any-location(prefer=p2:int)@late]
      #|  i3 IncomingReg(F32, p0:fpvec) uses=[v3:fixed(p0:fpvec)@early] defs=[v11:any-location(prefer=p0:fpvec)@late]
      #|  i4 IncomingReg(F64, p1:fpvec) uses=[v4:fixed(p1:fpvec)@early] defs=[v12:any-location(prefer=p1:fpvec)@late]
      #|  i5 IncomingReg(V128, p2:fpvec) uses=[v5:fixed(p2:fpvec)@early] defs=[v13:any-location(prefer=p2:fpvec)@late]
      #|  i6 IncomingReg(V128, p3:fpvec) uses=[v6:fixed(p3:fpvec)@early] defs=[v14:any-location(prefer=p3:fpvec)@late]
      #|  i7 IncomingReg(V128, p4:fpvec) uses=[v7:fixed(p4:fpvec)@early] defs=[v15:any-location(prefer=p4:fpvec)@late]
      #|  i8 LoadVectorConstant(506097522914230528, 1084818905618843912) defs=[v16:any@late]
      #|  i9 VectorSplat(I8x16) uses=[v9:any@early] defs=[v17:any@late]
      #|  i10 VectorSplat(I16x8) uses=[v9:any@early] defs=[v18:any@late]
      #|  i11 VectorSplat(I32x4) uses=[v9:any@early] defs=[v19:any@late]
      #|  i12 VectorSplat(I64x2) uses=[v10:any@early] defs=[v20:any@late]
      #|  i13 VectorSplat(F32x4) uses=[v11:any@early] defs=[v21:any@late]
      #|  i14 VectorSplat(F64x2) uses=[v12:any@early] defs=[v22:any@late]
      #|  i15 VectorBitwise(Xor) uses=[v16:any@early, v17:any@early] defs=[v23:any@late]
      #|  i16 VectorBitwise(Xor) uses=[v23:any@early, v18:any@early] defs=[v24:any@late]
      #|  i17 VectorBitwise(Xor) uses=[v24:any@early, v19:any@early] defs=[v25:any@late]
      #|  i18 VectorBitwise(Xor) uses=[v25:any@early, v20:any@early] defs=[v26:any@late]
      #|  i19 VectorBitwise(Xor) uses=[v26:any@early, v21:any@early] defs=[v27:any@late]
      #|  i20 VectorBitwise(Xor) uses=[v27:any@early, v22:any@early] defs=[v28:any@late]
      #|  i21 VectorBitwise(Not) uses=[v28:any@early] defs=[v29:any@late]
      #|  i22 VectorBitwise(And) uses=[v29:any@early, v13:any@early] defs=[v30:any@late]
      #|  i23 VectorBitwise(Or) uses=[v30:any@early, v14:any@early] defs=[v31:any@late]
      #|  i24 VectorBitwise(Xor) uses=[v31:any@early, v15:any@early] defs=[v32:any@late]
      #|  i25 VectorBitwise(AndNot) uses=[v32:any@early, v16:any@early] defs=[v33:any@late]
      #|  i26 VectorBitwise(BitSelect) uses=[v33:any@early, v13:any@early, v14:any@early] defs=[v34:any@late]
      #|  i27 VectorSelect uses=[v9:any@early, v34:any@early, v15:any@early] defs=[v35:any@late]
      #|  i28 OutgoingReg(V128, p0:fpvec) uses=[v35:any@early]
      #|  i29 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects vector lane movement" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_lane_movement",
    Internal,
    [Ptr64, V128],
    [V128, I32, I64, F32, F64],
  )
  let vector = builder.parameters()[1]
  let narrow_extractions = [
    builder.emit(Vector(ExtractLane(I8x16, 15, Some(Signed))), [vector], [I32])[0],
    builder.emit(Vector(ExtractLane(I8x16, 0, Some(Unsigned))), [vector], [I32])[0],
    builder.emit(Vector(ExtractLane(I16x8, 7, Some(Signed))), [vector], [I32])[0],
    builder.emit(Vector(ExtractLane(I16x8, 0, Some(Unsigned))), [vector], [I32])[0],
    builder.emit(Vector(ExtractLane(I32x4, 3, None)), [vector], [I32])[0],
  ]
  let mut scalar32 = narrow_extractions[0]
  for index in 1..<narrow_extractions.length() {
    scalar32 = builder.emit(
        IntBinary(Xor),
        [scalar32, narrow_extractions[index]],
        [I32],
      )[0]
  }
  let scalar64 = builder.emit(Vector(ExtractLane(I64x2, 1, None)), [vector], [
      I64,
    ])[0]
  let scalar_f32 = builder.emit(Vector(ExtractLane(F32x4, 2, None)), [vector], [
      F32,
    ])[0]
  let scalar_f64 = builder.emit(Vector(ExtractLane(F64x2, 1, None)), [vector], [
      F64,
    ])[0]
  let mut replaced = builder.emit(
      Vector(ReplaceLane(I8x16, 15)),
      [vector, scalar32],
      [V128],
    )[0]
  replaced = builder.emit(Vector(ReplaceLane(I16x8, 7)), [replaced, scalar32], [
      V128,
    ])[0]
  replaced = builder.emit(Vector(ReplaceLane(I32x4, 3)), [replaced, scalar32], [
      V128,
    ])[0]
  replaced = builder.emit(Vector(ReplaceLane(I64x2, 1)), [replaced, scalar64], [
      V128,
    ])[0]
  replaced = builder.emit(
      Vector(ReplaceLane(F32x4, 2)),
      [replaced, scalar_f32],
      [V128],
    )[0]
  replaced = builder.emit(
      Vector(ReplaceLane(F64x2, 1)),
      [replaced, scalar_f64],
      [V128],
    )[0]
  builder.return_([replaced, scalar32, scalar64, scalar_f32, scalar_f64])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_lane_movement(v0:ptr64, v1:v128) -> (v128, i32, i64, f32, f64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v2:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v3:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingResultArea(p10:int) defs=[v4:any-location@late]
      #|  i3 VectorExtractLane(I8x16, 15, Some(Signed)) uses=[v3:any@early] defs=[v5:any@late]
      #|  i4 VectorExtractLane(I8x16, 0, Some(Unsigned)) uses=[v3:any@early] defs=[v6:any@late]
      #|  i5 VectorExtractLane(I16x8, 7, Some(Signed)) uses=[v3:any@early] defs=[v7:any@late]
      #|  i6 VectorExtractLane(I16x8, 0, Some(Unsigned)) uses=[v3:any@early] defs=[v8:any@late]
      #|  i7 VectorExtractLane(I32x4, 3, None) uses=[v3:any@early] defs=[v9:any@late]
      #|  i8 IntBinary(W32, Eor) uses=[v5:any@early, v6:any@early] defs=[v10:any@late]
      #|  i9 IntBinary(W32, Eor) uses=[v10:any@early, v7:any@early] defs=[v11:any@late]
      #|  i10 IntBinary(W32, Eor) uses=[v11:any@early, v8:any@early] defs=[v12:any@late]
      #|  i11 IntBinary(W32, Eor) uses=[v12:any@early, v9:any@early] defs=[v13:any@late]
      #|  i12 VectorExtractLane(I64x2, 1, None) uses=[v3:any@early] defs=[v14:any@late]
      #|  i13 VectorExtractLane(F32x4, 2, None) uses=[v3:any@early] defs=[v15:any@late]
      #|  i14 VectorExtractLane(F64x2, 1, None) uses=[v3:any@early] defs=[v16:any@late]
      #|  i15 VectorReplaceLane(I8x16, 15) uses=[v3:any@early, v13:any@early] defs=[v17:any@late]
      #|  i16 VectorReplaceLane(I16x8, 7) uses=[v17:any@early, v13:any@early] defs=[v18:any@late]
      #|  i17 VectorReplaceLane(I32x4, 3) uses=[v18:any@early, v13:any@early] defs=[v19:any@late]
      #|  i18 VectorReplaceLane(I64x2, 1) uses=[v19:any@early, v14:any@early] defs=[v20:any@late]
      #|  i19 VectorReplaceLane(F32x4, 2) uses=[v20:any@early, v15:any@early] defs=[v21:any@late]
      #|  i20 VectorReplaceLane(F64x2, 1) uses=[v21:any@early, v16:any@early] defs=[v22:any@late]
      #|  i21 OutgoingReg(V128, p0:fpvec) uses=[v22:any@early]
      #|  i22 OutgoingReg(I32, p0:int) uses=[v13:any@early]
      #|  i23 OutgoingReg(I64, p2:int) uses=[v14:any@early]
      #|  i24 OutgoingReg(F32, p1:fpvec) uses=[v15:any@early]
      #|  i25 OutgoingAreaResult(F64, 0) uses=[v4:any@early, v16:any@early]
      #|  i26 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects vector shuffle and swizzle" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_permute",
    Internal,
    [Ptr64, V128, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let mask : FixedArray[Int] = [
    0, 17, 2, 19, 4, 21, 6, 23, 8, 25, 10, 27, 12, 29, 14, 31,
  ]
  let shuffled = builder.emit(
      Vector(Shuffle(mask)),
      [parameters[1], parameters[2]],
      [V128],
    )[0]
  let swizzled = builder.emit(Vector(Swizzle), [shuffled, parameters[3]], [V128])[0]
  builder.return_([swizzled])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_permute(v0:ptr64, v1:v128, v2:v128, v3:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v4:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v5:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v6:any-location(prefer=p1:fpvec)@late]
      #|  i3 IncomingReg(V128, p2:fpvec) uses=[v3:fixed(p2:fpvec)@early] defs=[v7:any-location(prefer=p2:fpvec)@late]
      #|  i4 VectorShuffle(
      #|  <FixedArray:
      #|    [0, 17, 2, 19, 4, 21, 6, 23, 8, 25, 10, 27, 12, 29, 14, 31]>,
      #|) uses=[v5:any@early, v6:any@early] defs=[v8:any@late]
      #|  i5 VectorSwizzle uses=[v8:any@early, v7:any@early] defs=[v9:any@late]
      #|  i6 OutgoingReg(V128, p0:fpvec) uses=[v9:any@early]
      #|  i7 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects basic vector integer arithmetic" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_integer_arithmetic",
    Internal,
    [Ptr64, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let mut result = parameters[1]
  let lanes : Array[@semantic.VectorLane] = [I8x16, I16x8, I32x4, I64x2]
  for lane in lanes {
    result = builder.emit(Vector(IntUnary(lane, Absolute)), [result], [V128])[0]
    result = builder.emit(Vector(IntUnary(lane, Negate)), [result], [V128])[0]
    result = builder.emit(
        Vector(IntBinary(lane, Add)),
        [result, parameters[2]],
        [V128],
      )[0]
    result = builder.emit(
        Vector(IntBinary(lane, Sub)),
        [result, parameters[2]],
        [V128],
      )[0]
    result = builder.emit(
        Vector(IntBinary(lane, Mul)),
        [result, parameters[2]],
        [V128],
      )[0]
  }
  builder.return_([result])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_integer_arithmetic(v0:ptr64, v1:v128, v2:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v3:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any-location(prefer=p1:fpvec)@late]
      #|  i3 VectorIntUnary(I8x16, Absolute) uses=[v4:any@early] defs=[v6:any@late]
      #|  i4 VectorIntUnary(I8x16, Negate) uses=[v6:any@early] defs=[v7:any@late]
      #|  i5 VectorIntBinary(I8x16, Add) uses=[v7:any@early, v5:any@early] defs=[v8:any@late]
      #|  i6 VectorIntBinary(I8x16, Sub) uses=[v8:any@early, v5:any@early] defs=[v9:any@late]
      #|  i7 VectorIntBinary(I8x16, Mul) uses=[v9:any@early, v5:any@early] defs=[v10:any@late]
      #|  i8 VectorIntUnary(I16x8, Absolute) uses=[v10:any@early] defs=[v11:any@late]
      #|  i9 VectorIntUnary(I16x8, Negate) uses=[v11:any@early] defs=[v12:any@late]
      #|  i10 VectorIntBinary(I16x8, Add) uses=[v12:any@early, v5:any@early] defs=[v13:any@late]
      #|  i11 VectorIntBinary(I16x8, Sub) uses=[v13:any@early, v5:any@early] defs=[v14:any@late]
      #|  i12 VectorIntBinary(I16x8, Mul) uses=[v14:any@early, v5:any@early] defs=[v15:any@late]
      #|  i13 VectorIntUnary(I32x4, Absolute) uses=[v15:any@early] defs=[v16:any@late]
      #|  i14 VectorIntUnary(I32x4, Negate) uses=[v16:any@early] defs=[v17:any@late]
      #|  i15 VectorIntBinary(I32x4, Add) uses=[v17:any@early, v5:any@early] defs=[v18:any@late]
      #|  i16 VectorIntBinary(I32x4, Sub) uses=[v18:any@early, v5:any@early] defs=[v19:any@late]
      #|  i17 VectorIntBinary(I32x4, Mul) uses=[v19:any@early, v5:any@early] defs=[v20:any@late]
      #|  i18 VectorIntUnary(I64x2, Absolute) uses=[v20:any@early] defs=[v21:any@late]
      #|  i19 VectorIntUnary(I64x2, Negate) uses=[v21:any@early] defs=[v22:any@late]
      #|  i20 VectorIntBinary(I64x2, Add) uses=[v22:any@early, v5:any@early] defs=[v23:any@late]
      #|  i21 VectorIntBinary(I64x2, Sub) uses=[v23:any@early, v5:any@early] defs=[v24:any@late]
      #|  i22 VectorIntBinary(I64x2, Mul) uses=[v24:any@early, v5:any@early] defs=[v25:any@late]
      #|  i23 OutgoingReg(V128, p0:fpvec) uses=[v25:any@early]
      #|  i24 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects vector integer shifts" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_integer_shifts",
    Internal,
    [Ptr64, V128, I32],
    [V128],
  )
  let parameters = builder.parameters()
  let mut result = parameters[1]
  let lanes : Array[@semantic.VectorLane] = [I8x16, I16x8, I32x4, I64x2]
  for lane in lanes {
    result = builder.emit(
        Vector(IntShift(lane, Left)),
        [result, parameters[2]],
        [V128],
      )[0]
    result = builder.emit(
        Vector(IntShift(lane, Right(Signed))),
        [result, parameters[2]],
        [V128],
      )[0]
    result = builder.emit(
        Vector(IntShift(lane, Right(Unsigned))),
        [result, parameters[2]],
        [V128],
      )[0]
  }
  builder.return_([result])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_integer_shifts(v0:ptr64, v1:v128, v2:i32) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v3:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(I32, p6:int) uses=[v2:fixed(p6:int)@early] defs=[v5:any-location(prefer=p6:int)@late]
      #|  i3 VectorIntShift(I8x16, Left) uses=[v4:any@early, v5:any@early] defs=[v6:any@late]
      #|  i4 VectorIntShift(I8x16, Right(Signed)) uses=[v6:any@early, v5:any@early] defs=[v7:any@late]
      #|  i5 VectorIntShift(I8x16, Right(Unsigned)) uses=[v7:any@early, v5:any@early] defs=[v8:any@late]
      #|  i6 VectorIntShift(I16x8, Left) uses=[v8:any@early, v5:any@early] defs=[v9:any@late]
      #|  i7 VectorIntShift(I16x8, Right(Signed)) uses=[v9:any@early, v5:any@early] defs=[v10:any@late]
      #|  i8 VectorIntShift(I16x8, Right(Unsigned)) uses=[v10:any@early, v5:any@early] defs=[v11:any@late]
      #|  i9 VectorIntShift(I32x4, Left) uses=[v11:any@early, v5:any@early] defs=[v12:any@late]
      #|  i10 VectorIntShift(I32x4, Right(Signed)) uses=[v12:any@early, v5:any@early] defs=[v13:any@late]
      #|  i11 VectorIntShift(I32x4, Right(Unsigned)) uses=[v13:any@early, v5:any@early] defs=[v14:any@late]
      #|  i12 VectorIntShift(I64x2, Left) uses=[v14:any@early, v5:any@early] defs=[v15:any@late]
      #|  i13 VectorIntShift(I64x2, Right(Signed)) uses=[v15:any@early, v5:any@early] defs=[v16:any@late]
      #|  i14 VectorIntShift(I64x2, Right(Unsigned)) uses=[v16:any@early, v5:any@early] defs=[v17:any@late]
      #|  i15 OutgoingReg(V128, p0:fpvec) uses=[v17:any@early]
      #|  i16 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects vector integer comparisons" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_integer_comparisons",
    Internal,
    [Ptr64, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let mut result = parameters[1]
  let lanes : Array[@semantic.VectorLane] = [I8x16, I16x8, I32x4, I64x2]
  let comparisons : Array[@semantic.VectorIntComparison] = [
    Equal,
    NotEqual,
    LessThan(Signed),
    LessThan(Unsigned),
    LessOrEqual(Signed),
    LessOrEqual(Unsigned),
    GreaterThan(Signed),
    GreaterThan(Unsigned),
    GreaterOrEqual(Signed),
    GreaterOrEqual(Unsigned),
  ]
  for lane in lanes {
    for comparison in comparisons {
      result = builder.emit(
          Vector(IntCompare(lane, comparison)),
          [result, parameters[2]],
          [V128],
        )[0]
    }
  }
  builder.return_([result])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_integer_comparisons(v0:ptr64, v1:v128, v2:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v3:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any-location(prefer=p1:fpvec)@late]
      #|  i3 VectorIntCompare(I8x16, Equal) uses=[v4:any@early, v5:any@early] defs=[v6:any@late]
      #|  i4 VectorIntCompare(I8x16, NotEqual) uses=[v6:any@early, v5:any@early] defs=[v7:any@late]
      #|  i5 VectorIntCompare(I8x16, LessThan(Signed)) uses=[v7:any@early, v5:any@early] defs=[v8:any@late]
      #|  i6 VectorIntCompare(I8x16, LessThan(Unsigned)) uses=[v8:any@early, v5:any@early] defs=[v9:any@late]
      #|  i7 VectorIntCompare(I8x16, LessOrEqual(Signed)) uses=[v9:any@early, v5:any@early] defs=[v10:any@late]
      #|  i8 VectorIntCompare(I8x16, LessOrEqual(Unsigned)) uses=[v10:any@early, v5:any@early] defs=[v11:any@late]
      #|  i9 VectorIntCompare(I8x16, GreaterThan(Signed)) uses=[v11:any@early, v5:any@early] defs=[v12:any@late]
      #|  i10 VectorIntCompare(I8x16, GreaterThan(Unsigned)) uses=[v12:any@early, v5:any@early] defs=[v13:any@late]
      #|  i11 VectorIntCompare(I8x16, GreaterOrEqual(Signed)) uses=[v13:any@early, v5:any@early] defs=[v14:any@late]
      #|  i12 VectorIntCompare(I8x16, GreaterOrEqual(Unsigned)) uses=[v14:any@early, v5:any@early] defs=[v15:any@late]
      #|  i13 VectorIntCompare(I16x8, Equal) uses=[v15:any@early, v5:any@early] defs=[v16:any@late]
      #|  i14 VectorIntCompare(I16x8, NotEqual) uses=[v16:any@early, v5:any@early] defs=[v17:any@late]
      #|  i15 VectorIntCompare(I16x8, LessThan(Signed)) uses=[v17:any@early, v5:any@early] defs=[v18:any@late]
      #|  i16 VectorIntCompare(I16x8, LessThan(Unsigned)) uses=[v18:any@early, v5:any@early] defs=[v19:any@late]
      #|  i17 VectorIntCompare(I16x8, LessOrEqual(Signed)) uses=[v19:any@early, v5:any@early] defs=[v20:any@late]
      #|  i18 VectorIntCompare(I16x8, LessOrEqual(Unsigned)) uses=[v20:any@early, v5:any@early] defs=[v21:any@late]
      #|  i19 VectorIntCompare(I16x8, GreaterThan(Signed)) uses=[v21:any@early, v5:any@early] defs=[v22:any@late]
      #|  i20 VectorIntCompare(I16x8, GreaterThan(Unsigned)) uses=[v22:any@early, v5:any@early] defs=[v23:any@late]
      #|  i21 VectorIntCompare(I16x8, GreaterOrEqual(Signed)) uses=[v23:any@early, v5:any@early] defs=[v24:any@late]
      #|  i22 VectorIntCompare(I16x8, GreaterOrEqual(Unsigned)) uses=[v24:any@early, v5:any@early] defs=[v25:any@late]
      #|  i23 VectorIntCompare(I32x4, Equal) uses=[v25:any@early, v5:any@early] defs=[v26:any@late]
      #|  i24 VectorIntCompare(I32x4, NotEqual) uses=[v26:any@early, v5:any@early] defs=[v27:any@late]
      #|  i25 VectorIntCompare(I32x4, LessThan(Signed)) uses=[v27:any@early, v5:any@early] defs=[v28:any@late]
      #|  i26 VectorIntCompare(I32x4, LessThan(Unsigned)) uses=[v28:any@early, v5:any@early] defs=[v29:any@late]
      #|  i27 VectorIntCompare(I32x4, LessOrEqual(Signed)) uses=[v29:any@early, v5:any@early] defs=[v30:any@late]
      #|  i28 VectorIntCompare(I32x4, LessOrEqual(Unsigned)) uses=[v30:any@early, v5:any@early] defs=[v31:any@late]
      #|  i29 VectorIntCompare(I32x4, GreaterThan(Signed)) uses=[v31:any@early, v5:any@early] defs=[v32:any@late]
      #|  i30 VectorIntCompare(I32x4, GreaterThan(Unsigned)) uses=[v32:any@early, v5:any@early] defs=[v33:any@late]
      #|  i31 VectorIntCompare(I32x4, GreaterOrEqual(Signed)) uses=[v33:any@early, v5:any@early] defs=[v34:any@late]
      #|  i32 VectorIntCompare(I32x4, GreaterOrEqual(Unsigned)) uses=[v34:any@early, v5:any@early] defs=[v35:any@late]
      #|  i33 VectorIntCompare(I64x2, Equal) uses=[v35:any@early, v5:any@early] defs=[v36:any@late]
      #|  i34 VectorIntCompare(I64x2, NotEqual) uses=[v36:any@early, v5:any@early] defs=[v37:any@late]
      #|  i35 VectorIntCompare(I64x2, LessThan(Signed)) uses=[v37:any@early, v5:any@early] defs=[v38:any@late]
      #|  i36 VectorIntCompare(I64x2, LessThan(Unsigned)) uses=[v38:any@early, v5:any@early] defs=[v39:any@late]
      #|  i37 VectorIntCompare(I64x2, LessOrEqual(Signed)) uses=[v39:any@early, v5:any@early] defs=[v40:any@late]
      #|  i38 VectorIntCompare(I64x2, LessOrEqual(Unsigned)) uses=[v40:any@early, v5:any@early] defs=[v41:any@late]
      #|  i39 VectorIntCompare(I64x2, GreaterThan(Signed)) uses=[v41:any@early, v5:any@early] defs=[v42:any@late]
      #|  i40 VectorIntCompare(I64x2, GreaterThan(Unsigned)) uses=[v42:any@early, v5:any@early] defs=[v43:any@late]
      #|  i41 VectorIntCompare(I64x2, GreaterOrEqual(Signed)) uses=[v43:any@early, v5:any@early] defs=[v44:any@late]
      #|  i42 VectorIntCompare(I64x2, GreaterOrEqual(Unsigned)) uses=[v44:any@early, v5:any@early] defs=[v45:any@late]
      #|  i43 OutgoingReg(V128, p0:fpvec) uses=[v45:any@early]
      #|  i44 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects saturating vector integer arithmetic" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_saturating_arithmetic",
    Internal,
    [Ptr64, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let mut result = parameters[1]
  let lanes : Array[@semantic.VectorLane] = [I8x16, I16x8, I32x4, I64x2]
  let operations : Array[@semantic.VectorIntBinaryOp] = [
    SaturatingAdd(Signed),
    SaturatingAdd(Unsigned),
    SaturatingSub(Signed),
    SaturatingSub(Unsigned),
  ]
  for lane in lanes {
    for operation in operations {
      result = builder.emit(
          Vector(IntBinary(lane, operation)),
          [result, parameters[2]],
          [V128],
        )[0]
    }
  }
  builder.return_([result])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_saturating_arithmetic(v0:ptr64, v1:v128, v2:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v3:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any-location(prefer=p1:fpvec)@late]
      #|  i3 VectorIntBinary(I8x16, SaturatingAdd(Signed)) uses=[v4:any@early, v5:any@early] defs=[v6:any@late]
      #|  i4 VectorIntBinary(I8x16, SaturatingAdd(Unsigned)) uses=[v6:any@early, v5:any@early] defs=[v7:any@late]
      #|  i5 VectorIntBinary(I8x16, SaturatingSub(Signed)) uses=[v7:any@early, v5:any@early] defs=[v8:any@late]
      #|  i6 VectorIntBinary(I8x16, SaturatingSub(Unsigned)) uses=[v8:any@early, v5:any@early] defs=[v9:any@late]
      #|  i7 VectorIntBinary(I16x8, SaturatingAdd(Signed)) uses=[v9:any@early, v5:any@early] defs=[v10:any@late]
      #|  i8 VectorIntBinary(I16x8, SaturatingAdd(Unsigned)) uses=[v10:any@early, v5:any@early] defs=[v11:any@late]
      #|  i9 VectorIntBinary(I16x8, SaturatingSub(Signed)) uses=[v11:any@early, v5:any@early] defs=[v12:any@late]
      #|  i10 VectorIntBinary(I16x8, SaturatingSub(Unsigned)) uses=[v12:any@early, v5:any@early] defs=[v13:any@late]
      #|  i11 VectorIntBinary(I32x4, SaturatingAdd(Signed)) uses=[v13:any@early, v5:any@early] defs=[v14:any@late]
      #|  i12 VectorIntBinary(I32x4, SaturatingAdd(Unsigned)) uses=[v14:any@early, v5:any@early] defs=[v15:any@late]
      #|  i13 VectorIntBinary(I32x4, SaturatingSub(Signed)) uses=[v15:any@early, v5:any@early] defs=[v16:any@late]
      #|  i14 VectorIntBinary(I32x4, SaturatingSub(Unsigned)) uses=[v16:any@early, v5:any@early] defs=[v17:any@late]
      #|  i15 VectorIntBinary(I64x2, SaturatingAdd(Signed)) uses=[v17:any@early, v5:any@early] defs=[v18:any@late]
      #|  i16 VectorIntBinary(I64x2, SaturatingAdd(Unsigned)) uses=[v18:any@early, v5:any@early] defs=[v19:any@late]
      #|  i17 VectorIntBinary(I64x2, SaturatingSub(Signed)) uses=[v19:any@early, v5:any@early] defs=[v20:any@late]
      #|  i18 VectorIntBinary(I64x2, SaturatingSub(Unsigned)) uses=[v20:any@early, v5:any@early] defs=[v21:any@late]
      #|  i19 OutgoingReg(V128, p0:fpvec) uses=[v21:any@early]
      #|  i20 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects vector integer min and max" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_integer_min_max",
    Internal,
    [Ptr64, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let mut result = parameters[1]
  let lanes : Array[@semantic.VectorLane] = [I8x16, I16x8, I32x4, I64x2]
  let operations : Array[@semantic.VectorIntBinaryOp] = [
    Min(Signed),
    Min(Unsigned),
    Max(Signed),
    Max(Unsigned),
  ]
  for lane in lanes {
    for operation in operations {
      result = builder.emit(
          Vector(IntBinary(lane, operation)),
          [result, parameters[2]],
          [V128],
        )[0]
    }
  }
  builder.return_([result])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_integer_min_max(v0:ptr64, v1:v128, v2:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v3:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any-location(prefer=p1:fpvec)@late]
      #|  i3 VectorIntBinary(I8x16, Min(Signed)) uses=[v4:any@early, v5:any@early] defs=[v6:any@late]
      #|  i4 VectorIntBinary(I8x16, Min(Unsigned)) uses=[v6:any@early, v5:any@early] defs=[v7:any@late]
      #|  i5 VectorIntBinary(I8x16, Max(Signed)) uses=[v7:any@early, v5:any@early] defs=[v8:any@late]
      #|  i6 VectorIntBinary(I8x16, Max(Unsigned)) uses=[v8:any@early, v5:any@early] defs=[v9:any@late]
      #|  i7 VectorIntBinary(I16x8, Min(Signed)) uses=[v9:any@early, v5:any@early] defs=[v10:any@late]
      #|  i8 VectorIntBinary(I16x8, Min(Unsigned)) uses=[v10:any@early, v5:any@early] defs=[v11:any@late]
      #|  i9 VectorIntBinary(I16x8, Max(Signed)) uses=[v11:any@early, v5:any@early] defs=[v12:any@late]
      #|  i10 VectorIntBinary(I16x8, Max(Unsigned)) uses=[v12:any@early, v5:any@early] defs=[v13:any@late]
      #|  i11 VectorIntBinary(I32x4, Min(Signed)) uses=[v13:any@early, v5:any@early] defs=[v14:any@late]
      #|  i12 VectorIntBinary(I32x4, Min(Unsigned)) uses=[v14:any@early, v5:any@early] defs=[v15:any@late]
      #|  i13 VectorIntBinary(I32x4, Max(Signed)) uses=[v15:any@early, v5:any@early] defs=[v16:any@late]
      #|  i14 VectorIntBinary(I32x4, Max(Unsigned)) uses=[v16:any@early, v5:any@early] defs=[v17:any@late]
      #|  i15 VectorIntBinary(I64x2, Min(Signed)) uses=[v17:any@early, v5:any@early] defs=[v18:any@late]
      #|  i16 VectorIntBinary(I64x2, Min(Unsigned)) uses=[v18:any@early, v5:any@early] defs=[v19:any@late]
      #|  i17 VectorIntBinary(I64x2, Max(Signed)) uses=[v19:any@early, v5:any@early] defs=[v20:any@late]
      #|  i18 VectorIntBinary(I64x2, Max(Unsigned)) uses=[v20:any@early, v5:any@early] defs=[v21:any@late]
      #|  i19 OutgoingReg(V128, p0:fpvec) uses=[v21:any@early]
      #|  i20 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects legal vector unsigned averages" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_unsigned_average",
    Internal,
    [Ptr64, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let bytes = builder.emit(
      Vector(IntBinary(I8x16, AverageUnsigned)),
      [parameters[1], parameters[2]],
      [V128],
    )[0]
  let halfwords = builder.emit(
      Vector(IntBinary(I16x8, AverageUnsigned)),
      [bytes, parameters[2]],
      [V128],
    )[0]
  builder.return_([halfwords])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_unsigned_average(v0:ptr64, v1:v128, v2:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v3:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any-location(prefer=p1:fpvec)@late]
      #|  i3 VectorIntBinary(I8x16, AverageUnsigned) uses=[v4:any@early, v5:any@early] defs=[v6:any@late]
      #|  i4 VectorIntBinary(I16x8, AverageUnsigned) uses=[v6:any@early, v5:any@early] defs=[v7:any@late]
      #|  i5 OutgoingReg(V128, p0:fpvec) uses=[v7:any@early]
      #|  i6 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects vector byte population count" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_population_count",
    Internal,
    [Ptr64, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let result = builder.emit(
      Vector(IntUnary(I8x16, PopulationCount)),
      [parameters[1]],
      [V128],
    )[0]
  builder.return_([result])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_population_count(v0:ptr64, v1:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v2:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v3:any-location(prefer=p0:fpvec)@late]
      #|  i2 VectorIntUnary(I8x16, PopulationCount) uses=[v3:any@early] defs=[v4:any@late]
      #|  i3 OutgoingReg(V128, p0:fpvec) uses=[v4:any@early]
      #|  i4 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects widening vector integer arithmetic" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_widening_arithmetic",
    Internal,
    [Ptr64, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let mut result = parameters[1]
  let lanes : Array[@semantic.VectorLane] = [I16x8, I32x4, I64x2]
  let signednesses : Array[@native.Signedness] = [Signed, Unsigned]
  for lane in lanes {
    for signedness in signednesses {
      result = builder.emit(
          Vector(IntUnary(lane, ExtendAddPairwise(signedness))),
          [result],
          [V128],
        )[0]
    }
  }
  let halves : Array[@semantic.VectorHalf] = [Low, High]
  for lane in lanes {
    for half in halves {
      for signedness in signednesses {
        result = builder.emit(
            Vector(IntBinary(lane, ExtendMultiply(half, signedness))),
            [result, parameters[2]],
            [V128],
          )[0]
      }
    }
  }
  result = builder.emit(
      Vector(IntBinary(I32x4, Dot16To32Signed)),
      [result, parameters[2]],
      [V128],
    )[0]
  result = builder.emit(
      Vector(IntBinary(I16x8, Q15MultiplyRoundedSaturating)),
      [result, parameters[2]],
      [V128],
    )[0]
  builder.return_([result])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_widening_arithmetic(v0:ptr64, v1:v128, v2:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v3:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any-location(prefer=p1:fpvec)@late]
      #|  i3 VectorIntUnary(I16x8, ExtendAddPairwise(Signed)) uses=[v4:any@early] defs=[v6:any@late]
      #|  i4 VectorIntUnary(I16x8, ExtendAddPairwise(Unsigned)) uses=[v6:any@early] defs=[v7:any@late]
      #|  i5 VectorIntUnary(I32x4, ExtendAddPairwise(Signed)) uses=[v7:any@early] defs=[v8:any@late]
      #|  i6 VectorIntUnary(I32x4, ExtendAddPairwise(Unsigned)) uses=[v8:any@early] defs=[v9:any@late]
      #|  i7 VectorIntUnary(I64x2, ExtendAddPairwise(Signed)) uses=[v9:any@early] defs=[v10:any@late]
      #|  i8 VectorIntUnary(I64x2, ExtendAddPairwise(Unsigned)) uses=[v10:any@early] defs=[v11:any@late]
      #|  i9 VectorIntBinary(I16x8, ExtendMultiply(Low, Signed)) uses=[v11:any@early, v5:any@early] defs=[v12:any@late]
      #|  i10 VectorIntBinary(I16x8, ExtendMultiply(Low, Unsigned)) uses=[v12:any@early, v5:any@early] defs=[v13:any@late]
      #|  i11 VectorIntBinary(I16x8, ExtendMultiply(High, Signed)) uses=[v13:any@early, v5:any@early] defs=[v14:any@late]
      #|  i12 VectorIntBinary(I16x8, ExtendMultiply(High, Unsigned)) uses=[v14:any@early, v5:any@early] defs=[v15:any@late]
      #|  i13 VectorIntBinary(I32x4, ExtendMultiply(Low, Signed)) uses=[v15:any@early, v5:any@early] defs=[v16:any@late]
      #|  i14 VectorIntBinary(I32x4, ExtendMultiply(Low, Unsigned)) uses=[v16:any@early, v5:any@early] defs=[v17:any@late]
      #|  i15 VectorIntBinary(I32x4, ExtendMultiply(High, Signed)) uses=[v17:any@early, v5:any@early] defs=[v18:any@late]
      #|  i16 VectorIntBinary(I32x4, ExtendMultiply(High, Unsigned)) uses=[v18:any@early, v5:any@early] defs=[v19:any@late]
      #|  i17 VectorIntBinary(I64x2, ExtendMultiply(Low, Signed)) uses=[v19:any@early, v5:any@early] defs=[v20:any@late]
      #|  i18 VectorIntBinary(I64x2, ExtendMultiply(Low, Unsigned)) uses=[v20:any@early, v5:any@early] defs=[v21:any@late]
      #|  i19 VectorIntBinary(I64x2, ExtendMultiply(High, Signed)) uses=[v21:any@early, v5:any@early] defs=[v22:any@late]
      #|  i20 VectorIntBinary(I64x2, ExtendMultiply(High, Unsigned)) uses=[v22:any@early, v5:any@early] defs=[v23:any@late]
      #|  i21 VectorIntBinary(I32x4, Dot16To32Signed) uses=[v23:any@early, v5:any@early] defs=[v24:any@late]
      #|  i22 VectorIntBinary(I16x8, Q15MultiplyRoundedSaturating) uses=[v24:any@early, v5:any@early] defs=[v25:any@late]
      #|  i23 OutgoingReg(V128, p0:fpvec) uses=[v25:any@early]
      #|  i24 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects vector integer extension" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_integer_extension",
    Internal,
    [Ptr64, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let mut result = parameters[1]
  let lanes : Array[@semantic.VectorLane] = [I16x8, I32x4, I64x2]
  let halves : Array[@semantic.VectorHalf] = [Low, High]
  let signednesses : Array[@native.Signedness] = [Signed, Unsigned]
  for lane in lanes {
    for half in halves {
      for signedness in signednesses {
        let conversion = match half {
          Low => @semantic.VectorConversionOp::ExtendLow(lane, signedness)
          High => ExtendHigh(lane, signedness)
        }
        result = builder.emit(Vector(Convert(conversion)), [result], [V128])[0]
      }
    }
  }
  builder.return_([result])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_integer_extension(v0:ptr64, v1:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v2:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v3:any-location(prefer=p0:fpvec)@late]
      #|  i2 VectorConvert(ExtendLow(I16x8, Signed)) uses=[v3:any@early] defs=[v4:any@late]
      #|  i3 VectorConvert(ExtendLow(I16x8, Unsigned)) uses=[v4:any@early] defs=[v5:any@late]
      #|  i4 VectorConvert(ExtendHigh(I16x8, Signed)) uses=[v5:any@early] defs=[v6:any@late]
      #|  i5 VectorConvert(ExtendHigh(I16x8, Unsigned)) uses=[v6:any@early] defs=[v7:any@late]
      #|  i6 VectorConvert(ExtendLow(I32x4, Signed)) uses=[v7:any@early] defs=[v8:any@late]
      #|  i7 VectorConvert(ExtendLow(I32x4, Unsigned)) uses=[v8:any@early] defs=[v9:any@late]
      #|  i8 VectorConvert(ExtendHigh(I32x4, Signed)) uses=[v9:any@early] defs=[v10:any@late]
      #|  i9 VectorConvert(ExtendHigh(I32x4, Unsigned)) uses=[v10:any@early] defs=[v11:any@late]
      #|  i10 VectorConvert(ExtendLow(I64x2, Signed)) uses=[v11:any@early] defs=[v12:any@late]
      #|  i11 VectorConvert(ExtendLow(I64x2, Unsigned)) uses=[v12:any@early] defs=[v13:any@late]
      #|  i12 VectorConvert(ExtendHigh(I64x2, Signed)) uses=[v13:any@early] defs=[v14:any@late]
      #|  i13 VectorConvert(ExtendHigh(I64x2, Unsigned)) uses=[v14:any@early] defs=[v15:any@late]
      #|  i14 OutgoingReg(V128, p0:fpvec) uses=[v15:any@early]
      #|  i15 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects saturating vector narrowing" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_narrowing",
    Internal,
    [Ptr64, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let mut result = parameters[1]
  let lanes : Array[@semantic.VectorLane] = [I8x16, I16x8]
  let signednesses : Array[@native.Signedness] = [Signed, Unsigned]
  for lane in lanes {
    for signedness in signednesses {
      result = builder.emit(
          Vector(Convert(Narrow(lane, signedness))),
          [result, parameters[2]],
          [V128],
        )[0]
    }
  }
  builder.return_([result])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_narrowing(v0:ptr64, v1:v128, v2:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v3:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any-location(prefer=p1:fpvec)@late]
      #|  i3 VectorConvert(Narrow(I8x16, Signed)) uses=[v4:any@early, v5:any@early] defs=[v6:any@late]
      #|  i4 VectorConvert(Narrow(I8x16, Unsigned)) uses=[v6:any@early, v5:any@early] defs=[v7:any@late]
      #|  i5 VectorConvert(Narrow(I16x8, Signed)) uses=[v7:any@early, v5:any@early] defs=[v8:any@late]
      #|  i6 VectorConvert(Narrow(I16x8, Unsigned)) uses=[v8:any@early, v5:any@early] defs=[v9:any@late]
      #|  i7 OutgoingReg(V128, p0:fpvec) uses=[v9:any@early]
      #|  i8 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects vector truth predicates" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_truth_predicates",
    Internal,
    [Ptr64, V128],
    [I32, I32, I32, I32, I32],
  )
  let source = builder.parameters()[1]
  let results = [builder.emit(Vector(Predicate(AnyTrue)), [source], [I32])[0]]
  let mut result = builder.emit(Vector(Predicate(AllTrue(I8x16))), [source], [
      I32,
    ])[0]
  results.push(result)
  let lanes : Array[@semantic.VectorLane] = [I16x8, I32x4, I64x2]
  for lane in lanes {
    result = builder.emit(Vector(Predicate(AllTrue(lane))), [source], [I32])[0]
    results.push(result)
  }
  builder.return_(results)
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_truth_predicates(v0:ptr64, v1:v128) -> (i32, i32, i32, i32, i32)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v2:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v3:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingResultArea(p10:int) defs=[v4:any-location@late]
      #|  i3 VectorPredicate(AnyTrue) uses=[v3:any@early] defs=[v5:any@late]
      #|  i4 VectorPredicate(AllTrue(I8x16)) uses=[v3:any@early] defs=[v6:any@late]
      #|  i5 VectorPredicate(AllTrue(I16x8)) uses=[v3:any@early] defs=[v7:any@late]
      #|  i6 VectorPredicate(AllTrue(I32x4)) uses=[v3:any@early] defs=[v8:any@late]
      #|  i7 VectorPredicate(AllTrue(I64x2)) uses=[v3:any@early] defs=[v9:any@late]
      #|  i8 OutgoingReg(I32, p0:int) uses=[v5:any@early]
      #|  i9 OutgoingReg(I32, p2:int) uses=[v6:any@early]
      #|  i10 OutgoingAreaResult(I32, 0) uses=[v4:any@early, v7:any@early]
      #|  i11 OutgoingAreaResult(I32, 8) uses=[v4:any@early, v8:any@early]
      #|  i12 OutgoingAreaResult(I32, 16) uses=[v4:any@early, v9:any@early]
      #|  i13 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects vector integer bitmasks" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_integer_bitmasks",
    Internal,
    [Ptr64, V128],
    [I32, I32, I32, I32],
  )
  let source = builder.parameters()[1]
  let lanes : Array[@semantic.VectorLane] = [I8x16, I16x8, I32x4, I64x2]
  let results = lanes.map(lane => {
    builder.emit(Vector(Predicate(BitMask(lane))), [source], [I32])[0]
  })
  builder.return_(results)
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_integer_bitmasks(v0:ptr64, v1:v128) -> (i32, i32, i32, i32)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v2:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v3:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingResultArea(p10:int) defs=[v4:any-location@late]
      #|  i3 VectorPredicate(BitMask(I8x16)) uses=[v3:any@early] defs=[v5:any@late]
      #|  i4 VectorPredicate(BitMask(I16x8)) uses=[v3:any@early] defs=[v6:any@late]
      #|  i5 VectorPredicate(BitMask(I32x4)) uses=[v3:any@early] defs=[v7:any@late]
      #|  i6 VectorPredicate(BitMask(I64x2)) uses=[v3:any@early] defs=[v8:any@late]
      #|  i7 OutgoingReg(I32, p0:int) uses=[v5:any@early]
      #|  i8 OutgoingReg(I32, p2:int) uses=[v6:any@early]
      #|  i9 OutgoingAreaResult(I32, 0) uses=[v4:any@early, v7:any@early]
      #|  i10 OutgoingAreaResult(I32, 8) uses=[v4:any@early, v8:any@early]
      #|  i11 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects every non-fused vector float operation" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_float_operations",
    Internal,
    [Ptr64, V128, V128],
    [V128, V128, V128, V128],
  )
  let parameters = builder.parameters()
  let unary_operations : Array[@semantic.VectorFloatUnaryOp] = [
    Absolute,
    Negate,
    SquareRoot,
    Ceil,
    Floor,
    Truncate,
    Nearest,
  ]
  let binary_operations : Array[@semantic.VectorFloatBinaryOp] = [
    Add,
    Sub,
    Mul,
    Div,
    Min,
    Max,
    PseudoMin,
    PseudoMax,
  ]
  let comparisons : Array[@semantic.VectorFloatComparison] = [
    Equal,
    NotEqual,
    LessThan,
    LessOrEqual,
    GreaterThan,
    GreaterOrEqual,
  ]
  let results : Array[@semantic.Value] = []
  let lanes : Array[@semantic.VectorLane] = [F32x4, F64x2]
  for lane in lanes {
    let mut value = parameters[1]
    for operation in unary_operations {
      value = builder.emit(Vector(FloatUnary(lane, operation)), [value], [V128])[0]
    }
    for operation in binary_operations {
      value = builder.emit(
          Vector(FloatBinary(lane, operation)),
          [value, parameters[2]],
          [V128],
        )[0]
    }
    results.push(value)
    let mut comparison = parameters[1]
    for operation in comparisons {
      comparison = builder.emit(
          Vector(FloatCompare(lane, operation)),
          [comparison, parameters[2]],
          [V128],
        )[0]
    }
    results.push(comparison)
  }
  builder.return_(results)
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_float_operations(v0:ptr64, v1:v128, v2:v128) -> (v128, v128, v128, v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v3:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any-location(prefer=p1:fpvec)@late]
      #|  i3 IncomingResultArea(p10:int) defs=[v6:any-location@late]
      #|  i4 VectorFloatUnary(F32x4, Absolute) uses=[v4:any@early] defs=[v7:any@late]
      #|  i5 VectorFloatUnary(F32x4, Negate) uses=[v7:any@early] defs=[v8:any@late]
      #|  i6 VectorFloatUnary(F32x4, SquareRoot) uses=[v8:any@early] defs=[v9:any@late]
      #|  i7 VectorFloatUnary(F32x4, Ceil) uses=[v9:any@early] defs=[v10:any@late]
      #|  i8 VectorFloatUnary(F32x4, Floor) uses=[v10:any@early] defs=[v11:any@late]
      #|  i9 VectorFloatUnary(F32x4, Truncate) uses=[v11:any@early] defs=[v12:any@late]
      #|  i10 VectorFloatUnary(F32x4, Nearest) uses=[v12:any@early] defs=[v13:any@late]
      #|  i11 VectorFloatBinary(F32x4, Add) uses=[v13:any@early, v5:any@early] defs=[v14:any@late]
      #|  i12 VectorFloatBinary(F32x4, Sub) uses=[v14:any@early, v5:any@early] defs=[v15:any@late]
      #|  i13 VectorFloatBinary(F32x4, Mul) uses=[v15:any@early, v5:any@early] defs=[v16:any@late]
      #|  i14 VectorFloatBinary(F32x4, Div) uses=[v16:any@early, v5:any@early] defs=[v17:any@late]
      #|  i15 VectorFloatBinary(F32x4, Min) uses=[v17:any@early, v5:any@early] defs=[v18:any@late]
      #|  i16 VectorFloatBinary(F32x4, Max) uses=[v18:any@early, v5:any@early] defs=[v19:any@late]
      #|  i17 VectorFloatBinary(F32x4, PseudoMin) uses=[v19:any@early, v5:any@early] defs=[v20:any@late]
      #|  i18 VectorFloatBinary(F32x4, PseudoMax) uses=[v20:any@early, v5:any@early] defs=[v21:any@late]
      #|  i19 VectorFloatCompare(F32x4, Equal) uses=[v4:any@early, v5:any@early] defs=[v22:any@late]
      #|  i20 VectorFloatCompare(F32x4, NotEqual) uses=[v22:any@early, v5:any@early] defs=[v23:any@late]
      #|  i21 VectorFloatCompare(F32x4, LessThan) uses=[v23:any@early, v5:any@early] defs=[v24:any@late]
      #|  i22 VectorFloatCompare(F32x4, LessOrEqual) uses=[v24:any@early, v5:any@early] defs=[v25:any@late]
      #|  i23 VectorFloatCompare(F32x4, GreaterThan) uses=[v25:any@early, v5:any@early] defs=[v26:any@late]
      #|  i24 VectorFloatCompare(F32x4, GreaterOrEqual) uses=[v26:any@early, v5:any@early] defs=[v27:any@late]
      #|  i25 VectorFloatUnary(F64x2, Absolute) uses=[v4:any@early] defs=[v28:any@late]
      #|  i26 VectorFloatUnary(F64x2, Negate) uses=[v28:any@early] defs=[v29:any@late]
      #|  i27 VectorFloatUnary(F64x2, SquareRoot) uses=[v29:any@early] defs=[v30:any@late]
      #|  i28 VectorFloatUnary(F64x2, Ceil) uses=[v30:any@early] defs=[v31:any@late]
      #|  i29 VectorFloatUnary(F64x2, Floor) uses=[v31:any@early] defs=[v32:any@late]
      #|  i30 VectorFloatUnary(F64x2, Truncate) uses=[v32:any@early] defs=[v33:any@late]
      #|  i31 VectorFloatUnary(F64x2, Nearest) uses=[v33:any@early] defs=[v34:any@late]
      #|  i32 VectorFloatBinary(F64x2, Add) uses=[v34:any@early, v5:any@early] defs=[v35:any@late]
      #|  i33 VectorFloatBinary(F64x2, Sub) uses=[v35:any@early, v5:any@early] defs=[v36:any@late]
      #|  i34 VectorFloatBinary(F64x2, Mul) uses=[v36:any@early, v5:any@early] defs=[v37:any@late]
      #|  i35 VectorFloatBinary(F64x2, Div) uses=[v37:any@early, v5:any@early] defs=[v38:any@late]
      #|  i36 VectorFloatBinary(F64x2, Min) uses=[v38:any@early, v5:any@early] defs=[v39:any@late]
      #|  i37 VectorFloatBinary(F64x2, Max) uses=[v39:any@early, v5:any@early] defs=[v40:any@late]
      #|  i38 VectorFloatBinary(F64x2, PseudoMin) uses=[v40:any@early, v5:any@early] defs=[v41:any@late]
      #|  i39 VectorFloatBinary(F64x2, PseudoMax) uses=[v41:any@early, v5:any@early] defs=[v42:any@late]
      #|  i40 VectorFloatCompare(F64x2, Equal) uses=[v4:any@early, v5:any@early] defs=[v43:any@late]
      #|  i41 VectorFloatCompare(F64x2, NotEqual) uses=[v43:any@early, v5:any@early] defs=[v44:any@late]
      #|  i42 VectorFloatCompare(F64x2, LessThan) uses=[v44:any@early, v5:any@early] defs=[v45:any@late]
      #|  i43 VectorFloatCompare(F64x2, LessOrEqual) uses=[v45:any@early, v5:any@early] defs=[v46:any@late]
      #|  i44 VectorFloatCompare(F64x2, GreaterThan) uses=[v46:any@early, v5:any@early] defs=[v47:any@late]
      #|  i45 VectorFloatCompare(F64x2, GreaterOrEqual) uses=[v47:any@early, v5:any@early] defs=[v48:any@late]
      #|  i46 OutgoingReg(V128, p0:fpvec) uses=[v21:any@early]
      #|  i47 OutgoingReg(V128, p1:fpvec) uses=[v27:any@early]
      #|  i48 OutgoingAreaResult(V128, 0) uses=[v6:any@early, v42:any@early]
      #|  i49 OutgoingAreaResult(V128, 16) uses=[v6:any@early, v48:any@early]
      #|  i50 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects vector fused operations and relaxed producers" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_float_fused",
    Internal,
    [Ptr64, V128, V128, V128],
    [V128, V128],
  )
  let parameters = builder.parameters()
  let operations : Array[@semantic.FloatTernaryOp] = [
    FusedMultiplyAdd,
    FusedNegatedMultiplyAdd,
    FusedMultiplySubtract,
    FusedNegatedMultiplySubtract,
  ]
  let mut direct = parameters[3]
  let mut relaxed = parameters[3]
  for operation in operations {
    direct = builder.emit(
        Vector(FloatTernary(F32x4, operation)),
        [parameters[1], parameters[2], direct],
        [V128],
      )[0]
    relaxed = builder.emit(
        Vector(Relaxed(FusedMultiplyAdd(F64x2, operation))),
        [parameters[1], parameters[2], relaxed],
        [V128],
      )[0]
  }
  builder.return_([direct, relaxed])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_float_fused(v0:ptr64, v1:v128, v2:v128, v3:v128) -> (v128, v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v4:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v5:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v6:any-location(prefer=p1:fpvec)@late]
      #|  i3 IncomingReg(V128, p2:fpvec) uses=[v3:fixed(p2:fpvec)@early] defs=[v7:any-location(prefer=p2:fpvec)@late]
      #|  i4 VectorFloatTernary(F32x4, FusedMultiplyAdd) uses=[v5:any@early, v6:any@early, v7:any@early] defs=[v8:any@late]
      #|  i5 VectorFloatTernary(F64x2, FusedMultiplyAdd) uses=[v5:any@early, v6:any@early, v7:any@early] defs=[v9:any@late]
      #|  i6 VectorFloatTernary(F32x4, FusedNegatedMultiplyAdd) uses=[v5:any@early, v6:any@early, v8:any@early] defs=[v10:any@late]
      #|  i7 VectorFloatTernary(F64x2, FusedNegatedMultiplyAdd) uses=[v5:any@early, v6:any@early, v9:any@early] defs=[v11:any@late]
      #|  i8 VectorFloatTernary(F32x4, FusedMultiplySubtract) uses=[v5:any@early, v6:any@early, v10:any@early] defs=[v12:any@late]
      #|  i9 VectorFloatTernary(F64x2, FusedMultiplySubtract) uses=[v5:any@early, v6:any@early, v11:any@early] defs=[v13:any@late]
      #|  i10 VectorFloatTernary(F32x4, FusedNegatedMultiplySubtract) uses=[v5:any@early, v6:any@early, v12:any@early] defs=[v14:any@late]
      #|  i11 VectorFloatTernary(F64x2, FusedNegatedMultiplySubtract) uses=[v5:any@early, v6:any@early, v13:any@early] defs=[v15:any@late]
      #|  i12 OutgoingReg(V128, p0:fpvec) uses=[v14:any@early]
      #|  i13 OutgoingReg(V128, p1:fpvec) uses=[v15:any@early]
      #|  i14 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects every remaining vector conversion" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_conversions",
    Internal,
    [Ptr64, V128],
    [V128],
  )
  let mut value = builder.parameters()[1]
  let signednesses : Array[@native.Signedness] = [Signed, Unsigned]
  for signedness in signednesses {
    value = builder.emit(
        Vector(Convert(FloatToInt(F32x4, I32x4, signedness, Saturating))),
        [value],
        [V128],
      )[0]
    value = builder.emit(
        Vector(Convert(FloatToInt(F64x2, I32x4, signedness, Saturating))),
        [value],
        [V128],
      )[0]
    value = builder.emit(
        Vector(Convert(IntToFloat(I32x4, F32x4, signedness))),
        [value],
        [V128],
      )[0]
    value = builder.emit(
        Vector(Convert(IntToFloat(I32x4, F64x2, signedness))),
        [value],
        [V128],
      )[0]
  }
  value = builder.emit(Vector(Convert(PromoteLowF32x4)), [value], [V128])[0]
  value = builder.emit(Vector(Convert(DemoteZeroF64x2)), [value], [V128])[0]
  value = builder.emit(
      Vector(Relaxed(FloatToInt(F64x2, I32x4, Unsigned))),
      [value],
      [V128],
    )[0]
  builder.return_([value])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_conversions(v0:ptr64, v1:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v2:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v3:any-location(prefer=p0:fpvec)@late]
      #|  i2 VectorConvert(FloatToInt(F32x4, Signed)) uses=[v3:any@early] defs=[v4:any@late]
      #|  i3 VectorConvert(FloatToInt(F64x2, Signed)) uses=[v4:any@early] defs=[v5:any@late]
      #|  i4 VectorConvert(IntToFloat(F32x4, Signed)) uses=[v5:any@early] defs=[v6:any@late]
      #|  i5 VectorConvert(IntToFloat(F64x2, Signed)) uses=[v6:any@early] defs=[v7:any@late]
      #|  i6 VectorConvert(FloatToInt(F32x4, Unsigned)) uses=[v7:any@early] defs=[v8:any@late]
      #|  i7 VectorConvert(FloatToInt(F64x2, Unsigned)) uses=[v8:any@early] defs=[v9:any@late]
      #|  i8 VectorConvert(IntToFloat(F32x4, Unsigned)) uses=[v9:any@early] defs=[v10:any@late]
      #|  i9 VectorConvert(IntToFloat(F64x2, Unsigned)) uses=[v10:any@early] defs=[v11:any@late]
      #|  i10 VectorConvert(PromoteLowF32x4) uses=[v11:any@early] defs=[v12:any@late]
      #|  i11 VectorConvert(DemoteZeroF64x2) uses=[v12:any@early] defs=[v13:any@late]
      #|  i12 VectorConvert(FloatToInt(F64x2, Unsigned)) uses=[v13:any@early] defs=[v14:any@late]
      #|  i13 OutgoingReg(V128, p0:fpvec) uses=[v14:any@early]
      #|  i14 Return
      #|
    ),
  )
}

///|
test "X64 lowering reuses exact target operations for relaxed SIMD" {
  let builder = @semantic.FunctionBuilder::new(
    "relaxed_vector_reuse",
    Internal,
    [Ptr64, V128, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let swizzled = builder.emit(
      Vector(Relaxed(Swizzle)),
      [parameters[1], parameters[2]],
      [V128],
    )[0]
  let selected = builder.emit(
      Vector(Relaxed(LaneSelect(I64x2))),
      [swizzled, parameters[2], parameters[3]],
      [V128],
    )[0]
  let minimum = builder.emit(
      Vector(Relaxed(Min(F32x4))),
      [selected, parameters[2]],
      [V128],
    )[0]
  let maximum = builder.emit(
      Vector(Relaxed(Max(F64x2))),
      [minimum, parameters[2]],
      [V128],
    )[0]
  let result = builder.emit(
      Vector(Relaxed(Q15MultiplyRoundedSigned)),
      [maximum, parameters[2]],
      [V128],
    )[0]
  builder.return_([result])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode relaxed_vector_reuse(v0:ptr64, v1:v128, v2:v128, v3:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v4:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v5:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v6:any-location(prefer=p1:fpvec)@late]
      #|  i3 IncomingReg(V128, p2:fpvec) uses=[v3:fixed(p2:fpvec)@early] defs=[v7:any-location(prefer=p2:fpvec)@late]
      #|  i4 VectorSwizzle uses=[v5:any@early, v6:any@early] defs=[v8:any@late]
      #|  i5 VectorBitwise(BitSelect) uses=[v8:any@early, v6:any@early, v7:any@early] defs=[v9:any@late]
      #|  i6 VectorFloatBinary(F32x4, Min) uses=[v9:any@early, v6:any@early] defs=[v10:any@late]
      #|  i7 VectorFloatBinary(F64x2, Max) uses=[v10:any@early, v6:any@early] defs=[v11:any@late]
      #|  i8 VectorIntBinary(I16x8, Q15MultiplyRoundedSaturating) uses=[v11:any@early, v6:any@early] defs=[v12:any@late]
      #|  i9 OutgoingReg(V128, p0:fpvec) uses=[v12:any@early]
      #|  i10 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects relaxed dot8-to16" {
  let builder = @semantic.FunctionBuilder::new(
    "relaxed_dot8_to16",
    Internal,
    [Ptr64, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let result = builder.emit(
      Vector(Relaxed(Dot8To16Signed)),
      [parameters[1], parameters[2]],
      [V128],
    )[0]
  builder.return_([result])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode relaxed_dot8_to16(v0:ptr64, v1:v128, v2:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v3:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any-location(prefer=p1:fpvec)@late]
      #|  i3 VectorRelaxedDot8To16 uses=[v4:any@early, v5:any@early] defs=[v6:any@late]
      #|  i4 OutgoingReg(V128, p0:fpvec) uses=[v6:any@early]
      #|  i5 Return
      #|
    ),
  )
}

///|
test "X64 lowering expands relaxed dot8-to32-add into allocatable temporaries" {
  let builder = @semantic.FunctionBuilder::new(
    "relaxed_dot8_to32_add",
    Internal,
    [Ptr64, V128, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let result = builder.emit(
      Vector(Relaxed(Dot8To32AddSigned)),
      [parameters[1], parameters[2], parameters[3]],
      [V128],
    )[0]
  builder.return_([result])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode relaxed_dot8_to32_add(v0:ptr64, v1:v128, v2:v128, v3:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v4:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v5:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v6:any-location(prefer=p1:fpvec)@late]
      #|  i3 IncomingReg(V128, p2:fpvec) uses=[v3:fixed(p2:fpvec)@early] defs=[v7:any-location(prefer=p2:fpvec)@late]
      #|  i4 VectorIntBinary(I16x8, ExtendMultiply(Low, Signed)) uses=[v5:any@early, v6:any@early] defs=[v8:any@late]
      #|  i5 VectorIntBinary(I16x8, ExtendMultiply(High, Signed)) uses=[v5:any@early, v6:any@early] defs=[v9:any@late]
      #|  i6 VectorPairwiseAddI16x8 uses=[v8:any@early, v9:any@early] defs=[v10:any@late]
      #|  i7 VectorIntUnary(I32x4, ExtendAddPairwise(Signed)) uses=[v10:any@early] defs=[v11:any@late]
      #|  i8 VectorIntBinary(I32x4, Add) uses=[v11:any@early, v7:any@early] defs=[v12:any@late]
      #|  i9 OutgoingReg(V128, p0:fpvec) uses=[v12:any@early]
      #|  i10 Return
      #|
    ),
  )
}

///|
test "X64 lowering assigns one aligned semantic stack-object area" {
  let builder = @semantic.FunctionBuilder::new(
    "stack_object_layout",
    Internal,
    [Ptr64],
    [Ptr64, Ptr64],
  )
  let first = builder.create_stack_object(3, 1)
  builder.create_stack_object(16, 16) |> ignore
  let last = builder.create_stack_object(24, 8)
  let first_address = builder.emit(StackAddress(first), [], [Ptr64])[0]
  let last_address = builder.emit(StackAddress(last), [], [Ptr64])[0]
  builder.return_([first_address, last_address])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode stack_object_layout(v0:ptr64) -> (ptr64, ptr64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v1:any-location(prefer=p7:int)@late]
      #|  i1 StackAddress(
      #|  {
      #|    offset: 0,
      #|    size: 3,
      #|    alignment: 1,
      #|    area_size: 64,
      #|    area_alignment: 16,
      #|  },
      #|) defs=[v2:any@late]
      #|  i2 StackAddress(
      #|  {
      #|    offset: 32,
      #|    size: 24,
      #|    alignment: 8,
      #|    area_size: 64,
      #|    area_alignment: 16,
      #|  },
      #|) defs=[v3:any@late]
      #|  i3 OutgoingReg(Ptr64, p0:int) uses=[v2:any@early]
      #|  i4 OutgoingReg(Ptr64, p2:int) uses=[v3:any@early]
      #|  i5 Return
      #|
    ),
  )
}

///|
test "X64 lowering inserts explicit traps before signed division" {
  let builder = @semantic.FunctionBuilder::new(
    "checked_divide",
    Platform,
    [I64, I64],
    [I64],
  )
  let value = builder.emit(IntBinary(SignedDiv), builder.parameters(), [I64])[0]
  builder.return_([value])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode checked_divide(v0:i64, v1:i64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(I64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v2:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(I64, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v3:any-location(prefer=p6:int)@late]
      #|  i2 TrapIfZero(W64) uses=[v3:any@early] trap=IntegerDivisionByZero
      #|  i3 TrapIfSignedDivOverflow(W64) uses=[v2:any@early, v3:any@early] trap=IntegerOverflow
      #|  i4 IntBinary(W64, Sdiv) uses=[v2:fixed(p0:int)@early, v3:fixed(p11:int)@early] defs=[v4:fixed(p0:int)@late] clobbers=[p2:int]
      #|  i5 OutgoingReg(I64, p0:int) uses=[v4:any@early]
      #|  i6 Return
      #|
    ),
  )
}

///|
test "X64 lowering legalizes remaining pure scalar integer operations" {
  let builder = @semantic.FunctionBuilder::new(
    "pure_integer_operations",
    Internal,
    [Ptr64, I32, I32, I64, I64],
    [I32, I64],
  )
  let parameters = builder.parameters()
  let trailing32 = builder.emit(IntUnary(CountTrailingZeros), [parameters[1]], [
      I32,
    ])[0]
  let population32 = builder.emit(IntUnary(PopulationCount), [parameters[1]], [
      I32,
    ])[0]
  let rotated32 = builder.emit(
      IntBinary(RotateLeft),
      [trailing32, population32],
      [I32],
    )[0]
  let signed_high32 = builder.emit(
      IntHighMultiply(Signed),
      [rotated32, parameters[2]],
      [I32],
    )[0]
  let unsigned_high32 = builder.emit(
      IntHighMultiply(Unsigned),
      [signed_high32, population32],
      [I32],
    )[0]
  let trailing64 = builder.emit(IntUnary(CountTrailingZeros), [parameters[3]], [
      I64,
    ])[0]
  let population64 = builder.emit(IntUnary(PopulationCount), [parameters[3]], [
      I64,
    ])[0]
  let rotated64 = builder.emit(
      IntBinary(RotateLeft),
      [trailing64, population64],
      [I64],
    )[0]
  let signed_high64 = builder.emit(
      IntHighMultiply(Signed),
      [rotated64, parameters[4]],
      [I64],
    )[0]
  let unsigned_high64 = builder.emit(
      IntHighMultiply(Unsigned),
      [signed_high64, population64],
      [I64],
    )[0]
  builder.return_([unsigned_high32, unsigned_high64])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode pure_integer_operations(v0:ptr64, v1:i32, v2:i32, v3:i64, v4:i64) -> (i32, i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v5:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(I32, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v6:any-location(prefer=p6:int)@late]
      #|  i2 IncomingReg(I32, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v7:any-location(prefer=p2:int)@late]
      #|  i3 IncomingReg(I64, p1:int) uses=[v3:fixed(p1:int)@early] defs=[v8:any-location(prefer=p1:int)@late]
      #|  i4 IncomingReg(I64, p8:int) uses=[v4:fixed(p8:int)@early] defs=[v9:any-location(prefer=p8:int)@late]
      #|  i5 IntUnary(W32, Rbit) uses=[v6:any@early] defs=[v10:any@late]
      #|  i6 IntUnary(W32, Clz) uses=[v10:any@early] defs=[v11:any@late]
      #|  i7 PopulationCount(W32) uses=[v6:any@early] defs=[v12:any@late]
      #|  i8 IntUnary(W32, Neg) uses=[v12:any@early] defs=[v13:any@late]
      #|  i9 IntBinary(W32, Ror) uses=[v11:any@early, v13:any@early] defs=[v14:any@late] clobbers=[p1:int]
      #|  i10 IntHighMultiply(W32, Signed) uses=[v14:fixed(p0:int)@early, v7:fixed(p11:int)@early] defs=[v15:fixed(p2:int)@late] clobbers=[p0:int]
      #|  i11 IntHighMultiply(W32, Unsigned) uses=[v15:fixed(p0:int)@early, v12:fixed(p11:int)@early] defs=[v16:fixed(p2:int)@late] clobbers=[p0:int]
      #|  i12 IntUnary(W64, Rbit) uses=[v8:any@early] defs=[v17:any@late]
      #|  i13 IntUnary(W64, Clz) uses=[v17:any@early] defs=[v18:any@late]
      #|  i14 PopulationCount(W64) uses=[v8:any@early] defs=[v19:any@late]
      #|  i15 IntUnary(W64, Neg) uses=[v19:any@early] defs=[v20:any@late]
      #|  i16 IntBinary(W64, Ror) uses=[v18:any@early, v20:any@early] defs=[v21:any@late] clobbers=[p1:int]
      #|  i17 IntHighMultiply(W64, Signed) uses=[v21:fixed(p0:int)@early, v9:fixed(p11:int)@early] defs=[v22:fixed(p2:int)@late] clobbers=[p0:int]
      #|  i18 IntHighMultiply(W64, Unsigned) uses=[v22:fixed(p0:int)@early, v19:fixed(p11:int)@early] defs=[v23:fixed(p2:int)@late] clobbers=[p0:int]
      #|  i19 OutgoingReg(I32, p0:int) uses=[v16:any@early]
      #|  i20 OutgoingReg(I64, p2:int) uses=[v23:any@early]
      #|  i21 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects every scalar overflow arithmetic contract" {
  let builder = @semantic.FunctionBuilder::new(
    "overflow_arithmetic",
    Internal,
    [Ptr64, I32, I32, I64, I64],
    [I32, I64, I32],
  )
  let parameters = builder.parameters()
  let operations : Array[@semantic.IntOverflowOp] = [
    Add(Signed),
    Add(Unsigned),
    Sub(Signed),
    Sub(Unsigned),
    Mul(Signed),
    Mul(Unsigned),
  ]
  let mut value32 = parameters[1]
  let mut overflow = builder.emit(I32Const(0U), [], [I32])[0]
  for operation in operations {
    let results = builder.emit(
      IntWithOverflow(operation),
      [value32, parameters[2]],
      [I32, I32],
    )
    value32 = results[0]
    overflow = builder.emit(IntBinary(Or), [overflow, results[1]], [I32])[0]
  }
  let mut value64 = parameters[3]
  for operation in operations {
    let results = builder.emit(
      IntWithOverflow(operation),
      [value64, parameters[4]],
      [I64, I32],
    )
    value64 = results[0]
    overflow = builder.emit(IntBinary(Or), [overflow, results[1]], [I32])[0]
  }
  builder.return_([value32, value64, overflow])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode overflow_arithmetic(v0:ptr64, v1:i32, v2:i32, v3:i64, v4:i64) -> (i32, i64, i32)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v5:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(I32, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v6:any-location(prefer=p6:int)@late]
      #|  i2 IncomingReg(I32, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v7:any-location(prefer=p2:int)@late]
      #|  i3 IncomingReg(I64, p1:int) uses=[v3:fixed(p1:int)@early] defs=[v8:any-location(prefer=p1:int)@late]
      #|  i4 IncomingReg(I64, p8:int) uses=[v4:fixed(p8:int)@early] defs=[v9:any-location(prefer=p8:int)@late]
      #|  i5 IncomingResultArea(p10:int) defs=[v10:any-location@late]
      #|  i6 LoadConstant(W32, 0) defs=[v11:any@late]
      #|  i7 IntWithOverflow(W32, Add(Signed)) uses=[v6:any@early, v7:any@early] defs=[v12:any@late, v13:any@late]
      #|  i8 IntBinary(W32, Orr) uses=[v11:any@early, v13:any@early] defs=[v14:any@late]
      #|  i9 IntWithOverflow(W32, Add(Unsigned)) uses=[v12:any@early, v7:any@early] defs=[v15:any@late, v16:any@late]
      #|  i10 IntBinary(W32, Orr) uses=[v14:any@early, v16:any@early] defs=[v17:any@late]
      #|  i11 IntWithOverflow(W32, Sub(Signed)) uses=[v15:any@early, v7:any@early] defs=[v18:any@late, v19:any@late]
      #|  i12 IntBinary(W32, Orr) uses=[v17:any@early, v19:any@early] defs=[v20:any@late]
      #|  i13 IntWithOverflow(W32, Sub(Unsigned)) uses=[v18:any@early, v7:any@early] defs=[v21:any@late, v22:any@late]
      #|  i14 IntBinary(W32, Orr) uses=[v20:any@early, v22:any@early] defs=[v23:any@late]
      #|  i15 IntWithOverflow(W32, Mul(Signed)) uses=[v21:fixed(p0:int)@early, v7:fixed(p11:int)@early] defs=[v24:fixed(p0:int)@late, v25:any@late] clobbers=[p2:int]
      #|  i16 IntBinary(W32, Orr) uses=[v23:any@early, v25:any@early] defs=[v26:any@late]
      #|  i17 IntWithOverflow(W32, Mul(Unsigned)) uses=[v24:fixed(p0:int)@early, v7:fixed(p11:int)@early] defs=[v27:fixed(p0:int)@late, v28:any@late] clobbers=[p2:int]
      #|  i18 IntBinary(W32, Orr) uses=[v26:any@early, v28:any@early] defs=[v29:any@late]
      #|  i19 IntWithOverflow(W64, Add(Signed)) uses=[v8:any@early, v9:any@early] defs=[v30:any@late, v31:any@late]
      #|  i20 IntBinary(W32, Orr) uses=[v29:any@early, v31:any@early] defs=[v32:any@late]
      #|  i21 IntWithOverflow(W64, Add(Unsigned)) uses=[v30:any@early, v9:any@early] defs=[v33:any@late, v34:any@late]
      #|  i22 IntBinary(W32, Orr) uses=[v32:any@early, v34:any@early] defs=[v35:any@late]
      #|  i23 IntWithOverflow(W64, Sub(Signed)) uses=[v33:any@early, v9:any@early] defs=[v36:any@late, v37:any@late]
      #|  i24 IntBinary(W32, Orr) uses=[v35:any@early, v37:any@early] defs=[v38:any@late]
      #|  i25 IntWithOverflow(W64, Sub(Unsigned)) uses=[v36:any@early, v9:any@early] defs=[v39:any@late, v40:any@late]
      #|  i26 IntBinary(W32, Orr) uses=[v38:any@early, v40:any@early] defs=[v41:any@late]
      #|  i27 IntWithOverflow(W64, Mul(Signed)) uses=[v39:fixed(p0:int)@early, v9:fixed(p11:int)@early] defs=[v42:fixed(p0:int)@late, v43:any@late] clobbers=[p2:int]
      #|  i28 IntBinary(W32, Orr) uses=[v41:any@early, v43:any@early] defs=[v44:any@late]
      #|  i29 IntWithOverflow(W64, Mul(Unsigned)) uses=[v42:fixed(p0:int)@early, v9:fixed(p11:int)@early] defs=[v45:fixed(p0:int)@late, v46:any@late] clobbers=[p2:int]
      #|  i30 IntBinary(W32, Orr) uses=[v44:any@early, v46:any@early] defs=[v47:any@late]
      #|  i31 OutgoingReg(I32, p0:int) uses=[v27:any@early]
      #|  i32 OutgoingReg(I64, p2:int) uses=[v45:any@early]
      #|  i33 OutgoingAreaResult(I32, 0) uses=[v10:any@early, v47:any@early]
      #|  i34 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects null carriers references and scalar values" {
  let builder = @semantic.FunctionBuilder::new(
    "scalar_carriers_and_select",
    Internal,
    [Ptr64, I32, I32, I64, I64, F32, F32, F64, F64],
    [I32, I32, I32, I64, Ptr64, GcRef64, F32, F64],
  )
  let parameters = builder.parameters()
  let null_pointer = builder.emit(NullPtr, [], [Ptr64])[0]
  let null_reference = builder.emit(NullGcRef, [], [GcRef64])[0]
  let reference = builder.emit(GcRefFromBits, [parameters[3]], [GcRef64])[0]
  let address = builder.emit(GcRefAddress, [reference], [Ptr64])[0]
  let pointer_equal = builder.emit(
      ReferenceCompare(Equal),
      [null_pointer, address],
      [I32],
    )[0]
  let reference_not_equal = builder.emit(
      ReferenceCompare(NotEqual),
      [null_reference, reference],
      [I32],
    )[0]
  let selected32 = builder.emit(
      Select,
      [parameters[1], parameters[1], parameters[2]],
      [I32],
    )[0]
  let selected64 = builder.emit(
      Select,
      [parameters[1], parameters[3], parameters[4]],
      [I64],
    )[0]
  let selected_pointer = builder.emit(
      Select,
      [parameters[1], null_pointer, address],
      [Ptr64],
    )[0]
  let selected_reference = builder.emit(
      Select,
      [parameters[1], null_reference, reference],
      [GcRef64],
    )[0]
  let selected32_float = builder.emit(
      Select,
      [parameters[1], parameters[5], parameters[6]],
      [F32],
    )[0]
  let selected64_float = builder.emit(
      Select,
      [parameters[1], parameters[7], parameters[8]],
      [F64],
    )[0]
  builder.return_([
    pointer_equal, reference_not_equal, selected32, selected64, selected_pointer,
    selected_reference, selected32_float, selected64_float,
  ])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_carriers_and_select(v0:ptr64, v1:i32, v2:i32, v3:i64, v4:i64, v5:f32, v6:f32, v7:f64, v8:f64) -> (i32, i32, i32, i64, ptr64, gcref64, f32, f64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v9:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(I32, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v10:any-location(prefer=p6:int)@late]
      #|  i2 IncomingReg(I32, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v11:any-location(prefer=p2:int)@late]
      #|  i3 IncomingReg(I64, p1:int) uses=[v3:fixed(p1:int)@early] defs=[v12:any-location(prefer=p1:int)@late]
      #|  i4 IncomingReg(I64, p8:int) uses=[v4:fixed(p8:int)@early] defs=[v13:any-location(prefer=p8:int)@late]
      #|  i5 IncomingReg(F32, p0:fpvec) uses=[v5:fixed(p0:fpvec)@early] defs=[v14:any-location(prefer=p0:fpvec)@late]
      #|  i6 IncomingReg(F32, p1:fpvec) uses=[v6:fixed(p1:fpvec)@early] defs=[v15:any-location(prefer=p1:fpvec)@late]
      #|  i7 IncomingReg(F64, p2:fpvec) uses=[v7:fixed(p2:fpvec)@early] defs=[v16:any-location(prefer=p2:fpvec)@late]
      #|  i8 IncomingReg(F64, p3:fpvec) uses=[v8:fixed(p3:fpvec)@early] defs=[v17:any-location(prefer=p3:fpvec)@late]
      #|  i9 IncomingResultArea(p10:int) defs=[v18:any-location@late]
      #|  i10 LoadNull(Ptr64) defs=[v19:any@late]
      #|  i11 LoadNull(GcRef64) defs=[v20:any@late]
      #|  i12 CarrierMove(I64, GcRef64) uses=[v12:any@early] defs=[v21:any@late]
      #|  i13 CarrierMove(GcRef64, Ptr64) uses=[v21:any@early] defs=[v22:any@late]
      #|  i14 ReferenceCompareSet(Ptr64, Eq) uses=[v19:any@early, v22:any@early] defs=[v23:any@late]
      #|  i15 ReferenceCompareSet(GcRef64, Ne) uses=[v20:any@early, v21:any@early] defs=[v24:any@late]
      #|  i16 Select(I32) uses=[v10:any@early, v10:any@early, v11:any@early] defs=[v25:any@late]
      #|  i17 Select(I64) uses=[v10:any@early, v12:any@early, v13:any@early] defs=[v26:any@late]
      #|  i18 Select(Ptr64) uses=[v10:any@early, v19:any@early, v22:any@early] defs=[v27:any@late]
      #|  i19 Select(GcRef64) uses=[v10:any@early, v20:any@early, v21:any@early] defs=[v28:any@late]
      #|  i20 Select(F32) uses=[v10:any@early, v14:any@early, v15:any@early] defs=[v29:any@late]
      #|  i21 Select(F64) uses=[v10:any@early, v16:any@early, v17:any@early] defs=[v30:any@late]
      #|  i22 OutgoingReg(I32, p0:int) uses=[v23:any@early]
      #|  i23 OutgoingReg(I32, p2:int) uses=[v24:any@early]
      #|  i24 OutgoingAreaResult(I32, 0) uses=[v18:any@early, v25:any@early]
      #|  i25 OutgoingAreaResult(I64, 8) uses=[v18:any@early, v26:any@early]
      #|  i26 OutgoingAreaResult(Ptr64, 16) uses=[v18:any@early, v27:any@early]
      #|  i27 OutgoingAreaResult(GcRef64, 24) uses=[v18:any@early, v28:any@early]
      #|  i28 OutgoingReg(F32, p0:fpvec) uses=[v29:any@early]
      #|  i29 OutgoingReg(F64, p1:fpvec) uses=[v30:any@early]
      #|  i30 Return
      #|
    ),
  )
}

///|
test "X64 lowering resolves environment paths and typed symbol addresses" {
  let field = @native.EnvironmentField::new("runtime.memory.base", I64)
  let builder = @semantic.FunctionBuilder::new(
    "addresses_and_environment",
    Internal,
    [Ptr64],
    [Ptr64, Ptr64, Ptr64, I64],
  )
  let code = builder.emit(CodeAddress(@native.CodeSymbol::new("callee")), [], [
      Ptr64,
    ])[0]
  let external = builder.emit(
      ExternalAddress(@native.ExternalSymbol::new("runtime.helper")),
      [],
      [Ptr64],
    )[0]
  let data = builder.emit(
      DataAddress(@native.DataSymbol::new("constant.pool")),
      [],
      [Ptr64],
    )[0]
  let environment = builder.emit(
      EnvironmentField(field, Mutable),
      [builder.parameters()[0]],
      [I64],
    )[0]
  builder.return_([code, external, data, environment])
  let context = test_lowering_context().with_environment_field(field, [8, 24])
  inspect(
    lower(builder.finish_selection_plan(), context).summary(),
    content=(
      #|vcode addresses_and_environment(v0:ptr64) -> (ptr64, ptr64, ptr64, i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v1:any-location(prefer=p7:int)@late]
      #|  i1 IncomingResultArea(p10:int) defs=[v2:any-location@late]
      #|  i2 LoadAddress(Code({ name: "callee" })) defs=[v3:any@late]
      #|  i3 LoadAddress(External({ name: "runtime.helper" })) defs=[v4:any@late]
      #|  i4 LoadAddress(Data({ name: "constant.pool" })) defs=[v5:any@late]
      #|  i5 ScalarLoad(W64, None, Ptr64, 8) uses=[v1:any@early] defs=[v6:any@late]
      #|  i6 ScalarLoad(W64, None, I64, 24) uses=[v6:any@early] defs=[v7:any@late]
      #|  i7 OutgoingReg(Ptr64, p0:int) uses=[v3:any@early]
      #|  i8 OutgoingReg(Ptr64, p2:int) uses=[v4:any@early]
      #|  i9 OutgoingAreaResult(Ptr64, 0) uses=[v2:any@early, v5:any@early]
      #|  i10 OutgoingAreaResult(I64, 8) uses=[v2:any@early, v7:any@early]
      #|  i11 Return
      #|
    ),
  )
}

///|
test "X64 lowering materializes each stable environment field" {
  let field = @native.EnvironmentField::new("runtime.memory.base", I64)
  let builder = @semantic.FunctionBuilder::new(
    "stable_environment_fields",
    Internal,
    [Ptr64],
    [I64, I64],
  )
  let context = builder.parameters()[0]
  let first = builder.emit(EnvironmentField(field, Stable), [context], [I64])[0]
  let second = builder.emit(EnvironmentField(field, Stable), [context], [I64])[0]
  builder.return_([first, second])
  let lowering = test_lowering_context().with_environment_field(field, [24])
  inspect(
    lower(builder.finish_selection_plan(), lowering).summary(),
    content=(
      #|vcode stable_environment_fields(v0:ptr64) -> (i64, i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v1:any-location(prefer=p7:int)@late]
      #|  i1 ScalarLoad(W64, None, I64, 24) uses=[v1:any@early] defs=[v2:any@late]
      #|  i2 ScalarLoad(W64, None, I64, 24) uses=[v1:any@early] defs=[v3:any@late]
      #|  i3 OutgoingReg(I64, p0:int) uses=[v2:any@early]
      #|  i4 OutgoingReg(I64, p2:int) uses=[v3:any@early]
      #|  i5 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects a direct platform call with explicit ABI facts" {
  let builder = @semantic.FunctionBuilder::new(
    "direct_platform_call",
    Platform,
    [I64, F64],
    [I64],
  )
  let call = @semantic.SemanticCall::new(
    External(@native.ExternalSymbol::new("runtime.helper")),
    @native.Signature::new([I64, F64], [I64]),
    Platform,
    @native.CallBehavior::new(ReadWrite, true, true, true, true),
  )
  let result = builder.emit_with_metadata(
      Call(call),
      builder.parameters(),
      [I64],
      @semantic.InstructionMetadata::new(
        Some(@native.SourceLocation::new("call.wat", 7, 11)),
        [],
      ),
    )[0]
  builder.return_([result])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode direct_platform_call(v0:i64, v1:f64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(I64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v2:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(F64, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v3:any-location(prefer=p0:fpvec)@late]
      #|  i2 PlatformCall(
      #|  { name: "runtime.helper" },
      #|  { params: [I64, F64], results: [I64] },
      #|) uses=[v2:any-location(prefer=p7:int)@early, v3:any-location(prefer=p0:fpvec)@early] clobbers=[p0:int, p1:int, p2:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec] source={ file: "call.wat", line: 7, column: 11 } safepoint=GcAndCancellation
      #|  i3 IncomingCallResult(I64, p0:int) defs=[v4:any-location(prefer=p0:int)@late]
      #|  i4 OutgoingReg(I64, p0:int) uses=[v4:any@early]
      #|  i5 Return
      #|
    ),
  )
}

///|
test "X64 lowering preserves returns-twice platform calls" {
  let builder = @semantic.FunctionBuilder::new(
    "returns_twice_platform_call",
    Platform,
    [Ptr64, I32, I64],
    [I64],
  )
  let call = @semantic.SemanticCall::new(
    External(@native.ExternalSymbol::new("runtime.sigsetjmp")),
    @native.Signature::new([Ptr64, I32], [I32]),
    Platform,
    @native.CallBehavior::new(
      ReadWrite,
      false,
      false,
      false,
      false,
      returns_twice=true,
    ),
  )
  let parameters = builder.parameters()
  let result = builder.emit(Call(call), [parameters[0], parameters[1]], [I32])[0]
  let widened = builder.emit(Convert(I64ExtendI32(Unsigned)), [result], [I64])[0]
  let preserved = builder.emit(IntBinary(Add), [parameters[2], widened], [I64])[0]
  builder.return_([preserved])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode returns_twice_platform_call(v0:ptr64, v1:i32, v2:i64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v3:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(I32, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v4:any-location(prefer=p6:int)@late]
      #|  i2 IncomingReg(I64, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v5:any-location(prefer=p2:int)@late]
      #|  i3 ReturnsTwicePlatformCall(
      #|  { name: "runtime.sigsetjmp" },
      #|  { params: [Ptr64, I32], results: [I32] },
      #|) uses=[v3:any-location(prefer=p7:int)@early, v4:any-location(prefer=p6:int)@early] clobbers=[p0:int, p1:int, p2:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec]
      #|  i4 IncomingCallResult(I32, p0:int) defs=[v6:any-location(prefer=p0:int)@late]
      #|  i5 Convert(ExtendI32ToI64(Unsigned)) uses=[v6:any@early] defs=[v7:any@late]
      #|  i6 IntBinary(W64, Add) uses=[v5:any@early, v7:any@early] defs=[v8:any@late]
      #|  i7 OutgoingReg(I64, p0:int) uses=[v8:any@early]
      #|  i8 Return
      #|
    ),
  )
}

///|
test "X64 lowering derives internal entry and direct-call layouts" {
  let builder = @semantic.FunctionBuilder::new(
    "direct_internal_call",
    Internal,
    [Ptr64, I64, F64],
    [I64],
  )
  let call = @semantic.SemanticCall::new(
    Internal(@native.CodeSymbol::new("wasm.func.7")),
    @native.Signature::new([Ptr64, I64, F64], [I64]),
    Internal,
    @native.CallBehavior::new(ReadWrite, true, true, true, true),
  )
  let result = builder.emit(Call(call), builder.parameters(), [I64])[0]
  builder.return_([result])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode direct_internal_call(v0:ptr64, v1:i64, v2:f64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v3:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(I64, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v4:any-location(prefer=p6:int)@late]
      #|  i2 IncomingReg(F64, p0:fpvec) uses=[v2:fixed(p0:fpvec)@early] defs=[v5:any-location(prefer=p0:fpvec)@late]
      #|  i3 InternalCall(
      #|  { name: "wasm.func.7" },
      #|  { params: [Ptr64, I64, F64], results: [I64] },
      #|  {
      #|    arguments: [CallRegister(p7:int), CallRegister(p6:int), CallRegister(p0:fpvec)],
      #|    results: [CallResultRegister(p0:int)],
      #|    stack_size: 0,
      #|    result_area_size: 0,
      #|  },
      #|) uses=[v3:any-location(prefer=p7:int)@early, v4:any-location(prefer=p6:int)@early, v5:any-location(prefer=p0:fpvec)@early] clobbers=[p0:int, p1:int, p2:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec] safepoint=GcAndCancellation
      #|  i4 IncomingCallResult(I64, p0:int) defs=[v6:any-location(prefer=p0:int)@late]
      #|  i5 OutgoingReg(I64, p0:int) uses=[v6:any@early]
      #|  i6 Return
      #|
    ),
  )
}

///|
test "X64 lowering keeps the indirect callee outside the logical signature" {
  let builder = @semantic.FunctionBuilder::new(
    "indirect_internal_call",
    Internal,
    [Ptr64, Ptr64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let call = @semantic.SemanticCall::new(
    Indirect,
    @native.Signature::new([Ptr64, I64], [I64]),
    Internal,
    @native.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  let result = builder.emit(
      Call(call),
      [parameters[1], parameters[0], parameters[2]],
      [I64],
    )[0]
  builder.return_([result])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode indirect_internal_call(v0:ptr64, v1:ptr64, v2:i64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v3:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(Ptr64, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v4:any-location(prefer=p6:int)@late]
      #|  i2 IncomingReg(I64, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v5:any-location(prefer=p2:int)@late]
      #|  i3 InternalCallIndirect(
      #|  { params: [Ptr64, I64], results: [I64] },
      #|  {
      #|    arguments: [CallRegister(p7:int), CallRegister(p6:int)],
      #|    results: [CallResultRegister(p0:int)],
      #|    stack_size: 0,
      #|    result_area_size: 0,
      #|  },
      #|) uses=[v4:any-location@early, v3:any-location(prefer=p7:int)@early, v5:any-location(prefer=p6:int)@early] clobbers=[p0:int, p1:int, p2:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec]
      #|  i4 IncomingCallResult(I64, p0:int) defs=[v6:any-location(prefer=p0:int)@late]
      #|  i5 OutgoingReg(I64, p0:int) uses=[v6:any@early]
      #|  i6 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects a compatible true internal tail call" {
  let builder = @semantic.FunctionBuilder::new(
    "direct_tail_call",
    Internal,
    [Ptr64, I64],
    [I64],
  )
  let call = @semantic.SemanticCall::new(
    Internal(@native.CodeSymbol::new("wasm.func.9")),
    @native.Signature::new([Ptr64, I64], [I64]),
    Internal,
    @native.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.tail_call(call, builder.parameters())
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode direct_tail_call(v0:ptr64, v1:i64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v2:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(I64, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v3:any-location(prefer=p6:int)@late]
      #|  i2 TailCallDirect(
      #|  { name: "wasm.func.9" },
      #|  { params: [Ptr64, I64], results: [I64] },
      #|  {
      #|    arguments: [CallRegister(p7:int), CallRegister(p6:int)],
      #|    results: [CallResultRegister(p0:int)],
      #|    stack_size: 0,
      #|    result_area_size: 0,
      #|  },
      #|) uses=[v2:any-location(prefer=p7:int)@early, v3:any-location(prefer=p6:int)@early] clobbers=[p0:int, p1:int, p2:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec]
      #|
    ),
  )
}

///|
test "X64 tail calls transfer GC references without a caller safepoint" {
  let builder = @semantic.FunctionBuilder::new(
    "tail_call_gc_argument",
    Internal,
    [Ptr64, GcRef64],
    [],
  )
  let parameters = builder.parameters()
  let call = @semantic.SemanticCall::new(
    Internal(@native.CodeSymbol::new("wasm.func.gc_argument")),
    @native.Signature::new([Ptr64, GcRef64], []),
    Internal,
    @native.CallBehavior::new(ReadWrite, true, true, true, false),
  )
  builder.tail_call_with_metadata(
    call,
    parameters,
    @semantic.TerminatorMetadata::new(None, [parameters[1]]),
  )
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode tail_call_gc_argument(v0:ptr64, v1:gcref64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v2:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(GcRef64, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v3:any-location(prefer=p6:int)@late]
      #|  i2 TailCallDirect(
      #|  { name: "wasm.func.gc_argument" },
      #|  { params: [Ptr64, GcRef64], results: [] },
      #|  {
      #|    arguments: [CallRegister(p7:int), CallRegister(p6:int)],
      #|    results: [],
      #|    stack_size: 0,
      #|    result_area_size: 0,
      #|  },
      #|) uses=[v2:any-location(prefer=p7:int)@early, v3:any-location(prefer=p6:int)@early] clobbers=[p0:int, p1:int, p2:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec]
      #|
    ),
  )
}

///|
fn compact_result_context() -> LoweringContext {
  LoweringContext::new(
    try! InternalAbi::new(
      0,
      8,
      [1, 2, 3, 4, 5, 6, 7],
      [0, 1, 2, 3, 4, 5, 6, 7],
      [0],
      [0],
    ),
  )
}

///|
test "X64 internal calls materialize register and result-area returns" {
  let types : Array[@native.ValueType] = [I64, I64, F32, V128]
  let builder = @semantic.FunctionBuilder::new(
    "internal_result_area_call",
    Internal,
    [Ptr64, ..types],
    types,
  )
  let call = @semantic.SemanticCall::new(
    Internal(@native.CodeSymbol::new("wasm.func.result_area")),
    @native.Signature::new([Ptr64, ..types], types),
    Internal,
    @native.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  let results = builder.emit(Call(call), builder.parameters(), types)
  builder.return_(results)
  inspect(
    lower(builder.finish_selection_plan(), compact_result_context()).summary(),
    content=(
      #|vcode internal_result_area_call(v0:ptr64, v1:i64, v2:i64, v3:f32, v4:v128) -> (i64, i64, f32, v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v5:any-location(prefer=p0:int)@late]
      #|  i1 IncomingReg(I64, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v6:any-location(prefer=p1:int)@late]
      #|  i2 IncomingReg(I64, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v7:any-location(prefer=p2:int)@late]
      #|  i3 IncomingReg(F32, p0:fpvec) uses=[v3:fixed(p0:fpvec)@early] defs=[v8:any-location(prefer=p0:fpvec)@late]
      #|  i4 IncomingReg(V128, p1:fpvec) uses=[v4:fixed(p1:fpvec)@early] defs=[v9:any-location(prefer=p1:fpvec)@late]
      #|  i5 IncomingResultArea(p8:int) defs=[v10:any-location@late]
      #|  i6 InternalCall(
      #|  { name: "wasm.func.result_area" },
      #|  {
      #|    params: [Ptr64, I64, I64, F32, V128],
      #|    results: [I64, I64, F32, V128],
      #|  },
      #|  {
      #|    arguments: [
      #|      CallRegister(p0:int),
      #|      CallRegister(p1:int),
      #|      CallRegister(p2:int),
      #|      CallRegister(p0:fpvec),
      #|      CallRegister(p1:fpvec),
      #|    ],
      #|    results: [
      #|      CallResultRegister(p0:int),
      #|      CallResultArea(0, p8:int),
      #|      CallResultRegister(p0:fpvec),
      #|      CallResultArea(16, p8:int),
      #|    ],
      #|    stack_size: 0,
      #|    result_area_size: 32,
      #|  },
      #|) uses=[v5:any-location(prefer=p0:int)@early, v6:any-location(prefer=p1:int)@early, v7:any-location(prefer=p2:int)@early, v8:any-location(prefer=p0:fpvec)@early, v9:any-location(prefer=p1:fpvec)@early] clobbers=[p0:int, p1:int, p2:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec]
      #|  i7 IncomingCallResult(I64, p0:int) defs=[v11:any-location(prefer=p0:int)@late]
      #|  i8 IncomingCallAreaResult(I64, 0) defs=[v12:any-location@late]
      #|  i9 IncomingCallResult(F32, p0:fpvec) defs=[v13:any-location(prefer=p0:fpvec)@late]
      #|  i10 IncomingCallAreaResult(V128, 16) defs=[v14:any-location@late]
      #|  i11 OutgoingReg(I64, p0:int) uses=[v11:any@early]
      #|  i12 OutgoingAreaResult(I64, 0) uses=[v10:any@early, v12:any@early]
      #|  i13 OutgoingReg(F32, p0:fpvec) uses=[v13:any@early]
      #|  i14 OutgoingAreaResult(V128, 16) uses=[v10:any@early, v14:any@early]
      #|  i15 Return
      #|
    ),
  )
}

///|
test "X64 internal tail calls forward the incoming result area" {
  let types : Array[@native.ValueType] = [I64, I64, F32, V128]
  let builder = @semantic.FunctionBuilder::new(
    "internal_result_area_tail_call",
    Internal,
    [Ptr64, ..types],
    types,
  )
  let call = @semantic.SemanticCall::new(
    Internal(@native.CodeSymbol::new("wasm.func.result_area_tail")),
    @native.Signature::new([Ptr64, ..types], types),
    Internal,
    @native.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.tail_call(call, builder.parameters())
  inspect(
    lower(builder.finish_selection_plan(), compact_result_context()).summary(),
    content=(
      #|vcode internal_result_area_tail_call(v0:ptr64, v1:i64, v2:i64, v3:f32, v4:v128) -> (i64, i64, f32, v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v5:any-location(prefer=p0:int)@late]
      #|  i1 IncomingReg(I64, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v6:any-location(prefer=p1:int)@late]
      #|  i2 IncomingReg(I64, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v7:any-location(prefer=p2:int)@late]
      #|  i3 IncomingReg(F32, p0:fpvec) uses=[v3:fixed(p0:fpvec)@early] defs=[v8:any-location(prefer=p0:fpvec)@late]
      #|  i4 IncomingReg(V128, p1:fpvec) uses=[v4:fixed(p1:fpvec)@early] defs=[v9:any-location(prefer=p1:fpvec)@late]
      #|  i5 IncomingResultArea(p8:int) defs=[v10:any-location@late]
      #|  i6 TailCallDirect(
      #|  { name: "wasm.func.result_area_tail" },
      #|  {
      #|    params: [Ptr64, I64, I64, F32, V128],
      #|    results: [I64, I64, F32, V128],
      #|  },
      #|  {
      #|    arguments: [
      #|      CallRegister(p0:int),
      #|      CallRegister(p1:int),
      #|      CallRegister(p2:int),
      #|      CallRegister(p0:fpvec),
      #|      CallRegister(p1:fpvec),
      #|    ],
      #|    results: [
      #|      CallResultRegister(p0:int),
      #|      CallResultArea(0, p8:int),
      #|      CallResultRegister(p0:fpvec),
      #|      CallResultArea(16, p8:int),
      #|    ],
      #|    stack_size: 0,
      #|    result_area_size: 32,
      #|  },
      #|) uses=[v5:any-location(prefer=p0:int)@early, v6:any-location(prefer=p1:int)@early, v7:any-location(prefer=p2:int)@early, v8:any-location(prefer=p0:fpvec)@early, v9:any-location(prefer=p1:fpvec)@early, v10:any-location(prefer=p8:int)@early] clobbers=[p0:int, p1:int, p2:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec]
      #|
    ),
  )
}

///|
test "X64 lowers dense and sparse switches with edge arguments" {
  let dense = @semantic.FunctionBuilder::new(
    "dense_switch",
    Internal,
    [Ptr64, I32],
    [I32],
  )
  let dense_zero = dense.create_block([I32])
  let dense_one = dense.create_block([I32])
  let dense_default = dense.create_block([I32])
  let dense_index = dense.parameters()[1]
  dense.switch(
    dense_index,
    [(1UL, dense_one, [dense_index]), (0UL, dense_zero, [dense_index])],
    dense_default,
    [dense_index],
  )
  for target in [dense_zero, dense_one, dense_default] {
    dense.switch_to_block(target)
    dense.return_(dense.block_parameters(target))
  }
  let sparse = @semantic.FunctionBuilder::new(
    "sparse_switch",
    Internal,
    [Ptr64, I64],
    [I64],
  )
  let sparse_low = sparse.create_block([I64])
  let sparse_high = sparse.create_block([I64])
  let sparse_default = sparse.create_block([I64])
  let sparse_index = sparse.parameters()[1]
  sparse.switch(
    sparse_index,
    [
      (7UL, sparse_low, [sparse_index]),
      (0x10000UL, sparse_high, [sparse_index]),
    ],
    sparse_default,
    [sparse_index],
  )
  for target in [sparse_low, sparse_high, sparse_default] {
    sparse.switch_to_block(target)
    sparse.return_(sparse.block_parameters(target))
  }
  inspect(
    lower(dense.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode dense_switch(v0:ptr64, v1:i32) -> (i32)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v2:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(I32, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v3:any-location(prefer=p6:int)@late]
      #|  i2 Switch(W32, [1, 0]) uses=[v3:any@early] -> block2(v3) -> block1(v3) -> block3(v3)
      #|block3(v6:i32):
      #|  i3 OutgoingReg(I32, p0:int) uses=[v6:any@early]
      #|  i4 Return
      #|block1(v4:i32):
      #|  i5 OutgoingReg(I32, p0:int) uses=[v4:any@early]
      #|  i6 Return
      #|block2(v5:i32):
      #|  i7 OutgoingReg(I32, p0:int) uses=[v5:any@early]
      #|  i8 Return
      #|
    ),
  )
  inspect(
    lower(sparse.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode sparse_switch(v0:ptr64, v1:i64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v2:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(I64, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v3:any-location(prefer=p6:int)@late]
      #|  i2 Switch(W64, [7, 65536]) uses=[v3:any@early] -> block1(v3) -> block2(v3) -> block3(v3)
      #|block3(v6:i64):
      #|  i3 OutgoingReg(I64, p0:int) uses=[v6:any@early]
      #|  i4 Return
      #|block2(v5:i64):
      #|  i5 OutgoingReg(I64, p0:int) uses=[v5:any@early]
      #|  i6 Return
      #|block1(v4:i64):
      #|  i7 OutgoingReg(I64, p0:int) uses=[v4:any@early]
      #|  i8 Return
      #|
    ),
  )
}

///|
test "X64 lowers noreturn calls and explicit traps" {
  let noreturn = @semantic.FunctionBuilder::new(
    "noreturn_call",
    Platform,
    [GcRef64],
    [],
  )
  let call = @semantic.SemanticCall::new(
    External(@native.ExternalSymbol::new("runtime.abort")),
    @native.Signature::new([], []),
    Platform,
    @native.CallBehavior::new(ReadWrite, true, true, true, true),
  )
  noreturn.noreturn_call_with_metadata(
    call,
    [],
    @semantic.TerminatorMetadata::new(
      Some(@native.SourceLocation::new("trap.wat", 9, 4)),
      [noreturn.parameters()[0]],
    ),
  )
  let trapped = @semantic.FunctionBuilder::new(
    "explicit_trap",
    Internal,
    [Ptr64],
    [],
  )
  trapped.trap(User(7))
  trapped.set_terminator_source(@native.SourceLocation::new("trap.wat", 3, 9))
  inspect(
    lower(noreturn.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode noreturn_call(v0:gcref64)
      #|block0:
      #|  i0 IncomingReg(GcRef64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v1:any-location(prefer=p7:int)@late]
      #|  i1 PlatformCall({ name: "runtime.abort" }, { params: [], results: [] }) clobbers=[p0:int, p1:int, p2:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec] source={ file: "trap.wat", line: 9, column: 4 } safepoint=GcAndCancellation roots=[v1]
      #|  i2 KeepAlive(GcRef64) uses=[v1:any@early]
      #|  i3 Trap(Unreachable) source={ file: "trap.wat", line: 9, column: 4 } trap=Unreachable
      #|
    ),
  )
  inspect(
    lower(trapped.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode explicit_trap(v0:ptr64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v1:any-location(prefer=p7:int)@late]
      #|  i1 Trap(User(7)) source={ file: "trap.wat", line: 3, column: 9 } trap=User(7)
      #|
    ),
  )
}

///|
test "X64 selects tail calls larger than the incoming argument area" {
  let builder = @semantic.FunctionBuilder::new(
    "oversized_tail_call",
    Internal,
    [Ptr64],
    [],
  )
  let operands = [builder.parameters()[0]]
  for index in 0..<8 {
    operands.push(builder.emit(I64Const(index.to_uint64()), [], [I64])[0])
  }
  let call = @semantic.SemanticCall::new(
    Internal(@native.CodeSymbol::new("wasm.func.10")),
    @native.Signature::new([Ptr64, I64, I64, I64, I64, I64, I64, I64, I64], []),
    Internal,
    @native.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.tail_call(call, operands)
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode oversized_tail_call(v0:ptr64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v1:any-location(prefer=p7:int)@late]
      #|  i1 LoadConstant(W64, 0) defs=[v2:any@late]
      #|  i2 LoadConstant(W64, 1) defs=[v3:any@late]
      #|  i3 LoadConstant(W64, 2) defs=[v4:any@late]
      #|  i4 LoadConstant(W64, 3) defs=[v5:any@late]
      #|  i5 LoadConstant(W64, 4) defs=[v6:any@late]
      #|  i6 LoadConstant(W64, 5) defs=[v7:any@late]
      #|  i7 LoadConstant(W64, 6) defs=[v8:any@late]
      #|  i8 LoadConstant(W64, 7) defs=[v9:any@late]
      #|  i9 TailCallDirect(
      #|  { name: "wasm.func.10" },
      #|  {
      #|    params: [Ptr64, I64, I64, I64, I64, I64, I64, I64, I64],
      #|    results: [],
      #|  },
      #|  {
      #|    arguments: [
      #|      CallRegister(p7:int),
      #|      CallRegister(p6:int),
      #|      CallRegister(p2:int),
      #|      CallRegister(p1:int),
      #|      CallRegister(p8:int),
      #|      CallRegister(p9:int),
      #|      CallStack(0),
      #|      CallStack(8),
      #|      CallStack(16),
      #|    ],
      #|    results: [],
      #|    stack_size: 32,
      #|    result_area_size: 0,
      #|  },
      #|) uses=[v1:any-location(prefer=p7:int)@early, v2:any-location(prefer=p6:int)@early, v3:any-location(prefer=p2:int)@early, v4:any-location(prefer=p1:int)@early, v5:any-location(prefer=p8:int)@early, v6:any-location(prefer=p9:int)@early, v7:any-location@early, v8:any-location@early, v9:any-location@early] clobbers=[p0:int, p1:int, p2:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec]
      #|
    ),
  )
}

///|
test "X64 lowering selects typed scalar memory operations and traps" {
  let builder = @semantic.FunctionBuilder::new(
    "scalar_memory",
    Internal,
    [Ptr64, I32, I64, F32, F64],
    [I64],
  )
  let parameters = builder.parameters()
  builder.emit_with_metadata(
    Load(
      @semantic.LoadSpec::new(
        W8,
        Signed,
        I32,
        3UL,
        Little,
        Some(MemoryOutOfBounds),
      ),
    ),
    [parameters[0]],
    [I32],
    @semantic.InstructionMetadata::new(
      Some(@native.SourceLocation::new("memory.wat", 4, 7)),
      [],
    ),
  )
  |> ignore
  let loaded = builder.emit(
      Load(
        @semantic.LoadSpec::new(
          W32,
          Unsigned,
          I64,
          12UL,
          Little,
          Some(MemoryOutOfBounds),
        ),
      ),
      [parameters[0]],
      [I64],
    )[0]
  builder.emit(
    Load(@semantic.LoadSpec::new(W64, None, Ptr64, 16UL, Little, None)),
    [parameters[0]],
    [Ptr64],
  )
  |> ignore
  builder.emit(
    Load(@semantic.LoadSpec::new(W32, None, F32, 20UL, Little, None)),
    [parameters[0]],
    [F32],
  )
  |> ignore
  builder.emit(
    Load(@semantic.LoadSpec::new(W64, None, F64, 24UL, Little, None)),
    [parameters[0]],
    [F64],
  )
  |> ignore
  builder.emit(
    Store(@semantic.StoreSpec::new(W16, I32, 6UL, Little, None)),
    [parameters[0], parameters[1]],
    [],
  )
  |> ignore
  builder.emit(
    Store(@semantic.StoreSpec::new(W64, I64, 32UL, Little, None)),
    [parameters[0], parameters[2]],
    [],
  )
  |> ignore
  builder.emit(
    Store(@semantic.StoreSpec::new(W32, F32, 40UL, Little, None)),
    [parameters[0], parameters[3]],
    [],
  )
  |> ignore
  builder.emit(
    Store(@semantic.StoreSpec::new(W64, F64, 48UL, Little, None)),
    [parameters[0], parameters[4]],
    [],
  )
  |> ignore
  builder.return_([loaded])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_memory(v0:ptr64, v1:i32, v2:i64, v3:f32, v4:f64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v5:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(I32, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v6:any-location(prefer=p6:int)@late]
      #|  i2 IncomingReg(I64, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v7:any-location(prefer=p2:int)@late]
      #|  i3 IncomingReg(F32, p0:fpvec) uses=[v3:fixed(p0:fpvec)@early] defs=[v8:any-location(prefer=p0:fpvec)@late]
      #|  i4 IncomingReg(F64, p1:fpvec) uses=[v4:fixed(p1:fpvec)@early] defs=[v9:any-location(prefer=p1:fpvec)@late]
      #|  i5 ScalarLoad(W8, Signed, I32, 3) uses=[v5:any@early] defs=[v10:any@late] source={ file: "memory.wat", line: 4, column: 7 } trap=MemoryOutOfBounds
      #|  i6 ScalarLoad(W32, Unsigned, I64, 12) uses=[v5:any@early] defs=[v11:any@late] trap=MemoryOutOfBounds
      #|  i7 ScalarLoad(W64, None, Ptr64, 16) uses=[v5:any@early] defs=[v12:any@late]
      #|  i8 ScalarLoad(W32, None, F32, 20) uses=[v5:any@early] defs=[v13:any@late]
      #|  i9 ScalarLoad(W64, None, F64, 24) uses=[v5:any@early] defs=[v14:any@late]
      #|  i10 ScalarStore(W16, I32, 6) uses=[v5:any@early, v6:any@early]
      #|  i11 ScalarStore(W64, I64, 32) uses=[v5:any@early, v7:any@early]
      #|  i12 ScalarStore(W32, F32, 40) uses=[v5:any@early, v8:any@early]
      #|  i13 ScalarStore(W64, F64, 48) uses=[v5:any@early, v9:any@early]
      #|  i14 OutgoingReg(I64, p0:int) uses=[v11:any@early]
      #|  i15 Return
      #|
    ),
  )
}

///|
test "X64 lowering rejects non-native scalar memory endianness" {
  let builder = @semantic.FunctionBuilder::new(
    "big_endian_load",
    Internal,
    [Ptr64],
    [I32],
  )
  let loaded = builder.emit(
      Load(
        @semantic.LoadSpec::new(
          W32,
          None,
          I32,
          0UL,
          Big,
          Some(MemoryOutOfBounds),
        ),
      ),
      builder.parameters(),
      [I32],
    )[0]
  builder.return_([loaded])
  try
    lower(builder.finish_selection_plan(), test_lowering_context()) |> ignore
  catch {
    error =>
      inspect(
        error,
        content=(
          #|UnsupportedOperation(
          #|  block_index=0,
          #|  instruction_index=0,
          #|  operation=Load(
          #|    {
          #|      width: W32,
          #|      extension: None,
          #|      result_type: I32,
          #|      offset: 0,
          #|      endianness: Big,
          #|      trap: Some(MemoryOutOfBounds),
          #|    },
          #|  ),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected big-endian scalar memory lowering to fail")
  }
}

///|
test "X64 lowering selects complete vector memory families" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_memory",
    Internal,
    [Ptr64, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let loaded = builder.emit(
      Load(
        @semantic.LoadSpec::new(
          W128,
          None,
          V128,
          16UL,
          Little,
          Some(MemoryOutOfBounds),
        ),
      ),
      [parameters[0]],
      [V128],
    )[0]
  builder.emit(
    Store(
      @semantic.StoreSpec::new(
        W128,
        V128,
        32UL,
        Little,
        Some(MemoryOutOfBounds),
      ),
    ),
    [parameters[0], loaded],
    [],
  )
  |> ignore
  builder.emit(
    VectorLoad(
      @semantic.VectorLoadSpec::new(
        Splat(I16x8),
        4UL,
        Little,
        Some(MemoryOutOfBounds),
      ),
    ),
    [parameters[0]],
    [V128],
  )
  |> ignore
  builder.emit(
    VectorLoad(
      @semantic.VectorLoadSpec::new(
        Extend(I32x4, Signed),
        8UL,
        Little,
        Some(MemoryOutOfBounds),
      ),
    ),
    [parameters[0]],
    [V128],
  )
  |> ignore
  builder.emit(
    VectorLoad(
      @semantic.VectorLoadSpec::new(
        Zero(W64),
        24UL,
        Little,
        Some(MemoryOutOfBounds),
      ),
    ),
    [parameters[0]],
    [V128],
  )
  |> ignore
  let lane = builder.emit(
      VectorLoad(
        @semantic.VectorLoadSpec::new(
          Lane(I8x16, 3),
          40UL,
          Little,
          Some(MemoryOutOfBounds),
        ),
      ),
      parameters,
      [V128],
    )[0]
  builder.emit(
    VectorStoreLane(
      @semantic.VectorStoreLaneSpec::new(
        I16x8,
        2,
        48UL,
        Little,
        Some(MemoryOutOfBounds),
      ),
    ),
    [parameters[0], lane],
    [],
  )
  |> ignore
  builder.return_([lane])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_memory(v0:ptr64, v1:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v2:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v3:any-location(prefer=p0:fpvec)@late]
      #|  i2 VectorLoad128(16) uses=[v2:any@early] defs=[v4:any@late] trap=MemoryOutOfBounds
      #|  i3 VectorStore128(32) uses=[v2:any@early, v4:any@early] trap=MemoryOutOfBounds
      #|  i4 VectorLoadSplat(I16x8, 4) uses=[v2:any@early] defs=[v5:any@late] trap=MemoryOutOfBounds
      #|  i5 VectorLoadExtend(I32x4, Signed, 8) uses=[v2:any@early] defs=[v6:any@late] trap=MemoryOutOfBounds
      #|  i6 VectorLoadZero(W64, 24) uses=[v2:any@early] defs=[v7:any@late] trap=MemoryOutOfBounds
      #|  i7 VectorLoadLane(I8x16, 3, 40) uses=[v2:any@early, v3:any@early] defs=[v8:any@late] trap=MemoryOutOfBounds
      #|  i8 VectorStoreLane(I16x8, 2, 48) uses=[v2:any@early, v8:any@early] trap=MemoryOutOfBounds
      #|  i9 OutgoingReg(V128, p0:fpvec) uses=[v8:any@early]
      #|  i10 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects non-trapping scalar floating-point operations" {
  let builder = @semantic.FunctionBuilder::new(
    "scalar_float",
    Internal,
    [Ptr64, F32, F32, F64, F64],
    [F32, F64, I32, I32],
  )
  let parameters = builder.parameters()
  let one = builder.emit(F32Const(0x3F800000U), [], [F32])[0]
  let negated = builder.emit(FloatUnary(Negate), [parameters[1]], [F32])[0]
  let sum = builder.emit(FloatBinary(Add), [negated, one], [F32])[0]
  let two = builder.emit(F64Const(0x4000000000000000UL), [], [F64])[0]
  let rooted = builder.emit(FloatUnary(SquareRoot), [parameters[3]], [F64])[0]
  let quotient = builder.emit(FloatBinary(Div), [rooted, two], [F64])[0]
  let less = builder.emit(
      FloatCompare(LessThan),
      [parameters[1], parameters[2]],
      [I32],
    )[0]
  let not_equal = builder.emit(
      FloatCompare(NotEqual),
      [parameters[3], parameters[4]],
      [I32],
    )[0]
  builder.return_([sum, quotient, less, not_equal])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_float(v0:ptr64, v1:f32, v2:f32, v3:f64, v4:f64) -> (f32, f64, i32, i32)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v5:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(F32, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v6:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(F32, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v7:any-location(prefer=p1:fpvec)@late]
      #|  i3 IncomingReg(F64, p2:fpvec) uses=[v3:fixed(p2:fpvec)@early] defs=[v8:any-location(prefer=p2:fpvec)@late]
      #|  i4 IncomingReg(F64, p3:fpvec) uses=[v4:fixed(p3:fpvec)@early] defs=[v9:any-location(prefer=p3:fpvec)@late]
      #|  i5 LoadFloatConstant(F32, 1065353216) defs=[v10:any@late]
      #|  i6 FloatUnary(F32, Negate) uses=[v6:any@early] defs=[v11:any@late]
      #|  i7 FloatBinary(F32, Add) uses=[v11:any@early, v10:any@early] defs=[v12:any@late]
      #|  i8 LoadFloatConstant(F64, 4611686018427387904) defs=[v13:any@late]
      #|  i9 FloatUnary(F64, SquareRoot) uses=[v8:any@early] defs=[v14:any@late]
      #|  i10 FloatBinary(F64, Div) uses=[v14:any@early, v13:any@early] defs=[v15:any@late]
      #|  i11 FloatCompareSet(F32, LessThan) uses=[v6:any@early, v7:any@early] defs=[v16:any@late]
      #|  i12 FloatCompareSet(F64, NotEqual) uses=[v8:any@early, v9:any@early] defs=[v17:any@late]
      #|  i13 OutgoingReg(F32, p0:fpvec) uses=[v12:any@early]
      #|  i14 OutgoingReg(F64, p1:fpvec) uses=[v15:any@early]
      #|  i15 OutgoingReg(I32, p0:int) uses=[v16:any@early]
      #|  i16 OutgoingReg(I32, p2:int) uses=[v17:any@early]
      #|  i17 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects scalar rounding and NaN predicates" {
  let builder = @semantic.FunctionBuilder::new(
    "scalar_float_rounding",
    Internal,
    [Ptr64, F32, F32, F64, F64],
    [F32, F64, I32, I32],
  )
  let parameters = builder.parameters()
  let ceil32 = builder.emit(FloatUnary(Ceil), [parameters[1]], [F32])[0]
  let floor32 = builder.emit(FloatUnary(Floor), [ceil32], [F32])[0]
  let truncate32 = builder.emit(FloatUnary(Truncate), [floor32], [F32])[0]
  let nearest32 = builder.emit(FloatUnary(Nearest), [truncate32], [F32])[0]
  let ceil64 = builder.emit(FloatUnary(Ceil), [parameters[3]], [F64])[0]
  let floor64 = builder.emit(FloatUnary(Floor), [ceil64], [F64])[0]
  let truncate64 = builder.emit(FloatUnary(Truncate), [floor64], [F64])[0]
  let nearest64 = builder.emit(FloatUnary(Nearest), [truncate64], [F64])[0]
  let ordered = builder.emit(
      FloatCompare(Ordered),
      [parameters[1], parameters[2]],
      [I32],
    )[0]
  let unordered = builder.emit(
      FloatCompare(Unordered),
      [parameters[3], parameters[4]],
      [I32],
    )[0]
  builder.return_([nearest32, nearest64, ordered, unordered])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_float_rounding(v0:ptr64, v1:f32, v2:f32, v3:f64, v4:f64) -> (f32, f64, i32, i32)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v5:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(F32, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v6:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(F32, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v7:any-location(prefer=p1:fpvec)@late]
      #|  i3 IncomingReg(F64, p2:fpvec) uses=[v3:fixed(p2:fpvec)@early] defs=[v8:any-location(prefer=p2:fpvec)@late]
      #|  i4 IncomingReg(F64, p3:fpvec) uses=[v4:fixed(p3:fpvec)@early] defs=[v9:any-location(prefer=p3:fpvec)@late]
      #|  i5 FloatUnary(F32, Ceil) uses=[v6:any@early] defs=[v10:any@late]
      #|  i6 FloatUnary(F32, Floor) uses=[v10:any@early] defs=[v11:any@late]
      #|  i7 FloatUnary(F32, Truncate) uses=[v11:any@early] defs=[v12:any@late]
      #|  i8 FloatUnary(F32, Nearest) uses=[v12:any@early] defs=[v13:any@late]
      #|  i9 FloatUnary(F64, Ceil) uses=[v8:any@early] defs=[v14:any@late]
      #|  i10 FloatUnary(F64, Floor) uses=[v14:any@early] defs=[v15:any@late]
      #|  i11 FloatUnary(F64, Truncate) uses=[v15:any@early] defs=[v16:any@late]
      #|  i12 FloatUnary(F64, Nearest) uses=[v16:any@early] defs=[v17:any@late]
      #|  i13 FloatCompareSet(F32, Ordered) uses=[v6:any@early, v7:any@early] defs=[v18:any@late]
      #|  i14 FloatCompareSet(F64, Unordered) uses=[v8:any@early, v9:any@early] defs=[v19:any@late]
      #|  i15 OutgoingReg(F32, p0:fpvec) uses=[v13:any@early]
      #|  i16 OutgoingReg(F64, p1:fpvec) uses=[v17:any@early]
      #|  i17 OutgoingReg(I32, p0:int) uses=[v18:any@early]
      #|  i18 OutgoingReg(I32, p2:int) uses=[v19:any@early]
      #|  i19 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects scalar min max and bit-exact copy-sign" {
  let builder = @semantic.FunctionBuilder::new(
    "scalar_float_minmax_copysign",
    Internal,
    [Ptr64],
    [F32, F64, F32, F64],
  )
  let positive_zero32 = builder.emit(F32Const(0U), [], [F32])[0]
  let negative_zero32 = builder.emit(F32Const(0x80000000U), [], [F32])[0]
  let positive_zero64 = builder.emit(F64Const(0UL), [], [F64])[0]
  let negative_zero64 = builder.emit(F64Const(0x8000000000000000UL), [], [F64])[0]
  let minimum = builder.emit(
      FloatBinary(Min),
      [positive_zero32, negative_zero32],
      [F32],
    )[0]
  let maximum = builder.emit(
      FloatBinary(Max),
      [negative_zero64, positive_zero64],
      [F64],
    )[0]
  let nan32 = builder.emit(F32Const(0x7FC12345U), [], [F32])[0]
  let copied32 = builder.emit(FloatBinary(CopySign), [nan32, negative_zero32], [
      F32,
    ])[0]
  let nan64 = builder.emit(F64Const(0xFFF8123456789ABCUL), [], [F64])[0]
  let copied64 = builder.emit(FloatBinary(CopySign), [nan64, positive_zero64], [
      F64,
    ])[0]
  builder.return_([minimum, maximum, copied32, copied64])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_float_minmax_copysign(v0:ptr64) -> (f32, f64, f32, f64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v1:any-location(prefer=p7:int)@late]
      #|  i1 IncomingResultArea(p10:int) defs=[v2:any-location@late]
      #|  i2 LoadFloatConstant(F32, 0) defs=[v3:any@late]
      #|  i3 LoadFloatConstant(F32, 2147483648) defs=[v4:any@late]
      #|  i4 LoadFloatConstant(F64, 0) defs=[v5:any@late]
      #|  i5 LoadFloatConstant(F64, 9223372036854775808) defs=[v6:any@late]
      #|  i6 FloatBinary(F32, Min) uses=[v3:any@early, v4:any@early] defs=[v7:any@late]
      #|  i7 FloatBinary(F64, Max) uses=[v6:any@early, v5:any@early] defs=[v8:any@late]
      #|  i8 LoadFloatConstant(F32, 2143363909) defs=[v9:any@late]
      #|  i9 FloatBinary(F32, CopySign) uses=[v9:any@early, v4:any@early] defs=[v10:any@late]
      #|  i10 LoadFloatConstant(F64, 18444512289894210236) defs=[v11:any@late]
      #|  i11 FloatBinary(F64, CopySign) uses=[v11:any@early, v5:any@early] defs=[v12:any@late]
      #|  i12 OutgoingReg(F32, p0:fpvec) uses=[v7:any@early]
      #|  i13 OutgoingReg(F64, p1:fpvec) uses=[v8:any@early]
      #|  i14 OutgoingAreaResult(F32, 0) uses=[v2:any@early, v10:any@early]
      #|  i15 OutgoingAreaResult(F64, 8) uses=[v2:any@early, v12:any@early]
      #|  i16 Return
      #|
    ),
  )
}

///|
test "X64 lowering maps all scalar fused operations explicitly" {
  let builder = @semantic.FunctionBuilder::new(
    "scalar_float_fused",
    Internal,
    [Ptr64, F32, F32, F32, F64, F64, F64],
    [F32, F64],
  )
  let parameters = builder.parameters()
  let add32 = builder.emit(
      FloatTernary(FusedMultiplyAdd),
      [parameters[1], parameters[2], parameters[3]],
      [F32],
    )[0]
  let negated_add32 = builder.emit(
      FloatTernary(FusedNegatedMultiplyAdd),
      [parameters[1], parameters[2], add32],
      [F32],
    )[0]
  let subtract32 = builder.emit(
      FloatTernary(FusedMultiplySubtract),
      [parameters[1], parameters[2], negated_add32],
      [F32],
    )[0]
  let negated_subtract32 = builder.emit(
      FloatTernary(FusedNegatedMultiplySubtract),
      [parameters[1], parameters[2], subtract32],
      [F32],
    )[0]
  let add64 = builder.emit(
      FloatTernary(FusedMultiplyAdd),
      [parameters[4], parameters[5], parameters[6]],
      [F64],
    )[0]
  let negated_add64 = builder.emit(
      FloatTernary(FusedNegatedMultiplyAdd),
      [parameters[4], parameters[5], add64],
      [F64],
    )[0]
  let subtract64 = builder.emit(
      FloatTernary(FusedMultiplySubtract),
      [parameters[4], parameters[5], negated_add64],
      [F64],
    )[0]
  let negated_subtract64 = builder.emit(
      FloatTernary(FusedNegatedMultiplySubtract),
      [parameters[4], parameters[5], subtract64],
      [F64],
    )[0]
  builder.return_([negated_subtract32, negated_subtract64])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_float_fused(v0:ptr64, v1:f32, v2:f32, v3:f32, v4:f64, v5:f64, v6:f64) -> (f32, f64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v7:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(F32, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v8:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(F32, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v9:any-location(prefer=p1:fpvec)@late]
      #|  i3 IncomingReg(F32, p2:fpvec) uses=[v3:fixed(p2:fpvec)@early] defs=[v10:any-location(prefer=p2:fpvec)@late]
      #|  i4 IncomingReg(F64, p3:fpvec) uses=[v4:fixed(p3:fpvec)@early] defs=[v11:any-location(prefer=p3:fpvec)@late]
      #|  i5 IncomingReg(F64, p4:fpvec) uses=[v5:fixed(p4:fpvec)@early] defs=[v12:any-location(prefer=p4:fpvec)@late]
      #|  i6 IncomingReg(F64, p5:fpvec) uses=[v6:fixed(p5:fpvec)@early] defs=[v13:any-location(prefer=p5:fpvec)@late]
      #|  i7 FloatTernary(F32, Fmadd) uses=[v8:any@early, v9:any@early, v10:any@early] defs=[v14:any@late]
      #|  i8 FloatTernary(F32, Fmsub) uses=[v8:any@early, v9:any@early, v14:any@early] defs=[v15:any@late]
      #|  i9 FloatTernary(F32, Fnmsub) uses=[v8:any@early, v9:any@early, v15:any@early] defs=[v16:any@late]
      #|  i10 FloatTernary(F32, Fnmadd) uses=[v8:any@early, v9:any@early, v16:any@early] defs=[v17:any@late]
      #|  i11 FloatTernary(F64, Fmadd) uses=[v11:any@early, v12:any@early, v13:any@early] defs=[v18:any@late]
      #|  i12 FloatTernary(F64, Fmsub) uses=[v11:any@early, v12:any@early, v18:any@early] defs=[v19:any@late]
      #|  i13 FloatTernary(F64, Fnmsub) uses=[v11:any@early, v12:any@early, v19:any@early] defs=[v20:any@late]
      #|  i14 FloatTernary(F64, Fnmadd) uses=[v11:any@early, v12:any@early, v20:any@early] defs=[v21:any@late]
      #|  i15 OutgoingReg(F32, p0:fpvec) uses=[v17:any@early]
      #|  i16 OutgoingReg(F64, p1:fpvec) uses=[v21:any@early]
      #|  i17 Return
      #|
    ),
  )
}

///|
test "X64 lowering selects non-trapping scalar conversions" {
  let builder = @semantic.FunctionBuilder::new(
    "scalar_conversions",
    Internal,
    [Ptr64, I32, I64, F32, F64],
    [I32, I64, F32, F64],
  )
  let parameters = builder.parameters()
  let wrapped0 = builder.emit(Convert(I32WrapI64), [parameters[2]], [I32])[0]
  let signed8 = builder.emit(Convert(SignExtend(I32, W8)), [wrapped0], [I32])[0]
  let bits32 = builder.emit(Convert(Bitcast(I32, F32)), [signed8], [F32])[0]
  let wrapped = builder.emit(Convert(Bitcast(F32, I32)), [bits32], [I32])[0]
  let signed = builder.emit(Convert(I64ExtendI32(Signed)), [parameters[1]], [
      I64,
    ])[0]
  let unsigned = builder.emit(
      Convert(I64ExtendI32(Unsigned)),
      [parameters[1]],
      [I64],
    )[0]
  let combined = builder.emit(IntBinary(Add), [signed, unsigned], [I64])[0]
  let signed16 = builder.emit(Convert(SignExtend(I64, W16)), [combined], [I64])[0]
  let bits64 = builder.emit(Convert(Bitcast(I64, F64)), [signed16], [F64])[0]
  let extended = builder.emit(Convert(Bitcast(F64, I64)), [bits64], [I64])[0]
  let demoted = builder.emit(Convert(F32DemoteF64), [parameters[4]], [F32])[0]
  let int_float32 = builder.emit(
      Convert(IntToFloat(I32, F32, Signed)),
      [parameters[1]],
      [F32],
    )[0]
  let float32 = builder.emit(FloatBinary(Add), [demoted, int_float32], [F32])[0]
  let promoted = builder.emit(Convert(F64PromoteF32), [parameters[3]], [F64])[0]
  let int_float64 = builder.emit(
      Convert(IntToFloat(I64, F64, Unsigned)),
      [parameters[2]],
      [F64],
    )[0]
  let float64 = builder.emit(FloatBinary(Add), [promoted, int_float64], [F64])[0]
  builder.return_([wrapped, extended, float32, float64])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_conversions(v0:ptr64, v1:i32, v2:i64, v3:f32, v4:f64) -> (i32, i64, f32, f64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v5:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(I32, p6:int) uses=[v1:fixed(p6:int)@early] defs=[v6:any-location(prefer=p6:int)@late]
      #|  i2 IncomingReg(I64, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v7:any-location(prefer=p2:int)@late]
      #|  i3 IncomingReg(F32, p0:fpvec) uses=[v3:fixed(p0:fpvec)@early] defs=[v8:any-location(prefer=p0:fpvec)@late]
      #|  i4 IncomingReg(F64, p1:fpvec) uses=[v4:fixed(p1:fpvec)@early] defs=[v9:any-location(prefer=p1:fpvec)@late]
      #|  i5 Convert(WrapI64ToI32) uses=[v7:any@early] defs=[v10:any@late]
      #|  i6 Convert(SignExtend(I32, W8)) uses=[v10:any@early] defs=[v11:any@late]
      #|  i7 Convert(Bitcast(I32, F32)) uses=[v11:any@early] defs=[v12:any@late]
      #|  i8 Convert(Bitcast(F32, I32)) uses=[v12:any@early] defs=[v13:any@late]
      #|  i9 Convert(ExtendI32ToI64(Signed)) uses=[v6:any@early] defs=[v14:any@late]
      #|  i10 Convert(ExtendI32ToI64(Unsigned)) uses=[v6:any@early] defs=[v15:any@late]
      #|  i11 IntBinary(W64, Add) uses=[v14:any@early, v15:any@early] defs=[v16:any@late]
      #|  i12 Convert(SignExtend(I64, W16)) uses=[v16:any@early] defs=[v17:any@late]
      #|  i13 Convert(Bitcast(I64, F64)) uses=[v17:any@early] defs=[v18:any@late]
      #|  i14 Convert(Bitcast(F64, I64)) uses=[v18:any@early] defs=[v19:any@late]
      #|  i15 Convert(DemoteF64ToF32) uses=[v9:any@early] defs=[v20:any@late]
      #|  i16 Convert(IntToFloat(I32, F32, Signed)) uses=[v6:any@early] defs=[v21:any@late]
      #|  i17 FloatBinary(F32, Add) uses=[v20:any@early, v21:any@early] defs=[v22:any@late]
      #|  i18 Convert(PromoteF32ToF64) uses=[v8:any@early] defs=[v23:any@late]
      #|  i19 Convert(IntToFloat(I64, F64, Unsigned)) uses=[v7:any@early] defs=[v24:any@late]
      #|  i20 FloatBinary(F64, Add) uses=[v23:any@early, v24:any@early] defs=[v25:any@late]
      #|  i21 OutgoingReg(I32, p0:int) uses=[v13:any@early]
      #|  i22 OutgoingReg(I64, p2:int) uses=[v19:any@early]
      #|  i23 OutgoingReg(F32, p0:fpvec) uses=[v22:any@early]
      #|  i24 OutgoingReg(F64, p1:fpvec) uses=[v25:any@early]
      #|  i25 Return
      #|
    ),
  )
}

///|
test "X64 lowering legalizes trapping and saturating float-to-int" {
  let builder = @semantic.FunctionBuilder::new(
    "float_to_int",
    Internal,
    [Ptr64, F32, F64],
    [I32, I64],
  )
  let parameters = builder.parameters()
  let trapping = builder.emit(
      Convert(FloatToInt(F32, I32, Signed, Trapping)),
      [parameters[1]],
      [I32],
    )[0]
  let saturating = builder.emit(
      Convert(FloatToInt(F64, I64, Unsigned, Saturating)),
      [parameters[2]],
      [I64],
    )[0]
  builder.return_([trapping, saturating])
  inspect(
    lower(builder.finish_selection_plan(), test_lowering_context()).summary(),
    content=(
      #|vcode float_to_int(v0:ptr64, v1:f32, v2:f64) -> (i32, i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p7:int) uses=[v0:fixed(p7:int)@early] defs=[v3:any-location(prefer=p7:int)@late]
      #|  i1 IncomingReg(F32, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any-location(prefer=p0:fpvec)@late]
      #|  i2 IncomingReg(F64, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any-location(prefer=p1:fpvec)@late]
      #|  i3 TrapIfFloat(F32, Unordered) uses=[v4:any@early] trap=InvalidConversionToInteger
      #|  i4 LoadFloatConstant(F32, 3472883712) defs=[v6:any@late]
      #|  i5 TrapIfFloat(F32, LessThan) uses=[v4:any@early, v6:any@early] trap=InvalidConversionToInteger
      #|  i6 LoadFloatConstant(F32, 1325400064) defs=[v7:any@late]
      #|  i7 TrapIfFloat(F32, GreaterOrEqual) uses=[v4:any@early, v7:any@early] trap=InvalidConversionToInteger
      #|  i8 Convert(FloatToInt(F32, I32, Signed)) uses=[v4:any@early] defs=[v8:any@late]
      #|  i9 Convert(FloatToIntSaturating(F64, I64, Unsigned)) uses=[v5:any@early] defs=[v9:any@late]
      #|  i10 OutgoingReg(I32, p0:int) uses=[v8:any@early]
      #|  i11 OutgoingReg(I64, p2:int) uses=[v9:any@early]
      #|  i12 Return
      #|
    ),
  )
}

///|
/// Regression test for ISS-365.
///
/// Every x64 variable shift and rotate takes its count in `cl`, so lowering
/// must declare the `rcx` clobber on all of them. `RotateLeft` used to be
/// lowered through a special-case path that emitted `Ror` without it, so the
/// register allocator was free to keep a live value in `rcx` across the
/// rotate. In large rotate-heavy functions it did exactly that, and a memory
/// index destroyed by the `cl` setup produced an out-of-bounds access.
///
/// This asserts the invariant over every shift and rotate form rather than a
/// single opcode, so a future lowering path cannot reintroduce the defect.
test "X64 lowering always declares the rcx clobber for shifts and rotates" {
  let shift_operations : Array[@semantic.IntBinaryOp] = [
    ShiftLeft,
    SignedShiftRight,
    UnsignedShiftRight,
    RotateLeft,
    RotateRight,
  ]
  let missing : Array[String] = []
  let seen : Array[String] = []
  for operation in shift_operations {
    for ty in [@native.ValueType::I32, I64] {
      let builder = @semantic.FunctionBuilder::new(
        "shift_clobber",
        Internal,
        [Ptr64, ty, ty],
        [ty],
      )
      let parameters = builder.parameters()
      let shifted = builder.emit(
          IntBinary(operation),
          [parameters[1], parameters[2]],
          [ty],
        )[0]
      builder.return_([shifted])
      let text = lower(builder.finish_selection_plan(), test_lowering_context()).summary()
      for line in text.split("\n") {
        let line = line.to_owned()
        if line.contains("IntBinary(") &&
          (
            line.contains(", Lsl)") ||
            line.contains(", Asr)") ||
            line.contains(", Lsr)") ||
            line.contains(", Ror)")
          ) {
          seen.push(line)
          if !line.contains("clobbers=[p1:int]") {
            missing.push(line)
          }
        }
      }
    }
  }
  // Each of the five operations lowers to one shift or rotate per width.
  assert_eq(seen.length(), 10)
  assert_eq(missing, [])
}
