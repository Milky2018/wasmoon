///|
fn single(values : Array[@machv.Value]) -> @machv.Value {
  if values.length() != 1 {
    abort("expected one result")
  }
  values[0]
}

///|
test "address-visible stack objects retain target-neutral layout requirements" {
  let builder = @machv.FunctionBuilder::new("stack_buffer", Internal, [I64], [])
  let object = builder.create_stack_object(24, 16)
  let address = single(builder.emit(StackAddress(object), [], [Ptr64]))
  builder.emit(
    Store(@machv.StoreSpec::new(W64, I64, 0UL, Little, None)),
    [address, builder.parameters()[0]],
    [],
  )
  |> ignore
  builder.return_([])
  inspect(
    builder.finish(),
    content=(
      #|machv stack_buffer [internal](v0:i64) -> () {
      #|stack0: size=24, alignment=16
      #|block0:
      #|  v1:ptr64 = stack.address stack0
      #|  store {
      #|  width: W64,
      #|  value_type: I64,
      #|  offset: 0,
      #|  endianness: Little,
      #|  trap: None,
      #|} v1, v0 [memory=write]
      #|  return
      #|}
    ),
  )
}

///|
test "stack objects cannot cross function ownership" {
  let producer = @machv.FunctionBuilder::new("producer", Internal, [], [])
  let foreign = producer.create_stack_object(8, 8)
  producer.return_([])
  producer.finish() |> ignore
  let consumer = @machv.FunctionBuilder::new("consumer", Internal, [], [])
  consumer.emit(StackAddress(foreign), [], [Ptr64]) |> ignore
  consumer.return_([])
  try consumer.finish() catch {
    error => inspect(error, content="ForeignStackObject(object_id=0)")
  } noraise {
    _ => fail("expected a foreign stack object to be rejected")
  }
}

///|
test "stack object alignment must be a positive power of two" {
  let builder = @machv.FunctionBuilder::new("bad_stack", Internal, [], [])
  builder.create_stack_object(8, 3) |> ignore
  builder.return_([])
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidStackObject(
          #|  object_id=0,
          #|  message="stack object alignment must be a positive power of two",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected invalid stack object alignment to be rejected")
  }
}

///|
test "i64 switch carries typed edge arguments" {
  let builder = @machv.FunctionBuilder::new("switch64", Internal, [I64], [I64])
  let case_block = builder.create_block([I64])
  let default_block = builder.create_block([I64])
  let exit_block = builder.create_block([I64])
  let index = builder.parameters()[0]
  builder.switch(index, [(0x100000000UL, case_block, [index])], default_block, [
    index,
  ])
  builder.switch_to_block(case_block)
  builder.jump(exit_block, [builder.block_parameters(case_block)[0]])
  builder.switch_to_block(default_block)
  builder.jump(exit_block, [builder.block_parameters(default_block)[0]])
  builder.switch_to_block(exit_block)
  builder.return_([builder.block_parameters(exit_block)[0]])
  inspect(
    builder.finish(),
    content=(
      #|machv switch64 [internal](v0:i64) -> (i64) {
      #|block0:
      #|  switch v0 [4294967296: block1(v0), default: block2(v0)]
      #|block1(v1:i64):
      #|  jump block3(v1)
      #|block2(v2:i64):
      #|  jump block3(v2)
      #|block3(v3:i64):
      #|  return v3
      #|}
    ),
  )
}

///|
test "switch rejects duplicate case values" {
  let builder = @machv.FunctionBuilder::new(
    "duplicate_switch",
    Internal,
    [I32],
    [],
  )
  let target = builder.create_block([])
  let index = builder.parameters()[0]
  builder.switch(index, [(1UL, target, []), (1UL, target, [])], target, [])
  builder.switch_to_block(target)
  builder.return_([])
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidTerminator(
          #|  block_id=0,
          #|  message="switch case values must be unique",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected duplicate switch cases to be rejected")
  }
}

///|
test "edges reject missing block arguments" {
  let builder = @machv.FunctionBuilder::new(
    "missing_edge_argument",
    Internal,
    [],
    [],
  )
  let target = builder.create_block([I32])
  builder.jump(target, [])
  builder.switch_to_block(target)
  builder.return_([])
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidEdge(
          #|  block_id=0,
          #|  target_id=1,
          #|  message="jump expects 1 arguments, got 0",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected a missing edge argument")
  }
}

///|
test "i32 switch rejects case bits wider than its index" {
  let builder = @machv.FunctionBuilder::new(
    "wide_switch_case",
    Internal,
    [I32],
    [],
  )
  let target = builder.create_block([])
  builder.switch(
    builder.parameters()[0],
    [(0x100000000UL, target, [])],
    target,
    [],
  )
  builder.switch_to_block(target)
  builder.return_([])
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidTerminator(
          #|  block_id=0,
          #|  message="i32 switch case value exceeds 32 bits",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected an over-wide i32 switch case to be rejected")
  }
}

///|
test "indirect calls use an explicit ptr64 callee" {
  let builder = @machv.FunctionBuilder::new(
    "indirect",
    Internal,
    [Ptr64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let call = SemanticCall::new(
    Indirect,
    Signature::new([I64], [I64]),
    Internal,
    CallBehavior::conservative(),
  )
  let result = single(
    builder.emit(Call(call), [parameters[0], parameters[1]], [I64]),
  )
  builder.return_([result])
  inspect(
    builder.finish(),
    content=(
      #|machv indirect [internal](v0:ptr64, v1:i64) -> (i64) {
      #|block0:
      #|  v2:i64 = call indirect (i64) -> (i64) [internal] v0, v1 [memory=read-write, trap, unwind, gc-safepoint, cancel-safepoint]
      #|  return v2
      #|}
    ),
  )
}

///|
test "vector lane operations remain parameterized" {
  let builder = @machv.FunctionBuilder::new("vector_lane", Internal, [V128], [
    I32,
  ])
  let extracted = single(
    builder.emit(
      Vector(ExtractLane(I16x8, 3, Some(Unsigned))),
      [builder.parameters()[0]],
      [I32],
    ),
  )
  builder.return_([extracted])
  inspect(
    builder.finish(),
    content=(
      #|machv vector_lane [internal](v0:v128) -> (i32) {
      #|block0:
      #|  v1:i32 = vector.ExtractLane(I16x8, 3, Some(Unsigned)) v0
      #|  return v1
      #|}
    ),
  )
}

///|
test "vector shuffle validates all semantic lane indices" {
  let builder = @machv.FunctionBuilder::new(
    "bad_shuffle",
    Internal,
    [V128, V128],
    [],
  )
  let mask = FixedArray::makei(16, index => if index == 15 { 32 } else { index })
  builder.emit(Vector(Shuffle(mask)), builder.parameters(), [V128]) |> ignore
  builder.return_([])
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidOperation(
          #|  block_id=0,
          #|  message="vector.shuffle lane index is out of range",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected an invalid shuffle lane to be rejected")
  }
}

///|
test "narrow loads require an explicit extension" {
  let builder = @machv.FunctionBuilder::new("bad_load", Internal, [Ptr64], [])
  builder.emit(
    Load(LoadSpec::new(W8, None, I32, 0UL, Little, Some(MemoryOutOfBounds))),
    builder.parameters(),
    [I32],
  )
  |> ignore
  builder.return_([])
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidOperation(
          #|  block_id=0,
          #|  message="narrow integer load requires signedness",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected a narrow load without extension to be rejected")
  }
}

///|
test "atomic width is part of the semantic contract" {
  let builder = @machv.FunctionBuilder::new(
    "bad_atomic_width",
    Internal,
    [Ptr64, I32],
    [],
  )
  builder.emit(
    AtomicStore(AtomicSpec::new(W64, I32, 0UL, Little, Some(MemoryOutOfBounds))),
    builder.parameters(),
    [],
  )
  |> ignore
  builder.return_([])
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidOperation(
          #|  block_id=0,
          #|  message="atomic width exceeds its integer value type",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected an illegal atomic width to be rejected")
  }
}

///|
test "symbols must have stable non-empty identities" {
  let builder = @machv.FunctionBuilder::new("empty_symbol", Internal, [], [])
  let call = SemanticCall::new(
    External(ExternalSymbol::new("")),
    Signature::new([], []),
    Platform,
    CallBehavior::conservative(),
  )
  builder.emit(Call(call), [], []) |> ignore
  builder.return_([])
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidOperation(
          #|  block_id=0,
          #|  message="call external symbol must not be empty",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected an empty external symbol to be rejected")
  }
}

///|
test "source locations reject invalid coordinates" {
  let builder = @machv.FunctionBuilder::new("bad_source", Internal, [], [])
  builder.emit_with_metadata(
    Safepoint(Cancellation),
    [],
    [],
    InstructionMetadata::new(Some(SourceLocation::new("", -1, -1)), []),
  )
  |> ignore
  builder.return_([])
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidMetadata(
          #|  block_id=0,
          #|  message="source location requires a non-empty file and non-negative coordinates",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected invalid source metadata to be rejected")
  }
}

///|
test "entry block cannot acquire a predecessor" {
  let builder = @machv.FunctionBuilder::new("entry_predecessor", Internal, [], [])
  let loop_block = builder.create_block([])
  builder.jump(loop_block, [])
  builder.switch_to_block(loop_block)
  builder.jump(builder.entry_block(), [])
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|EntryHasPredecessor(block_id=0)
        ),
      )
  } noraise {
    _ => fail("expected an entry-predecessor error")
  }
}

///|
test "return values must match the function signature" {
  let builder = @machv.FunctionBuilder::new("bad_return", Internal, [I32], [I64])
  builder.return_([builder.parameters()[0]])
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidTerminator(
          #|  block_id=0,
          #|  message="return value 0 has type i32, expected i64",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected a return signature error")
  }
}

///|
test "instruction storage owns mutable call signatures" {
  let builder = @machv.FunctionBuilder::new(
    "owned_call_signature",
    Internal,
    [I32],
    [I32],
  )
  let call = SemanticCall::new(
    External(ExternalSymbol::new("identity")),
    Signature::new([I32], [I32]),
    Platform,
    CallBehavior::conservative(),
  )
  let result = single(builder.emit(Call(call), builder.parameters(), [I32]))
  call.signature.params[0] = I64
  call.signature.results[0] = I64
  builder.return_([result])
  inspect(
    builder.finish(),
    content=(
      #|machv owned_call_signature [internal](v0:i32) -> (i32) {
      #|block0:
      #|  v1:i32 = call external @identity (i32) -> (i32) [platform] v0 [memory=read-write, trap, unwind, gc-safepoint, cancel-safepoint]
      #|  return v1
      #|}
    ),
  )
}

///|
test "instruction storage owns mutable shuffle masks" {
  let builder = @machv.FunctionBuilder::new(
    "owned_shuffle",
    Internal,
    [V128, V128],
    [V128],
  )
  let mask = FixedArray::makei(16, index => index)
  let result = single(
    builder.emit(Vector(Shuffle(mask)), builder.parameters(), [V128]),
  )
  mask[0] = 32
  builder.return_([result])
  inspect(
    builder.finish(),
    content=(
      #|machv owned_shuffle [internal](v0:v128, v1:v128) -> (v128) {
      #|block0:
      #|  v2:v128 = vector.Shuffle(<FixedArray: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]>) v0, v1
      #|  return v2
      #|}
    ),
  )
}

///|
test "public queries return snapshots instead of canonical arrays" {
  let builder = @machv.FunctionBuilder::new("query_snapshot", Internal, [I32], [
    I32,
  ])
  let exit = builder.create_block([I32])
  builder.jump(exit, builder.parameters())
  builder.switch_to_block(exit)
  builder.return_([builder.block_parameters(exit)[0]])
  let function = builder.finish()
  let entry = function.blocks()[0]
  if function.block_terminator(entry) is Some(record) {
    match record.kind {
      Jump(edge) => edge.arguments.clear()
      _ => fail("expected a jump")
    }
  }
  let parameters = function.parameters()
  parameters.clear()
  function.verify()
  inspect(
    function,
    content=(
      #|machv query_snapshot [internal](v0:i32) -> (i32) {
      #|block0:
      #|  jump block1(v0)
      #|block1(v1:i32):
      #|  return v1
      #|}
    ),
  )
}

///|
test "mandatory cleanup collapses a long alias chain" {
  let builder = @machv.FunctionBuilder::new(
    "long_alias_chain",
    Internal,
    [I32],
    [I32],
  )
  let mut value = builder.parameters()[0]
  for _ in 0..<1000 {
    value = single(builder.emit(Copy, [value], [I32]))
  }
  builder.return_([value])
  inspect(
    builder.finish(),
    content=(
      #|machv long_alias_chain [internal](v0:i32) -> (i32) {
      #|block0:
      #|  return v0
      #|}
    ),
  )
}

///|
test "semantic superinstructions and vector memory remain target neutral" {
  let builder = @machv.FunctionBuilder::new(
    "semantic_superinstructions",
    Internal,
    [Ptr64, GcRef64, I64, F64, F64, F64, V128],
    [I32, I64, I32, F64, V128, V128],
  )
  let parameters = builder.parameters()
  let gc_address = single(builder.emit(GcRefAddress, [parameters[1]], [Ptr64]))
  let address = single(
    builder.emit(PointerOffset, [gc_address, parameters[2]], [Ptr64]),
  )
  let null_reference = single(builder.emit(NullGcRef, [], [GcRef64]))
  let reference_test = single(
    builder.emit(ReferenceCompare(Equal), [parameters[1], null_reference], [I32]),
  )
  let overflow_results = builder.emit(
    IntWithOverflow(Add(Unsigned)),
    [parameters[2], parameters[2]],
    [I64, I32],
  )
  let fused = single(
    builder.emit(
      FloatTernary(FusedMultiplyAdd),
      [parameters[3], parameters[4], parameters[5]],
      [F64],
    ),
  )
  let loaded = single(
    builder.emit(
      VectorLoad(
        VectorLoadSpec::new(Splat(I32x4), 8UL, Little, Some(MemoryOutOfBounds)),
      ),
      [address],
      [V128],
    ),
  )
  let fused_vector = single(
    builder.emit(
      Vector(FloatTernary(F32x4, FusedMultiplyAdd)),
      [parameters[6], loaded, loaded],
      [V128],
    ),
  )
  builder.emit(
    VectorStoreLane(
      VectorStoreLaneSpec::new(I32x4, 2, 12UL, Little, Some(MemoryOutOfBounds)),
    ),
    [address, fused_vector],
    [],
  )
  |> ignore
  builder.return_([
    reference_test,
    overflow_results[0],
    overflow_results[1],
    fused,
    loaded,
    fused_vector,
  ])
  inspect(
    builder.finish(),
    content=(
      #|machv semantic_superinstructions [internal](v0:ptr64, v1:gcref64, v2:i64, v3:f64, v4:f64, v5:f64, v6:v128) -> (i32, i64, i32, f64, v128, v128) {
      #|block0:
      #|  v7:ptr64 = gcref.address v1
      #|  v8:ptr64 = pointer.offset v7, v2
      #|  v9:gcref64 = gcref.null
      #|  v10:i32 = reference.compare.Equal v1, v9
      #|  v11:i64, v12:i32 = int.with_overflow.Add(Unsigned) v2, v2
      #|  v13:f64 = float.ternary.FusedMultiplyAdd v3, v4, v5
      #|  v14:v128 = vector.load {
      #|  kind: Splat(I32x4),
      #|  offset: 8,
      #|  endianness: Little,
      #|  trap: Some(MemoryOutOfBounds),
      #|} v8 [memory=read, trap]
      #|  v15:v128 = vector.FloatTernary(F32x4, FusedMultiplyAdd) v6, v14, v14
      #|  vector.store_lane {
      #|  lane: I32x4,
      #|  lane_index: 2,
      #|  offset: 12,
      #|  endianness: Little,
      #|  trap: Some(MemoryOutOfBounds),
      #|} v8, v15 [memory=write, trap]
      #|  return v10, v11, v12, v13, v14, v15
      #|}
    ),
  )
}

///|
test "sign extension rejects an equal-width source" {
  let builder = @machv.FunctionBuilder::new(
    "bad_sign_extend",
    Internal,
    [I64],
    [],
  )
  builder.emit(Convert(SignExtend(I64, W64)), builder.parameters(), [I64])
  |> ignore
  builder.return_([])
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidOperation(
          #|  block_id=0,
          #|  message="sign extension source width must be narrower than its integer value type",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected an invalid sign-extension width")
  }
}

///|
test "vector lane memory validates lane indices" {
  let builder = @machv.FunctionBuilder::new(
    "bad_vector_lane_load",
    Internal,
    [Ptr64, V128],
    [],
  )
  builder.emit(
    VectorLoad(
      VectorLoadSpec::new(Lane(I64x2, 2), 0UL, Little, Some(MemoryOutOfBounds)),
    ),
    builder.parameters(),
    [V128],
  )
  |> ignore
  builder.return_([])
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidOperation(
          #|  block_id=0,
          #|  message="vector load-lane index is out of range",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected an invalid vector load-lane index")
  }
}

///|
test "GC safepoints reject omitted live roots" {
  let builder = @machv.FunctionBuilder::new(
    "missing_gc_root",
    Internal,
    [GcRef64],
    [GcRef64],
  )
  let call = SemanticCall::new(
    External(ExternalSymbol::new("collect")),
    Signature::new([], []),
    Platform,
    CallBehavior::new(ReadWrite, false, false, true, false),
  )
  builder.emit(Call(call), [], []) |> ignore
  builder.return_(builder.parameters())
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|MissingGcRoot(block_id=0, instruction_id=0, value_id=0)
        ),
      )
  } noraise {
    _ => fail("expected a missing GC root")
  }
}

///|
test "GC safepoints reject duplicate root entries" {
  let builder = @machv.FunctionBuilder::new(
    "duplicate_gc_root",
    Internal,
    [GcRef64],
    [],
  )
  let root = builder.parameters()[0]
  builder.emit_with_metadata(
    Safepoint(Gc),
    [],
    [],
    InstructionMetadata::new(None, [root, root]),
  )
  |> ignore
  builder.return_([])
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidSafepoint(
          #|  block_id=0,
          #|  message="live GC roots must not contain duplicates",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected duplicate GC roots to be rejected")
  }
}

///|
test "terminator source metadata is preserved" {
  let builder = @machv.FunctionBuilder::new("trap_source", Internal, [], [])
  builder.trap(User(7))
  builder.set_terminator_source(SourceLocation::new("trap.wat", 3, 9))
  inspect(
    builder.finish(),
    content=(
      #|machv trap_source [internal]() -> () {
      #|block0:
      #|  trap User(7) source=trap.wat:3:9
      #|}
    ),
  )
}
