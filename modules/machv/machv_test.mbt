///|
fn only_result(values : Array[@machv.Value]) -> @machv.Value {
  if values.length() != 1 {
    abort("expected exactly one result")
  }
  values[0]
}

///|
fn semantic_summary(
  operation : @machv.Operation,
) -> (@machv.Operation, @machv.OperationSemantics) {
  (operation, operation.semantics())
}

///|
test "complete semantic function snapshot" {
  let builder = @machv.FunctionBuilder::new(
    "semantic_pipeline",
    Internal,
    [Ptr64, I32, GcRef64],
    [I32],
  )
  let parameters = builder.parameters()
  let pointer = parameters[0]
  let input = parameters[1]
  let root = parameters[2]
  let true_block = builder.create_block([I32])
  let false_block = builder.create_block([I32])
  let merge_block = builder.create_block([I32])
  let one = only_result(builder.emit(I32Const(1U), [], [I32]))
  let sum = only_result(builder.emit(IntBinary(Add), [input, one], [I32]))
  let condition = only_result(
    builder.emit(IntCompare(SignedGreaterThan), [sum, one], [I32]),
  )
  builder.emit(
    Store(StoreSpec::new(W32, I32, 4UL, Little, Some(MemoryOutOfBounds))),
    [pointer, sum],
    [],
  )
  |> ignore
  let call = SemanticCall::new(
    External(ExternalSymbol::new("observe")),
    Signature::new([I32], [I32]),
    Platform,
    CallBehavior::new(Read, true, false, true, true),
  )
  let observed = only_result(
    builder.emit_with_metadata(
      Call(call),
      [sum],
      [I32],
      InstructionMetadata::new(
        Some(SourceLocation::new("semantic.mbt", 12, 4)),
        [root],
      ),
    ),
  )
  builder.branch(condition, true_block, [observed], false_block, [sum])
  builder.switch_to_block(true_block)
  let true_value = builder.block_parameters(true_block)[0]
  let loaded = only_result(
    builder.emit(
      Load(LoadSpec::new(W32, None, I32, 4UL, Little, Some(MemoryOutOfBounds))),
      [pointer],
      [I32],
    ),
  )
  let combined = only_result(
    builder.emit(IntBinary(Add), [true_value, loaded], [I32]),
  )
  builder.jump(merge_block, [combined])
  builder.switch_to_block(false_block)
  let false_value = builder.block_parameters(false_block)[0]
  builder.emit(Safepoint(Cancellation), [], []) |> ignore
  builder.jump(merge_block, [false_value])
  builder.switch_to_block(merge_block)
  builder.return_([builder.block_parameters(merge_block)[0]])
  inspect(
    builder.finish(),
    content=(
      #|machv semantic_pipeline [internal](v0:ptr64, v1:i32, v2:gcref64) -> (i32) {
      #|block0:
      #|  v6:i32 = i32.const 1
      #|  v7:i32 = int.binary.Add v1, v6
      #|  v8:i32 = int.compare.SignedGreaterThan v7, v6
      #|  store {
      #|  width: W32,
      #|  value_type: I32,
      #|  offset: 4,
      #|  endianness: Little,
      #|  trap: Some(MemoryOutOfBounds),
      #|} v0, v7 [memory=write, trap]
      #|  v9:i32 = call external @observe (i32) -> (i32) [platform] v7 [memory=read, trap, gc-safepoint, cancel-safepoint] source=semantic.mbt:12:4 roots=[v2]
      #|  branch v8, block1(v9), block2(v7)
      #|block1(v3:i32):
      #|  v10:i32 = load {
      #|  width: W32,
      #|  extension: None,
      #|  result_type: I32,
      #|  offset: 4,
      #|  endianness: Little,
      #|  trap: Some(MemoryOutOfBounds),
      #|} v0 [memory=read, trap]
      #|  v11:i32 = int.binary.Add v3, v10
      #|  jump block3(v11)
      #|block2(v4:i32):
      #|  safepoint.Cancellation [cancel-safepoint]
      #|  jump block3(v4)
      #|block3(v5:i32):
      #|  return v5
      #|}
    ),
  )
}

///|
test "operation summaries snapshot all observable families" {
  let pointer_load : @machv.Operation = Load(
    LoadSpec::new(W64, None, Ptr64, 0UL, Little, Some(MemoryOutOfBounds)),
  )
  let call : @machv.Operation = Call(
    SemanticCall::new(
      Internal(CodeSymbol::new("callee")),
      Signature::new([], []),
      Internal,
      CallBehavior::conservative(),
    ),
  )
  let summaries : Array[(@machv.Operation, @machv.OperationSemantics)] = [
    semantic_summary(I32Const(0U)),
    semantic_summary(IntBinary(SignedDiv)),
    semantic_summary(Convert(FloatToInt(F64, I64, Signed, Trapping))),
    semantic_summary(Convert(FloatToInt(F64, I64, Signed, Saturating))),
    semantic_summary(pointer_load),
    semantic_summary(
      Store(StoreSpec::new(W32, I32, 0UL, Little, Some(MemoryOutOfBounds))),
    ),
    semantic_summary(
      AtomicRmw(
        AtomicSpec::new(W32, I32, 0UL, Little, Some(MemoryOutOfBounds)),
        Exchange,
      ),
    ),
    semantic_summary(call),
    semantic_summary(Safepoint(GcAndCancellation)),
  ]
  debug_inspect(
    summaries,
    content=(
      #|[
      #|  (
      #|    I32Const(0),
      #|    {
      #|      memory: None,
      #|      may_trap: false,
      #|      may_unwind: false,
      #|      gc_safepoint: false,
      #|      cancellation_safepoint: false,
      #|    },
      #|  ),
      #|  (
      #|    IntBinary(SignedDiv),
      #|    {
      #|      memory: None,
      #|      may_trap: true,
      #|      may_unwind: false,
      #|      gc_safepoint: false,
      #|      cancellation_safepoint: false,
      #|    },
      #|  ),
      #|  (
      #|    Convert(FloatToInt(F64, I64, Signed, Trapping)),
      #|    {
      #|      memory: None,
      #|      may_trap: true,
      #|      may_unwind: false,
      #|      gc_safepoint: false,
      #|      cancellation_safepoint: false,
      #|    },
      #|  ),
      #|  (
      #|    Convert(FloatToInt(F64, I64, Signed, Saturating)),
      #|    {
      #|      memory: None,
      #|      may_trap: false,
      #|      may_unwind: false,
      #|      gc_safepoint: false,
      #|      cancellation_safepoint: false,
      #|    },
      #|  ),
      #|  (
      #|    Load(
      #|      {
      #|        width: W64,
      #|        extension: None,
      #|        result_type: Ptr64,
      #|        offset: 0,
      #|        endianness: Little,
      #|        trap: Some(MemoryOutOfBounds),
      #|      },
      #|    ),
      #|    {
      #|      memory: Read,
      #|      may_trap: true,
      #|      may_unwind: false,
      #|      gc_safepoint: false,
      #|      cancellation_safepoint: false,
      #|    },
      #|  ),
      #|  (
      #|    Store(
      #|      {
      #|        width: W32,
      #|        value_type: I32,
      #|        offset: 0,
      #|        endianness: Little,
      #|        trap: Some(MemoryOutOfBounds),
      #|      },
      #|    ),
      #|    {
      #|      memory: Write,
      #|      may_trap: true,
      #|      may_unwind: false,
      #|      gc_safepoint: false,
      #|      cancellation_safepoint: false,
      #|    },
      #|  ),
      #|  (
      #|    AtomicRmw(
      #|      {
      #|        width: W32,
      #|        value_type: I32,
      #|        offset: 0,
      #|        endianness: Little,
      #|        trap: Some(MemoryOutOfBounds),
      #|      },
      #|      Exchange,
      #|    ),
      #|    {
      #|      memory: ReadWrite,
      #|      may_trap: true,
      #|      may_unwind: false,
      #|      gc_safepoint: false,
      #|      cancellation_safepoint: false,
      #|    },
      #|  ),
      #|  (
      #|    Call(
      #|      {
      #|        callee: Internal({ name: "callee" }),
      #|        signature: { params: [], results: [] },
      #|        protocol: Internal,
      #|        behavior: {
      #|          memory: ReadWrite,
      #|          may_trap: true,
      #|          may_unwind: true,
      #|          gc_safepoint: true,
      #|          cancellation_safepoint: true,
      #|        },
      #|      },
      #|    ),
      #|    {
      #|      memory: ReadWrite,
      #|      may_trap: true,
      #|      may_unwind: true,
      #|      gc_safepoint: true,
      #|      cancellation_safepoint: true,
      #|    },
      #|  ),
      #|  (
      #|    Safepoint(GcAndCancellation),
      #|    {
      #|      memory: None,
      #|      may_trap: false,
      #|      may_unwind: false,
      #|      gc_safepoint: true,
      #|      cancellation_safepoint: true,
      #|    },
      #|  ),
      #|]
    ),
  )
}

///|
test "builder rejects a foreign value before mutation" {
  let first = @machv.FunctionBuilder::new("first", Internal, [I32], [])
  let foreign = first.parameters()[0]
  let second = @machv.FunctionBuilder::new("second", Internal, [I32], [])
  second.emit(IntBinary(Add), [second.parameters()[0], foreign], [I32])
  |> ignore
  second.return_([])
  try second.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|ForeignValue(value_id=0)
        ),
      )
  } noraise {
    _ => fail("expected a foreign-value error")
  }
}

///|
test "builder rejects a foreign block before mutation" {
  let first = @machv.FunctionBuilder::new("first", Internal, [], [])
  let second = @machv.FunctionBuilder::new("second", Internal, [], [])
  first.switch_to_block(second.entry_block())
  first.return_([])
  try first.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|ForeignBlock(block_id=0)
        ),
      )
  } noraise {
    _ => fail("expected a foreign-block error")
  }
}

///|
test "verifier rejects a cross-block non-dominating value" {
  let builder = @machv.FunctionBuilder::new("non_dominating", Internal, [I32], [])
  let left = builder.create_block([])
  let right = builder.create_block([])
  let merge = builder.create_block([])
  builder.branch(builder.parameters()[0], left, [], right, [])
  builder.switch_to_block(left)
  let left_value = only_result(builder.emit(I32Const(1U), [], [I32]))
  builder.jump(merge, [])
  builder.switch_to_block(right)
  builder.jump(merge, [])
  builder.switch_to_block(merge)
  builder.emit(Copy, [left_value], [I32]) |> ignore
  builder.return_([])
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|NonDominatingUse(value_id=1, defining_block_id=1, use_block_id=3)
        ),
      )
  } noraise {
    _ => fail("expected a non-dominating-use error")
  }
}

///|
test "builder rejects malformed edge arguments" {
  let builder = @machv.FunctionBuilder::new("bad_edge", Internal, [], [])
  let target = builder.create_block([I64])
  let value = only_result(builder.emit(I32Const(0U), [], [I32]))
  builder.jump(target, [value])
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
          #|  message="jump argument 0 has type i32, expected i64",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected an invalid-edge error")
  }
}

///|
test "builder rejects malformed call signatures" {
  let builder = @machv.FunctionBuilder::new("bad_call", Internal, [I32], [])
  let call = SemanticCall::new(
    External(ExternalSymbol::new("bad")),
    Signature::new([I64], []),
    Platform,
    CallBehavior::conservative(),
  )
  builder.emit(Call(call), [builder.parameters()[0]], []) |> ignore
  builder.return_([])
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidOperation(
          #|  block_id=0,
          #|  message="call expects operands [I64], got [I32]",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected an invalid-operation error")
  }
}

///|
test "builder rejects non-reference GC roots" {
  let builder = @machv.FunctionBuilder::new("bad_root", Internal, [I64], [])
  builder.emit_with_metadata(
    Safepoint(Gc),
    [],
    [],
    InstructionMetadata::new(None, [builder.parameters()[0]]),
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
          #|  message="live GC roots must have type gcref64",
          #|)
        ),
      )
  } noraise {
    _ => fail("expected an invalid-safepoint error")
  }
}

///|
test "mandatory cleanup removes aliases but preserves observable operations" {
  let builder = @machv.FunctionBuilder::new(
    "mandatory_cleanup",
    Internal,
    [Ptr64, I32],
    [I32],
  )
  let parameters = builder.parameters()
  let zero = only_result(builder.emit(I32Const(0U), [], [I32]))
  let copied = only_result(builder.emit(Copy, [parameters[1]], [I32]))
  let shifted = only_result(
    builder.emit(IntBinary(ShiftLeft), [copied, zero], [I32]),
  )
  builder.emit(
    Load(LoadSpec::new(W32, None, I32, 0UL, Little, Some(MemoryOutOfBounds))),
    [parameters[0]],
    [I32],
  )
  |> ignore
  let call = SemanticCall::new(
    External(ExternalSymbol::new("effect")),
    Signature::new([], []),
    Platform,
    CallBehavior::conservative(),
  )
  builder.emit(Call(call), [], []) |> ignore
  builder.return_([shifted])
  inspect(
    builder.finish(),
    content=(
      #|machv mandatory_cleanup [internal](v0:ptr64, v1:i32) -> (i32) {
      #|block0:
      #|  v5:i32 = load {
      #|  width: W32,
      #|  extension: None,
      #|  result_type: I32,
      #|  offset: 0,
      #|  endianness: Little,
      #|  trap: Some(MemoryOutOfBounds),
      #|} v0 [memory=read, trap]
      #|  call external @effect () -> () [platform] [memory=read-write, trap, unwind, gc-safepoint, cancel-safepoint]
      #|  return v1
      #|}
    ),
  )
}

///|
test "verifier rejects unreachable blocks" {
  let builder = @machv.FunctionBuilder::new("unreachable", Internal, [], [])
  let dead = builder.create_block([])
  builder.return_([])
  builder.switch_to_block(dead)
  builder.trap(Unreachable)
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|UnreachableBlock(block_id=1)
        ),
      )
  } noraise {
    _ => fail("expected an unreachable-block error")
  }
}

///|
test "verifier rejects a missing terminator" {
  let builder = @machv.FunctionBuilder::new(
    "missing_terminator",
    Internal,
    [],
    [],
  )
  try builder.finish() catch {
    error =>
      inspect(
        error,
        content=(
          #|MissingTerminator(block_id=0)
        ),
      )
  } noraise {
    _ => fail("expected a missing-terminator error")
  }
}

///|
test "tail call snapshots logical protocol and GC roots" {
  let builder = @machv.FunctionBuilder::new(
    "tail",
    Internal,
    [Ptr64, GcRef64, I32],
    [I32],
  )
  let parameters = builder.parameters()
  let call = SemanticCall::new(
    Internal(CodeSymbol::new("next")),
    Signature::new([Ptr64, GcRef64, I32], [I32]),
    Internal,
    CallBehavior::new(ReadWrite, true, false, true, true),
  )
  builder.tail_call_with_metadata(
    call,
    parameters,
    TerminatorMetadata::new(None, [parameters[1]]),
  )
  inspect(
    builder.finish(),
    content=(
      #|machv tail [internal](v0:ptr64, v1:gcref64, v2:i32) -> (i32) {
      #|block0:
      #|  tail_call internal @next (ptr64, gcref64, i32) -> (i32) [internal] (v0, v1, v2) [memory=read-write, trap, gc-safepoint, cancel-safepoint] roots=[v1]
      #|}
    ),
  )
}
