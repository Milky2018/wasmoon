///|
test "AArch64 lowering selects scalar SSA and preserves source metadata" {
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
        Some(@semantic.SourceLocation::new("selected.wat", 3, 9)),
        [],
      ),
    )[0]
  builder.return_([sum])
  let selected = lower(builder.finish(), test_lowering_context())
  inspect(
    selected.summary(),
    content=(
      #|vcode selected_add(v0:i64, v1:i64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(I64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v2:any@late]
      #|  i1 IncomingReg(I64, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v3:any@late]
      #|  i2 IntBinary(W64, Add) uses=[v2:any@early, v3:any@early] defs=[v4:any@late] source={ file: "selected.wat", line: 3, column: 9 }
      #|  i3 OutgoingReg(I64, p0:int) uses=[v4:any@early]
      #|  i4 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering rejects unsupported valid operations structurally" {
  let builder = @semantic.FunctionBuilder::new(
    "unsupported_atomic_fence",
    Platform,
    [],
    [],
  )
  builder.emit(AtomicFence, [], []) |> ignore
  builder.return_([])
  try lower(builder.finish(), test_lowering_context()) |> ignore catch {
    error =>
      inspect(
        error,
        content=(
          #|UnsupportedOperation(
          #|  block_index=0,
          #|  instruction_index=0,
          #|  operation=AtomicFence,
          #|)
        ),
      )
  } noraise {
    _ => fail("expected unsupported float selection to fail")
  }
}

///|
test "AArch64 lowering selects the vector foundation" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_foundation(v0:ptr64, v1:i32, v2:i64, v3:f32, v4:f64, v5:v128, v6:v128, v7:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v8:any@late]
      #|  i1 IncomingReg(I32, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v9:any@late]
      #|  i2 IncomingReg(I64, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v10:any@late]
      #|  i3 IncomingReg(F32, p0:fpvec) uses=[v3:fixed(p0:fpvec)@early] defs=[v11:any@late]
      #|  i4 IncomingReg(F64, p1:fpvec) uses=[v4:fixed(p1:fpvec)@early] defs=[v12:any@late]
      #|  i5 IncomingReg(V128, p2:fpvec) uses=[v5:fixed(p2:fpvec)@early] defs=[v13:any@late]
      #|  i6 IncomingReg(V128, p3:fpvec) uses=[v6:fixed(p3:fpvec)@early] defs=[v14:any@late]
      #|  i7 IncomingReg(V128, p4:fpvec) uses=[v7:fixed(p4:fpvec)@early] defs=[v15:any@late]
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
test "AArch64 lowering selects vector lane movement" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_lane_movement(v0:ptr64, v1:v128) -> (v128, i32, i64, f32, f64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v2:any@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v3:any@late]
      #|  i2 VectorExtractLane(I8x16, 15, Some(Signed)) uses=[v3:any@early] defs=[v4:any@late]
      #|  i3 VectorExtractLane(I8x16, 0, Some(Unsigned)) uses=[v3:any@early] defs=[v5:any@late]
      #|  i4 VectorExtractLane(I16x8, 7, Some(Signed)) uses=[v3:any@early] defs=[v6:any@late]
      #|  i5 VectorExtractLane(I16x8, 0, Some(Unsigned)) uses=[v3:any@early] defs=[v7:any@late]
      #|  i6 VectorExtractLane(I32x4, 3, None) uses=[v3:any@early] defs=[v8:any@late]
      #|  i7 IntBinary(W32, Eor) uses=[v4:any@early, v5:any@early] defs=[v9:any@late]
      #|  i8 IntBinary(W32, Eor) uses=[v9:any@early, v6:any@early] defs=[v10:any@late]
      #|  i9 IntBinary(W32, Eor) uses=[v10:any@early, v7:any@early] defs=[v11:any@late]
      #|  i10 IntBinary(W32, Eor) uses=[v11:any@early, v8:any@early] defs=[v12:any@late]
      #|  i11 VectorExtractLane(I64x2, 1, None) uses=[v3:any@early] defs=[v13:any@late]
      #|  i12 VectorExtractLane(F32x4, 2, None) uses=[v3:any@early] defs=[v14:any@late]
      #|  i13 VectorExtractLane(F64x2, 1, None) uses=[v3:any@early] defs=[v15:any@late]
      #|  i14 VectorReplaceLane(I8x16, 15) uses=[v3:any@early, v12:any@early] defs=[v16:tied(0)@late]
      #|  i15 VectorReplaceLane(I16x8, 7) uses=[v16:any@early, v12:any@early] defs=[v17:tied(0)@late]
      #|  i16 VectorReplaceLane(I32x4, 3) uses=[v17:any@early, v12:any@early] defs=[v18:tied(0)@late]
      #|  i17 VectorReplaceLane(I64x2, 1) uses=[v18:any@early, v13:any@early] defs=[v19:tied(0)@late]
      #|  i18 VectorReplaceLane(F32x4, 2) uses=[v19:any@early, v14:any@early] defs=[v20:tied(0)@late]
      #|  i19 VectorReplaceLane(F64x2, 1) uses=[v20:any@early, v15:any@early] defs=[v21:tied(0)@late]
      #|  i20 OutgoingReg(V128, p0:fpvec) uses=[v21:any@early]
      #|  i21 OutgoingReg(I32, p0:int) uses=[v12:any@early]
      #|  i22 OutgoingReg(I64, p1:int) uses=[v13:any@early]
      #|  i23 OutgoingReg(F32, p1:fpvec) uses=[v14:any@early]
      #|  i24 OutgoingReg(F64, p2:fpvec) uses=[v15:any@early]
      #|  i25 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering selects vector shuffle and swizzle" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_permute(v0:ptr64, v1:v128, v2:v128, v3:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v4:any@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v5:any@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v6:any@late]
      #|  i3 IncomingReg(V128, p2:fpvec) uses=[v3:fixed(p2:fpvec)@early] defs=[v7:any@late]
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
test "AArch64 lowering selects basic vector integer arithmetic" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_integer_arithmetic(v0:ptr64, v1:v128, v2:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v3:any@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any@late]
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
test "AArch64 lowering selects vector integer shifts" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_integer_shifts(v0:ptr64, v1:v128, v2:i32) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v3:any@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any@late]
      #|  i2 IncomingReg(I32, p1:int) uses=[v2:fixed(p1:int)@early] defs=[v5:any@late]
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
test "AArch64 lowering selects vector integer comparisons" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_integer_comparisons(v0:ptr64, v1:v128, v2:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v3:any@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any@late]
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
test "AArch64 lowering selects saturating vector integer arithmetic" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_saturating_arithmetic(v0:ptr64, v1:v128, v2:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v3:any@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any@late]
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
test "AArch64 lowering selects vector integer min and max" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_integer_min_max(v0:ptr64, v1:v128, v2:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v3:any@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any@late]
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
test "AArch64 lowering selects legal vector unsigned averages" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_unsigned_average(v0:ptr64, v1:v128, v2:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v3:any@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any@late]
      #|  i3 VectorIntBinary(I8x16, AverageUnsigned) uses=[v4:any@early, v5:any@early] defs=[v6:any@late]
      #|  i4 VectorIntBinary(I16x8, AverageUnsigned) uses=[v6:any@early, v5:any@early] defs=[v7:any@late]
      #|  i5 OutgoingReg(V128, p0:fpvec) uses=[v7:any@early]
      #|  i6 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering selects vector byte population count" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_population_count(v0:ptr64, v1:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v2:any@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v3:any@late]
      #|  i2 VectorIntUnary(I8x16, PopulationCount) uses=[v3:any@early] defs=[v4:any@late]
      #|  i3 OutgoingReg(V128, p0:fpvec) uses=[v4:any@early]
      #|  i4 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering selects widening vector integer arithmetic" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_widening_arithmetic",
    Internal,
    [Ptr64, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let mut result = parameters[1]
  let lanes : Array[@semantic.VectorLane] = [I16x8, I32x4, I64x2]
  let signednesses : Array[@semantic.Signedness] = [Signed, Unsigned]
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_widening_arithmetic(v0:ptr64, v1:v128, v2:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v3:any@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any@late]
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
test "AArch64 lowering selects vector integer extension" {
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
  let signednesses : Array[@semantic.Signedness] = [Signed, Unsigned]
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_integer_extension(v0:ptr64, v1:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v2:any@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v3:any@late]
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
test "AArch64 lowering selects saturating vector narrowing" {
  let builder = @semantic.FunctionBuilder::new(
    "vector_narrowing",
    Internal,
    [Ptr64, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let mut result = parameters[1]
  let lanes : Array[@semantic.VectorLane] = [I8x16, I16x8]
  let signednesses : Array[@semantic.Signedness] = [Signed, Unsigned]
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_narrowing(v0:ptr64, v1:v128, v2:v128) -> (v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v3:any@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any@late]
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
test "AArch64 lowering selects vector truth predicates" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_truth_predicates(v0:ptr64, v1:v128) -> (i32, i32, i32, i32, i32)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v2:any@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v3:any@late]
      #|  i2 VectorPredicate(AnyTrue) uses=[v3:any@early] defs=[v4:any@late]
      #|  i3 VectorPredicate(AllTrue(I8x16)) uses=[v3:any@early] defs=[v5:any@late]
      #|  i4 VectorPredicate(AllTrue(I16x8)) uses=[v3:any@early] defs=[v6:any@late]
      #|  i5 VectorPredicate(AllTrue(I32x4)) uses=[v3:any@early] defs=[v7:any@late]
      #|  i6 VectorPredicate(AllTrue(I64x2)) uses=[v3:any@early] defs=[v8:any@late]
      #|  i7 OutgoingReg(I32, p0:int) uses=[v4:any@early]
      #|  i8 OutgoingReg(I32, p1:int) uses=[v5:any@early]
      #|  i9 OutgoingReg(I32, p2:int) uses=[v6:any@early]
      #|  i10 OutgoingReg(I32, p3:int) uses=[v7:any@early]
      #|  i11 OutgoingReg(I32, p4:int) uses=[v8:any@early]
      #|  i12 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering selects vector integer bitmasks" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_integer_bitmasks(v0:ptr64, v1:v128) -> (i32, i32, i32, i32)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v2:any@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v3:any@late]
      #|  i2 VectorPredicate(BitMask(I8x16)) uses=[v3:any@early] defs=[v4:any@late]
      #|  i3 VectorPredicate(BitMask(I16x8)) uses=[v3:any@early] defs=[v5:any@late]
      #|  i4 VectorPredicate(BitMask(I32x4)) uses=[v3:any@early] defs=[v6:any@late]
      #|  i5 VectorPredicate(BitMask(I64x2)) uses=[v3:any@early] defs=[v7:any@late]
      #|  i6 OutgoingReg(I32, p0:int) uses=[v4:any@early]
      #|  i7 OutgoingReg(I32, p1:int) uses=[v5:any@early]
      #|  i8 OutgoingReg(I32, p2:int) uses=[v6:any@early]
      #|  i9 OutgoingReg(I32, p3:int) uses=[v7:any@early]
      #|  i10 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering selects every non-fused vector float operation" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode vector_float_operations(v0:ptr64, v1:v128, v2:v128) -> (v128, v128, v128, v128)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v3:any@late]
      #|  i1 IncomingReg(V128, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any@late]
      #|  i2 IncomingReg(V128, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any@late]
      #|  i3 VectorFloatUnary(F32x4, Absolute) uses=[v4:any@early] defs=[v6:any@late]
      #|  i4 VectorFloatUnary(F32x4, Negate) uses=[v6:any@early] defs=[v7:any@late]
      #|  i5 VectorFloatUnary(F32x4, SquareRoot) uses=[v7:any@early] defs=[v8:any@late]
      #|  i6 VectorFloatUnary(F32x4, Ceil) uses=[v8:any@early] defs=[v9:any@late]
      #|  i7 VectorFloatUnary(F32x4, Floor) uses=[v9:any@early] defs=[v10:any@late]
      #|  i8 VectorFloatUnary(F32x4, Truncate) uses=[v10:any@early] defs=[v11:any@late]
      #|  i9 VectorFloatUnary(F32x4, Nearest) uses=[v11:any@early] defs=[v12:any@late]
      #|  i10 VectorFloatBinary(F32x4, Add) uses=[v12:any@early, v5:any@early] defs=[v13:any@late]
      #|  i11 VectorFloatBinary(F32x4, Sub) uses=[v13:any@early, v5:any@early] defs=[v14:any@late]
      #|  i12 VectorFloatBinary(F32x4, Mul) uses=[v14:any@early, v5:any@early] defs=[v15:any@late]
      #|  i13 VectorFloatBinary(F32x4, Div) uses=[v15:any@early, v5:any@early] defs=[v16:any@late]
      #|  i14 VectorFloatBinary(F32x4, Min) uses=[v16:any@early, v5:any@early] defs=[v17:any@late]
      #|  i15 VectorFloatBinary(F32x4, Max) uses=[v17:any@early, v5:any@early] defs=[v18:any@late]
      #|  i16 VectorFloatBinary(F32x4, PseudoMin) uses=[v18:any@early, v5:any@early] defs=[v19:any@late]
      #|  i17 VectorFloatBinary(F32x4, PseudoMax) uses=[v19:any@early, v5:any@early] defs=[v20:any@late]
      #|  i18 VectorFloatCompare(F32x4, Equal) uses=[v4:any@early, v5:any@early] defs=[v21:any@late]
      #|  i19 VectorFloatCompare(F32x4, NotEqual) uses=[v21:any@early, v5:any@early] defs=[v22:any@late]
      #|  i20 VectorFloatCompare(F32x4, LessThan) uses=[v22:any@early, v5:any@early] defs=[v23:any@late]
      #|  i21 VectorFloatCompare(F32x4, LessOrEqual) uses=[v23:any@early, v5:any@early] defs=[v24:any@late]
      #|  i22 VectorFloatCompare(F32x4, GreaterThan) uses=[v24:any@early, v5:any@early] defs=[v25:any@late]
      #|  i23 VectorFloatCompare(F32x4, GreaterOrEqual) uses=[v25:any@early, v5:any@early] defs=[v26:any@late]
      #|  i24 VectorFloatUnary(F64x2, Absolute) uses=[v4:any@early] defs=[v27:any@late]
      #|  i25 VectorFloatUnary(F64x2, Negate) uses=[v27:any@early] defs=[v28:any@late]
      #|  i26 VectorFloatUnary(F64x2, SquareRoot) uses=[v28:any@early] defs=[v29:any@late]
      #|  i27 VectorFloatUnary(F64x2, Ceil) uses=[v29:any@early] defs=[v30:any@late]
      #|  i28 VectorFloatUnary(F64x2, Floor) uses=[v30:any@early] defs=[v31:any@late]
      #|  i29 VectorFloatUnary(F64x2, Truncate) uses=[v31:any@early] defs=[v32:any@late]
      #|  i30 VectorFloatUnary(F64x2, Nearest) uses=[v32:any@early] defs=[v33:any@late]
      #|  i31 VectorFloatBinary(F64x2, Add) uses=[v33:any@early, v5:any@early] defs=[v34:any@late]
      #|  i32 VectorFloatBinary(F64x2, Sub) uses=[v34:any@early, v5:any@early] defs=[v35:any@late]
      #|  i33 VectorFloatBinary(F64x2, Mul) uses=[v35:any@early, v5:any@early] defs=[v36:any@late]
      #|  i34 VectorFloatBinary(F64x2, Div) uses=[v36:any@early, v5:any@early] defs=[v37:any@late]
      #|  i35 VectorFloatBinary(F64x2, Min) uses=[v37:any@early, v5:any@early] defs=[v38:any@late]
      #|  i36 VectorFloatBinary(F64x2, Max) uses=[v38:any@early, v5:any@early] defs=[v39:any@late]
      #|  i37 VectorFloatBinary(F64x2, PseudoMin) uses=[v39:any@early, v5:any@early] defs=[v40:any@late]
      #|  i38 VectorFloatBinary(F64x2, PseudoMax) uses=[v40:any@early, v5:any@early] defs=[v41:any@late]
      #|  i39 VectorFloatCompare(F64x2, Equal) uses=[v4:any@early, v5:any@early] defs=[v42:any@late]
      #|  i40 VectorFloatCompare(F64x2, NotEqual) uses=[v42:any@early, v5:any@early] defs=[v43:any@late]
      #|  i41 VectorFloatCompare(F64x2, LessThan) uses=[v43:any@early, v5:any@early] defs=[v44:any@late]
      #|  i42 VectorFloatCompare(F64x2, LessOrEqual) uses=[v44:any@early, v5:any@early] defs=[v45:any@late]
      #|  i43 VectorFloatCompare(F64x2, GreaterThan) uses=[v45:any@early, v5:any@early] defs=[v46:any@late]
      #|  i44 VectorFloatCompare(F64x2, GreaterOrEqual) uses=[v46:any@early, v5:any@early] defs=[v47:any@late]
      #|  i45 OutgoingReg(V128, p0:fpvec) uses=[v20:any@early]
      #|  i46 OutgoingReg(V128, p1:fpvec) uses=[v26:any@early]
      #|  i47 OutgoingReg(V128, p2:fpvec) uses=[v41:any@early]
      #|  i48 OutgoingReg(V128, p3:fpvec) uses=[v47:any@early]
      #|  i49 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering assigns one aligned semantic stack-object area" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode stack_object_layout(v0:ptr64) -> (ptr64, ptr64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v1:any@late]
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
      #|  i4 OutgoingReg(Ptr64, p1:int) uses=[v3:any@early]
      #|  i5 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering inserts explicit traps before signed division" {
  let builder = @semantic.FunctionBuilder::new(
    "checked_divide",
    Platform,
    [I64, I64],
    [I64],
  )
  let value = builder.emit(IntBinary(SignedDiv), builder.parameters(), [I64])[0]
  builder.return_([value])
  inspect(
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode checked_divide(v0:i64, v1:i64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(I64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v2:any@late]
      #|  i1 IncomingReg(I64, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v3:any@late]
      #|  i2 TrapIfZero(W64) uses=[v3:any@early] trap=IntegerDivisionByZero
      #|  i3 TrapIfSignedDivOverflow(W64) uses=[v2:any@early, v3:any@early] trap=IntegerOverflow
      #|  i4 IntBinary(W64, Sdiv) uses=[v2:any@early, v3:any@early] defs=[v4:any@late]
      #|  i5 OutgoingReg(I64, p0:int) uses=[v4:any@early]
      #|  i6 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering legalizes remaining pure scalar integer operations" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode pure_integer_operations(v0:ptr64, v1:i32, v2:i32, v3:i64, v4:i64) -> (i32, i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v5:any@late]
      #|  i1 IncomingReg(I32, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v6:any@late]
      #|  i2 IncomingReg(I32, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v7:any@late]
      #|  i3 IncomingReg(I64, p3:int) uses=[v3:fixed(p3:int)@early] defs=[v8:any@late]
      #|  i4 IncomingReg(I64, p4:int) uses=[v4:fixed(p4:int)@early] defs=[v9:any@late]
      #|  i5 IntUnary(W32, Rbit) uses=[v6:any@early] defs=[v10:any@late]
      #|  i6 IntUnary(W32, Clz) uses=[v10:any@early] defs=[v11:any@late]
      #|  i7 PopulationCount(W32) uses=[v6:any@early] defs=[v12:any@late]
      #|  i8 IntUnary(W32, Neg) uses=[v12:any@early] defs=[v13:any@late]
      #|  i9 IntBinary(W32, Ror) uses=[v11:any@early, v13:any@early] defs=[v14:any@late]
      #|  i10 IntHighMultiply(W32, Signed) uses=[v14:any@early, v7:any@early] defs=[v15:any@late]
      #|  i11 IntHighMultiply(W32, Unsigned) uses=[v15:any@early, v12:any@early] defs=[v16:any@late]
      #|  i12 IntUnary(W64, Rbit) uses=[v8:any@early] defs=[v17:any@late]
      #|  i13 IntUnary(W64, Clz) uses=[v17:any@early] defs=[v18:any@late]
      #|  i14 PopulationCount(W64) uses=[v8:any@early] defs=[v19:any@late]
      #|  i15 IntUnary(W64, Neg) uses=[v19:any@early] defs=[v20:any@late]
      #|  i16 IntBinary(W64, Ror) uses=[v18:any@early, v20:any@early] defs=[v21:any@late]
      #|  i17 IntHighMultiply(W64, Signed) uses=[v21:any@early, v9:any@early] defs=[v22:any@late]
      #|  i18 IntHighMultiply(W64, Unsigned) uses=[v22:any@early, v19:any@early] defs=[v23:any@late]
      #|  i19 OutgoingReg(I32, p0:int) uses=[v16:any@early]
      #|  i20 OutgoingReg(I64, p1:int) uses=[v23:any@early]
      #|  i21 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering selects every scalar overflow arithmetic contract" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode overflow_arithmetic(v0:ptr64, v1:i32, v2:i32, v3:i64, v4:i64) -> (i32, i64, i32)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v5:any@late]
      #|  i1 IncomingReg(I32, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v6:any@late]
      #|  i2 IncomingReg(I32, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v7:any@late]
      #|  i3 IncomingReg(I64, p3:int) uses=[v3:fixed(p3:int)@early] defs=[v8:any@late]
      #|  i4 IncomingReg(I64, p4:int) uses=[v4:fixed(p4:int)@early] defs=[v9:any@late]
      #|  i5 LoadConstant(W32, 0) defs=[v10:any@late]
      #|  i6 IntWithOverflow(W32, Add(Signed)) uses=[v6:any@early, v7:any@early] defs=[v11:any@late, v12:any@late]
      #|  i7 IntBinary(W32, Orr) uses=[v10:any@early, v12:any@early] defs=[v13:any@late]
      #|  i8 IntWithOverflow(W32, Add(Unsigned)) uses=[v11:any@early, v7:any@early] defs=[v14:any@late, v15:any@late]
      #|  i9 IntBinary(W32, Orr) uses=[v13:any@early, v15:any@early] defs=[v16:any@late]
      #|  i10 IntWithOverflow(W32, Sub(Signed)) uses=[v14:any@early, v7:any@early] defs=[v17:any@late, v18:any@late]
      #|  i11 IntBinary(W32, Orr) uses=[v16:any@early, v18:any@early] defs=[v19:any@late]
      #|  i12 IntWithOverflow(W32, Sub(Unsigned)) uses=[v17:any@early, v7:any@early] defs=[v20:any@late, v21:any@late]
      #|  i13 IntBinary(W32, Orr) uses=[v19:any@early, v21:any@early] defs=[v22:any@late]
      #|  i14 IntWithOverflow(W32, Mul(Signed)) uses=[v20:any@early, v7:any@early] defs=[v23:any@late, v24:any@late]
      #|  i15 IntBinary(W32, Orr) uses=[v22:any@early, v24:any@early] defs=[v25:any@late]
      #|  i16 IntWithOverflow(W32, Mul(Unsigned)) uses=[v23:any@early, v7:any@early] defs=[v26:any@late, v27:any@late]
      #|  i17 IntBinary(W32, Orr) uses=[v25:any@early, v27:any@early] defs=[v28:any@late]
      #|  i18 IntWithOverflow(W64, Add(Signed)) uses=[v8:any@early, v9:any@early] defs=[v29:any@late, v30:any@late]
      #|  i19 IntBinary(W32, Orr) uses=[v28:any@early, v30:any@early] defs=[v31:any@late]
      #|  i20 IntWithOverflow(W64, Add(Unsigned)) uses=[v29:any@early, v9:any@early] defs=[v32:any@late, v33:any@late]
      #|  i21 IntBinary(W32, Orr) uses=[v31:any@early, v33:any@early] defs=[v34:any@late]
      #|  i22 IntWithOverflow(W64, Sub(Signed)) uses=[v32:any@early, v9:any@early] defs=[v35:any@late, v36:any@late]
      #|  i23 IntBinary(W32, Orr) uses=[v34:any@early, v36:any@early] defs=[v37:any@late]
      #|  i24 IntWithOverflow(W64, Sub(Unsigned)) uses=[v35:any@early, v9:any@early] defs=[v38:any@late, v39:any@late]
      #|  i25 IntBinary(W32, Orr) uses=[v37:any@early, v39:any@early] defs=[v40:any@late]
      #|  i26 IntWithOverflow(W64, Mul(Signed)) uses=[v38:any@early, v9:any@early] defs=[v41:any@late, v42:any@late]
      #|  i27 IntBinary(W32, Orr) uses=[v40:any@early, v42:any@early] defs=[v43:any@late]
      #|  i28 IntWithOverflow(W64, Mul(Unsigned)) uses=[v41:any@early, v9:any@early] defs=[v44:any@late, v45:any@late]
      #|  i29 IntBinary(W32, Orr) uses=[v43:any@early, v45:any@early] defs=[v46:any@late]
      #|  i30 OutgoingReg(I32, p0:int) uses=[v26:any@early]
      #|  i31 OutgoingReg(I64, p1:int) uses=[v44:any@early]
      #|  i32 OutgoingReg(I32, p2:int) uses=[v46:any@early]
      #|  i33 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering selects null carriers references and scalar values" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_carriers_and_select(v0:ptr64, v1:i32, v2:i32, v3:i64, v4:i64, v5:f32, v6:f32, v7:f64, v8:f64) -> (i32, i32, i32, i64, ptr64, gcref64, f32, f64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v9:any@late]
      #|  i1 IncomingReg(I32, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v10:any@late]
      #|  i2 IncomingReg(I32, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v11:any@late]
      #|  i3 IncomingReg(I64, p3:int) uses=[v3:fixed(p3:int)@early] defs=[v12:any@late]
      #|  i4 IncomingReg(I64, p4:int) uses=[v4:fixed(p4:int)@early] defs=[v13:any@late]
      #|  i5 IncomingReg(F32, p0:fpvec) uses=[v5:fixed(p0:fpvec)@early] defs=[v14:any@late]
      #|  i6 IncomingReg(F32, p1:fpvec) uses=[v6:fixed(p1:fpvec)@early] defs=[v15:any@late]
      #|  i7 IncomingReg(F64, p2:fpvec) uses=[v7:fixed(p2:fpvec)@early] defs=[v16:any@late]
      #|  i8 IncomingReg(F64, p3:fpvec) uses=[v8:fixed(p3:fpvec)@early] defs=[v17:any@late]
      #|  i9 LoadNull(Ptr64) defs=[v18:any@late]
      #|  i10 LoadNull(GcRef64) defs=[v19:any@late]
      #|  i11 CarrierMove(I64, GcRef64) uses=[v12:any@early] defs=[v20:any@late]
      #|  i12 CarrierMove(GcRef64, Ptr64) uses=[v20:any@early] defs=[v21:any@late]
      #|  i13 ReferenceCompareSet(Ptr64, Eq) uses=[v18:any@early, v21:any@early] defs=[v22:any@late]
      #|  i14 ReferenceCompareSet(GcRef64, Ne) uses=[v19:any@early, v20:any@early] defs=[v23:any@late]
      #|  i15 Select(I32) uses=[v10:any@early, v10:any@early, v11:any@early] defs=[v24:any@late]
      #|  i16 Select(I64) uses=[v10:any@early, v12:any@early, v13:any@early] defs=[v25:any@late]
      #|  i17 Select(Ptr64) uses=[v10:any@early, v18:any@early, v21:any@early] defs=[v26:any@late]
      #|  i18 Select(GcRef64) uses=[v10:any@early, v19:any@early, v20:any@early] defs=[v27:any@late]
      #|  i19 Select(F32) uses=[v10:any@early, v14:any@early, v15:any@early] defs=[v28:any@late]
      #|  i20 Select(F64) uses=[v10:any@early, v16:any@early, v17:any@early] defs=[v29:any@late]
      #|  i21 OutgoingReg(I32, p0:int) uses=[v22:any@early]
      #|  i22 OutgoingReg(I32, p1:int) uses=[v23:any@early]
      #|  i23 OutgoingReg(I32, p2:int) uses=[v24:any@early]
      #|  i24 OutgoingReg(I64, p3:int) uses=[v25:any@early]
      #|  i25 OutgoingReg(Ptr64, p4:int) uses=[v26:any@early]
      #|  i26 OutgoingReg(GcRef64, p5:int) uses=[v27:any@early]
      #|  i27 OutgoingReg(F32, p0:fpvec) uses=[v28:any@early]
      #|  i28 OutgoingReg(F64, p1:fpvec) uses=[v29:any@early]
      #|  i29 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering resolves environment paths and typed symbol addresses" {
  let field = @semantic.EnvironmentField::new("runtime.memory.base", I64)
  let builder = @semantic.FunctionBuilder::new(
    "addresses_and_environment",
    Internal,
    [Ptr64],
    [Ptr64, Ptr64, Ptr64, I64],
  )
  let code = builder.emit(
      CodeAddress(@semantic.CodeSymbol::new("callee")),
      [],
      [Ptr64],
    )[0]
  let external = builder.emit(
      ExternalAddress(@semantic.ExternalSymbol::new("runtime.helper")),
      [],
      [Ptr64],
    )[0]
  let data = builder.emit(
      DataAddress(@semantic.DataSymbol::new("constant.pool")),
      [],
      [Ptr64],
    )[0]
  let environment = builder.emit(
      EnvironmentField(field),
      [builder.parameters()[0]],
      [I64],
    )[0]
  builder.return_([code, external, data, environment])
  let context = test_lowering_context().with_environment_field(field, [8, 24])
  inspect(
    lower(builder.finish(), context).summary(),
    content=(
      #|vcode addresses_and_environment(v0:ptr64) -> (ptr64, ptr64, ptr64, i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v1:any@late]
      #|  i1 LoadAddress(Code({ name: "callee" })) defs=[v2:any@late]
      #|  i2 LoadAddress(External({ name: "runtime.helper" })) defs=[v3:any@late]
      #|  i3 LoadAddress(Data({ name: "constant.pool" })) defs=[v4:any@late]
      #|  i4 ScalarLoad(W64, None, Ptr64, 8) uses=[v1:any@early] defs=[v5:any@late]
      #|  i5 ScalarLoad(W64, None, I64, 24) uses=[v5:any@early] defs=[v6:any@late]
      #|  i6 OutgoingReg(Ptr64, p0:int) uses=[v2:any@early]
      #|  i7 OutgoingReg(Ptr64, p1:int) uses=[v3:any@early]
      #|  i8 OutgoingReg(Ptr64, p2:int) uses=[v4:any@early]
      #|  i9 OutgoingReg(I64, p3:int) uses=[v6:any@early]
      #|  i10 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering selects a direct platform call with explicit ABI facts" {
  let builder = @semantic.FunctionBuilder::new(
    "direct_platform_call",
    Platform,
    [I64, F64],
    [I64],
  )
  let call = @semantic.SemanticCall::new(
    External(@semantic.ExternalSymbol::new("runtime.helper")),
    @semantic.Signature::new([I64, F64], [I64]),
    Platform,
    @semantic.CallBehavior::new(ReadWrite, true, true, true, true),
  )
  let result = builder.emit_with_metadata(
      Call(call),
      builder.parameters(),
      [I64],
      @semantic.InstructionMetadata::new(
        Some(@semantic.SourceLocation::new("call.wat", 7, 11)),
        [],
      ),
    )[0]
  builder.return_([result])
  inspect(
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode direct_platform_call(v0:i64, v1:f64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(I64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v2:any@late]
      #|  i1 IncomingReg(F64, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v3:any@late]
      #|  i2 PlatformCall(
      #|  { name: "runtime.helper" },
      #|  { params: [I64, F64], results: [I64] },
      #|) uses=[v2:any@early, v3:any@early] clobbers=[p0:int, p1:int, p2:int, p3:int, p4:int, p5:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p12:int, p13:int, p14:int, p15:int, p16:int, p17:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec, p16:fpvec, p17:fpvec, p18:fpvec, p19:fpvec, p20:fpvec, p21:fpvec, p22:fpvec, p23:fpvec, p24:fpvec, p25:fpvec, p26:fpvec, p27:fpvec, p28:fpvec, p29:fpvec, p30:fpvec, p31:fpvec] source={ file: "call.wat", line: 7, column: 11 } safepoint=GcAndCancellation
      #|  i3 IncomingCallResult(I64, p0:int) defs=[v4:any@late]
      #|  i4 OutgoingReg(I64, p0:int) uses=[v4:any@early]
      #|  i5 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering derives internal entry and direct-call layouts" {
  let builder = @semantic.FunctionBuilder::new(
    "direct_internal_call",
    Internal,
    [Ptr64, I64, F64],
    [I64],
  )
  let call = @semantic.SemanticCall::new(
    Internal(@semantic.CodeSymbol::new("wasm.func.7")),
    @semantic.Signature::new([Ptr64, I64, F64], [I64]),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, true, true),
  )
  let result = builder.emit(Call(call), builder.parameters(), [I64])[0]
  builder.return_([result])
  inspect(
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode direct_internal_call(v0:ptr64, v1:i64, v2:f64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v3:any@late]
      #|  i1 IncomingReg(I64, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v4:any@late]
      #|  i2 IncomingReg(F64, p0:fpvec) uses=[v2:fixed(p0:fpvec)@early] defs=[v5:any@late]
      #|  i3 InternalCall(
      #|  { name: "wasm.func.7" },
      #|  { params: [Ptr64, I64, F64], results: [I64] },
      #|  {
      #|    arguments: [CallRegister(p0:int), CallRegister(p1:int), CallRegister(p0:fpvec)],
      #|    results: [p0:int],
      #|    stack_size: 0,
      #|  },
      #|) uses=[v3:any@early, v4:any@early, v5:any@early] clobbers=[p0:int, p1:int, p2:int, p3:int, p4:int, p5:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p12:int, p13:int, p14:int, p15:int, p16:int, p17:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec, p16:fpvec, p17:fpvec, p18:fpvec, p19:fpvec, p20:fpvec, p21:fpvec, p22:fpvec, p23:fpvec, p24:fpvec, p25:fpvec, p26:fpvec, p27:fpvec, p28:fpvec, p29:fpvec, p30:fpvec, p31:fpvec] safepoint=GcAndCancellation
      #|  i4 IncomingCallResult(I64, p0:int) defs=[v6:any@late]
      #|  i5 OutgoingReg(I64, p0:int) uses=[v6:any@early]
      #|  i6 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering keeps the indirect callee outside the logical signature" {
  let builder = @semantic.FunctionBuilder::new(
    "indirect_internal_call",
    Internal,
    [Ptr64, Ptr64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let call = @semantic.SemanticCall::new(
    Indirect,
    @semantic.Signature::new([Ptr64, I64], [I64]),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  let result = builder.emit(
      Call(call),
      [parameters[1], parameters[0], parameters[2]],
      [I64],
    )[0]
  builder.return_([result])
  inspect(
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode indirect_internal_call(v0:ptr64, v1:ptr64, v2:i64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v3:any@late]
      #|  i1 IncomingReg(Ptr64, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v4:any@late]
      #|  i2 IncomingReg(I64, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v5:any@late]
      #|  i3 InternalCallIndirect(
      #|  { params: [Ptr64, I64], results: [I64] },
      #|  {
      #|    arguments: [CallRegister(p0:int), CallRegister(p1:int)],
      #|    results: [p0:int],
      #|    stack_size: 0,
      #|  },
      #|) uses=[v4:any@early, v3:any@early, v5:any@early] clobbers=[p0:int, p1:int, p2:int, p3:int, p4:int, p5:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p12:int, p13:int, p14:int, p15:int, p16:int, p17:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec, p16:fpvec, p17:fpvec, p18:fpvec, p19:fpvec, p20:fpvec, p21:fpvec, p22:fpvec, p23:fpvec, p24:fpvec, p25:fpvec, p26:fpvec, p27:fpvec, p28:fpvec, p29:fpvec, p30:fpvec, p31:fpvec]
      #|  i4 IncomingCallResult(I64, p0:int) defs=[v6:any@late]
      #|  i5 OutgoingReg(I64, p0:int) uses=[v6:any@early]
      #|  i6 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering selects a compatible true internal tail call" {
  let builder = @semantic.FunctionBuilder::new(
    "direct_tail_call",
    Internal,
    [Ptr64, I64],
    [I64],
  )
  let call = @semantic.SemanticCall::new(
    Internal(@semantic.CodeSymbol::new("wasm.func.9")),
    @semantic.Signature::new([Ptr64, I64], [I64]),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.tail_call(call, builder.parameters())
  inspect(
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode direct_tail_call(v0:ptr64, v1:i64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v2:any@late]
      #|  i1 IncomingReg(I64, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v3:any@late]
      #|  i2 TailCallDirect(
      #|  { name: "wasm.func.9" },
      #|  { params: [Ptr64, I64], results: [I64] },
      #|  {
      #|    arguments: [CallRegister(p0:int), CallRegister(p1:int)],
      #|    results: [p0:int],
      #|    stack_size: 0,
      #|  },
      #|) uses=[v2:any@early, v3:any@early] clobbers=[p0:int, p1:int, p2:int, p3:int, p4:int, p5:int, p6:int, p7:int, p8:int, p9:int, p10:int, p11:int, p12:int, p13:int, p14:int, p15:int, p16:int, p17:int, p0:fpvec, p1:fpvec, p2:fpvec, p3:fpvec, p4:fpvec, p5:fpvec, p6:fpvec, p7:fpvec, p8:fpvec, p9:fpvec, p10:fpvec, p11:fpvec, p12:fpvec, p13:fpvec, p14:fpvec, p15:fpvec, p16:fpvec, p17:fpvec, p18:fpvec, p19:fpvec, p20:fpvec, p21:fpvec, p22:fpvec, p23:fpvec, p24:fpvec, p25:fpvec, p26:fpvec, p27:fpvec, p28:fpvec, p29:fpvec, p30:fpvec, p31:fpvec]
      #|
    ),
  )
}

///|
test "AArch64 rejects tail stack arguments that cannot replace the incoming area" {
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
    Internal(@semantic.CodeSymbol::new("wasm.func.10")),
    @semantic.Signature::new([Ptr64, I64, I64, I64, I64, I64, I64, I64, I64], []),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.tail_call(call, operands)
  try lower(builder.finish(), test_lowering_context()) |> ignore catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidTarget(
          #|  cause=InvalidInstruction(
          #|    instruction=i9,
          #|    message="tail-call plan is not compatible with the current function",
          #|  ),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected an oversized true tail call to be rejected")
  }
}

///|
test "AArch64 lowering selects typed scalar memory operations and traps" {
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
      Some(@semantic.SourceLocation::new("memory.wat", 4, 7)),
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_memory(v0:ptr64, v1:i32, v2:i64, v3:f32, v4:f64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v5:any@late]
      #|  i1 IncomingReg(I32, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v6:any@late]
      #|  i2 IncomingReg(I64, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v7:any@late]
      #|  i3 IncomingReg(F32, p0:fpvec) uses=[v3:fixed(p0:fpvec)@early] defs=[v8:any@late]
      #|  i4 IncomingReg(F64, p1:fpvec) uses=[v4:fixed(p1:fpvec)@early] defs=[v9:any@late]
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
test "AArch64 lowering rejects non-native scalar memory endianness" {
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
  try lower(builder.finish(), test_lowering_context()) |> ignore catch {
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
test "AArch64 lowering selects non-trapping scalar floating-point operations" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_float(v0:ptr64, v1:f32, v2:f32, v3:f64, v4:f64) -> (f32, f64, i32, i32)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v5:any@late]
      #|  i1 IncomingReg(F32, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v6:any@late]
      #|  i2 IncomingReg(F32, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v7:any@late]
      #|  i3 IncomingReg(F64, p2:fpvec) uses=[v3:fixed(p2:fpvec)@early] defs=[v8:any@late]
      #|  i4 IncomingReg(F64, p3:fpvec) uses=[v4:fixed(p3:fpvec)@early] defs=[v9:any@late]
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
      #|  i16 OutgoingReg(I32, p1:int) uses=[v17:any@early]
      #|  i17 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering selects scalar rounding and NaN predicates" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_float_rounding(v0:ptr64, v1:f32, v2:f32, v3:f64, v4:f64) -> (f32, f64, i32, i32)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v5:any@late]
      #|  i1 IncomingReg(F32, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v6:any@late]
      #|  i2 IncomingReg(F32, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v7:any@late]
      #|  i3 IncomingReg(F64, p2:fpvec) uses=[v3:fixed(p2:fpvec)@early] defs=[v8:any@late]
      #|  i4 IncomingReg(F64, p3:fpvec) uses=[v4:fixed(p3:fpvec)@early] defs=[v9:any@late]
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
      #|  i18 OutgoingReg(I32, p1:int) uses=[v19:any@early]
      #|  i19 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering selects scalar min max and bit-exact copy-sign" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_float_minmax_copysign(v0:ptr64) -> (f32, f64, f32, f64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v1:any@late]
      #|  i1 LoadFloatConstant(F32, 0) defs=[v2:any@late]
      #|  i2 LoadFloatConstant(F32, 2147483648) defs=[v3:any@late]
      #|  i3 LoadFloatConstant(F64, 0) defs=[v4:any@late]
      #|  i4 LoadFloatConstant(F64, 9223372036854775808) defs=[v5:any@late]
      #|  i5 FloatBinary(F32, Min) uses=[v2:any@early, v3:any@early] defs=[v6:any@late]
      #|  i6 FloatBinary(F64, Max) uses=[v5:any@early, v4:any@early] defs=[v7:any@late]
      #|  i7 LoadFloatConstant(F32, 2143363909) defs=[v8:any@late]
      #|  i8 FloatBinary(F32, CopySign) uses=[v8:any@early, v3:any@early] defs=[v9:any@late]
      #|  i9 LoadFloatConstant(F64, 18444512289894210236) defs=[v10:any@late]
      #|  i10 FloatBinary(F64, CopySign) uses=[v10:any@early, v4:any@early] defs=[v11:any@late]
      #|  i11 OutgoingReg(F32, p0:fpvec) uses=[v6:any@early]
      #|  i12 OutgoingReg(F64, p1:fpvec) uses=[v7:any@early]
      #|  i13 OutgoingReg(F32, p2:fpvec) uses=[v9:any@early]
      #|  i14 OutgoingReg(F64, p3:fpvec) uses=[v11:any@early]
      #|  i15 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering maps all scalar fused operations explicitly" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_float_fused(v0:ptr64, v1:f32, v2:f32, v3:f32, v4:f64, v5:f64, v6:f64) -> (f32, f64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v7:any@late]
      #|  i1 IncomingReg(F32, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v8:any@late]
      #|  i2 IncomingReg(F32, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v9:any@late]
      #|  i3 IncomingReg(F32, p2:fpvec) uses=[v3:fixed(p2:fpvec)@early] defs=[v10:any@late]
      #|  i4 IncomingReg(F64, p3:fpvec) uses=[v4:fixed(p3:fpvec)@early] defs=[v11:any@late]
      #|  i5 IncomingReg(F64, p4:fpvec) uses=[v5:fixed(p4:fpvec)@early] defs=[v12:any@late]
      #|  i6 IncomingReg(F64, p5:fpvec) uses=[v6:fixed(p5:fpvec)@early] defs=[v13:any@late]
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
test "AArch64 lowering selects non-trapping scalar conversions" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode scalar_conversions(v0:ptr64, v1:i32, v2:i64, v3:f32, v4:f64) -> (i32, i64, f32, f64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v5:any@late]
      #|  i1 IncomingReg(I32, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v6:any@late]
      #|  i2 IncomingReg(I64, p2:int) uses=[v2:fixed(p2:int)@early] defs=[v7:any@late]
      #|  i3 IncomingReg(F32, p0:fpvec) uses=[v3:fixed(p0:fpvec)@early] defs=[v8:any@late]
      #|  i4 IncomingReg(F64, p1:fpvec) uses=[v4:fixed(p1:fpvec)@early] defs=[v9:any@late]
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
      #|  i22 OutgoingReg(I64, p1:int) uses=[v19:any@early]
      #|  i23 OutgoingReg(F32, p0:fpvec) uses=[v22:any@early]
      #|  i24 OutgoingReg(F64, p1:fpvec) uses=[v25:any@early]
      #|  i25 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering legalizes trapping and saturating float-to-int" {
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
    lower(builder.finish(), test_lowering_context()).summary(),
    content=(
      #|vcode float_to_int(v0:ptr64, v1:f32, v2:f64) -> (i32, i64)
      #|block0:
      #|  i0 IncomingReg(Ptr64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v3:any@late]
      #|  i1 IncomingReg(F32, p0:fpvec) uses=[v1:fixed(p0:fpvec)@early] defs=[v4:any@late]
      #|  i2 IncomingReg(F64, p1:fpvec) uses=[v2:fixed(p1:fpvec)@early] defs=[v5:any@late]
      #|  i3 TrapIfFloat(F32, Unordered) uses=[v4:any@early] trap=InvalidConversionToInteger
      #|  i4 LoadFloatConstant(F32, 3472883712) defs=[v6:any@late]
      #|  i5 TrapIfFloat(F32, LessThan) uses=[v4:any@early, v6:any@early] trap=InvalidConversionToInteger
      #|  i6 LoadFloatConstant(F32, 1325400064) defs=[v7:any@late]
      #|  i7 TrapIfFloat(F32, GreaterOrEqual) uses=[v4:any@early, v7:any@early] trap=InvalidConversionToInteger
      #|  i8 Convert(FloatToInt(F32, I32, Signed)) uses=[v4:any@early] defs=[v8:any@late]
      #|  i9 Convert(FloatToInt(F64, I64, Unsigned)) uses=[v5:any@early] defs=[v9:any@late]
      #|  i10 OutgoingReg(I32, p0:int) uses=[v8:any@early]
      #|  i11 OutgoingReg(I64, p1:int) uses=[v9:any@early]
      #|  i12 Return
      #|
    ),
  )
}
