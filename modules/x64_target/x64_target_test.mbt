///|
test "x64 trusted direct selection skips redundant VCode validation" {
  let abi = @x64_target.InternalAbi::new(
    7,
    12,
    [6, 2, 1, 8, 9],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 2, 1, 8, 9, 6, 7, 10],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let saw_validation = Ref(false)
  let session = @x64_target.DirectLoweringSession::new(
    "trusted",
    Internal,
    [Ptr64],
    [],
    @x64_target.LoweringContext::new(abi),
    on_event=fn(event) {
      if event is TargetValidationStarted {
        saw_validation.val = true
      }
    },
  )
  let sink = session.sink()
  inspect(sink.folds_unsigned_index_into_memory(), content="false")
  let builder = @lowering.DirectBuilder::new([Ptr64], sink)
  builder.return_([])
  builder.finish()
  session.finish_selected(verify_selected=false) |> ignore
  inspect(saw_validation.val, content="false")
}

///|
test "x64 direct selection erases raw-word pointer bitcasts" {
  let abi = @x64_target.InternalAbi::new(
    7,
    12,
    [6, 2, 1, 8, 9],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 2, 1, 8, 9, 6, 7, 10],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let session = @x64_target.DirectLoweringSession::new(
    "raw_word_alias",
    Internal,
    [Ptr64, I64],
    [I64],
    @x64_target.LoweringContext::new(abi),
  )
  let builder = @lowering.DirectBuilder::new([Ptr64, I64], session.sink())
  let pointer = builder.emit_with_metadata(
      Convert(Bitcast(I64, Ptr64)),
      [builder.parameters()[1]],
      [Ptr64],
      @lowering.InstructionMetadata::empty(),
    )[0]
  let offset = builder.emit_with_metadata(
      I64Const(8UL),
      [],
      [I64],
      @lowering.InstructionMetadata::empty(),
    )[0]
  let adjusted = builder.emit_with_metadata(
      PointerOffset,
      [pointer, offset],
      [Ptr64],
      @lowering.InstructionMetadata::empty(),
    )[0]
  let bits = builder.emit_with_metadata(
      Convert(Bitcast(Ptr64, I64)),
      [adjusted],
      [I64],
      @lowering.InstructionMetadata::empty(),
    )[0]
  builder.return_([bits])
  builder.finish()
  session.finish_selected() |> ignore
}

///|
test "x64 explicit immediate comparison retains semantic fallback" {
  let abi = @x64_target.InternalAbi::new(
    7,
    12,
    [6, 2, 1, 8, 9],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 2, 1, 8, 9, 6, 7, 10],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )

  let session = @x64_target.DirectLoweringSession::new(
    "compare_fallback",
    Internal,
    [Ptr64, I64],
    [I32],
    @x64_target.LoweringContext::new(abi),
  )
  let sink = session.sink()
  inspect(sink.supports_int_compare_immediate(I64, 42UL), content="false")
  let builder = @lowering.DirectBuilder::new([Ptr64, I64], sink)
  let result = builder.emit_with_metadata(
      IntCompareImmediate(Equal, 42UL),
      [builder.parameters()[1]],
      [I32],
      @lowering.InstructionMetadata::empty(),
    )[0]
  builder.return_([result])
  builder.finish()
  let diagnostics = @x64_target.diagnose_selected(session.finish_selected())
  inspect(diagnostics.target_vcode.contains("LoadConstant"), content="true")
  inspect(diagnostics.target_vcode.contains("CompareSet"), content="true")
}

///|
test "x64 tail calls validate hidden result-area clobbers with live roots" {
  for indirect in [false, true] {
    let abi = @x64_target.InternalAbi::new(
      7,
      12,
      [6, 2, 1, 8, 9],
      [0, 1, 2, 3, 4, 5, 6, 7],
      [0, 2, 1, 8, 9, 6, 7, 10],
      [0, 1, 2, 3, 4, 5, 6, 7],
    )
    let results : Array[@native.ValueType] = Array::make(9, I64)
    let session = @x64_target.DirectLoweringSession::new(
      "tail_result_area",
      Internal,
      [Ptr64, Ptr64, GcRef64],
      results,
      @x64_target.LoweringContext::new(abi),
    )
    let builder = @lowering.DirectBuilder::new(
      [Ptr64, Ptr64, GcRef64],
      session.sink(),
      call_abi=@lowering.CallAbiElaboration::new(
        function_frame=@lowering.FunctionRootFrameAbi::new(
          @native.ExternalSymbol::new("frame.enter"),
          @native.ExternalSymbol::new("frame.leave"),
        ),
      ),
    )
    builder.begin_function_roots(1)
    let params = builder.parameters()
    builder.define_function_root(params[2])
    let call = @native.NativeCall::new(
      if indirect {
        Indirect
      } else {
        Internal(@native.CodeSymbol::new("callee"))
      },
      @native.Signature::new([Ptr64, GcRef64], results),
      Internal,
      @native.CallBehavior::conservative(),
    )
    let operands = if indirect {
      [params[1], params[0], params[2]]
    } else {
      [params[0], params[2]]
    }
    builder.tail_call_with_metadata(
      call,
      operands,
      @lowering.TerminatorMetadata::new(None, [params[2]]),
    )
    builder.finish()
    // Public selection always verifies, independently of the JIT's optional gate.
    let selected = session.finish_selected()
    @x64_target.compile_selected(selected, verify_allocation=true) |> ignore
  }
}

///|
test "x64 compact function masks verify and allocate loop block parameters" {
  let abi = @x64_target.InternalAbi::new(
    7,
    12,
    [6, 2, 1, 8, 9],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 2, 1, 8, 9, 6, 7, 10],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let session = @x64_target.DirectLoweringSession::new(
    "compact_root_masks",
    Internal,
    [Ptr64, GcRef64],
    [],
    @x64_target.LoweringContext::new(abi),
  )
  let builder = @lowering.DirectBuilder::new(
    [Ptr64, GcRef64],
    session.sink(),
    call_abi=@lowering.CallAbiElaboration::new(
      function_frame=@lowering.FunctionRootFrameAbi::new(
        @native.ExternalSymbol::new("frame.enter"),
        @native.ExternalSymbol::new("frame.leave"),
      ),
    ),
  )
  builder.begin_function_roots(512)
  let params = builder.parameters()
  builder.define_function_root(params[1])
  for live in [[params[1]], []] {
    builder.emit_with_metadata(
      Call(
        @native.NativeCall::new(
          External(@native.ExternalSymbol::new("collect")),
          @native.Signature::new([Ptr64], []),
          Platform,
          @native.CallBehavior::conservative(),
        ),
      ),
      [params[0]],
      [],
      @lowering.InstructionMetadata::new(None, live),
    )
    |> ignore
  }
  builder.return_([])
  builder.finish()
  @x64_target.compile_selected(
    session.finish_selected(),
    verify_allocation=true,
  )
  |> ignore
}

///|
test "x64 pointer carrier aliases keep semantic types on every CFG edge" {
  let abi = @x64_target.InternalAbi::new(
    7,
    12,
    [6, 2, 1, 8, 9],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 2, 1, 8, 9, 6, 7, 10],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let exercise = fn(pointer_result : Bool, form : Int32, cast : Bool) raise {
    let session = @x64_target.DirectLoweringSession::new(
      "typed_carrier_edges",
      Internal,
      [Ptr64, I64, I32],
      [I64],
      @x64_target.LoweringContext::new(abi),
    )
    let builder = @lowering.DirectBuilder::new(
      [Ptr64, I64, I32],
      session.sink(),
    )
    let params = builder.parameters()
    let from = if pointer_result { @native.ValueType::I64 } else { Ptr64 }
    let to = if pointer_result { @native.ValueType::Ptr64 } else { I64 }
    let input = if pointer_result { params[1] } else { params[0] }
    let converted = if cast {
      builder.emit_with_metadata(
        Convert(Bitcast(from, to)),
        [input],
        [to],
        @lowering.InstructionMetadata::empty(),
      )[0]
    } else {
      input
    }
    let target = builder.create_block([to])
    match form {
      0 => builder.jump(target, [converted])
      1 => builder.branch(params[2], target, [converted], target, [converted])
      2 =>
        builder.branch_int_compare(
          Equal,
          params[1],
          params[1],
          target,
          [converted],
          target,
          [converted],
        )
      3 =>
        builder.branch_int_compare_immediate(
          Equal,
          params[1],
          0UL,
          target,
          [converted],
          target,
          [converted],
        )
      _ =>
        builder.switch(
          params[2],
          [(0UL, target, [converted]), (1UL, target, [converted])],
          target,
          [converted],
        )
    }
    builder.switch_to_block(target)
    let argument = builder.block_parameters(target)[0]
    let bits = if pointer_result {
      builder.emit_with_metadata(
        Convert(Bitcast(Ptr64, I64)),
        [argument],
        [I64],
        @lowering.InstructionMetadata::empty(),
      )[0]
    } else {
      argument
    }
    builder.return_([bits])
    builder.finish()
    if cast {
      @x64_target.compile_selected(
        session.finish_selected(),
        verify_allocation=true,
      )
      |> ignore
    } else {
      try session.finish_selected() |> ignore catch {
        error => assert_true(error.to_string().contains("EdgeClassMismatch"))
      } noraise {
        _ => fail("a missing semantic conversion was accepted")
      }
    }
  }
  for pointer_result in [true, false] {
    for form in 0..<5 {
      exercise(pointer_result, form, true)
    }
  }
  exercise(true, 0, false)
}

///|
test "x64 emits repeated mixed ABI groups at block-local positions" {
  let abi = @x64_target.InternalAbi::new(
    7,
    12,
    [6, 2, 1, 8, 9],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 2, 1, 8, 9, 6, 7, 10],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let values : Array[@native.ValueType] = Array::make(9, I64)
  for _ in 0..<9 {
    values.push(F64)
  }
  values.push(V128)
  let parameters = [@native.ValueType::Ptr64]
  parameters.append(values)
  let session = @x64_target.DirectLoweringSession::new(
    "repeated_abi_groups",
    Internal,
    parameters,
    values,
    @x64_target.LoweringContext::new(abi),
  )
  let builder = @lowering.DirectBuilder::new(parameters, session.sink())
  let context = builder.parameters()[0]
  let block = builder.create_block(values)
  builder.jump(block, builder.parameters()[1:].to_owned())
  builder.switch_to_block(block)
  let mut arguments = builder.block_parameters(block)
  for _ in 0..<32 {
    let operands = [context]
    operands.append(arguments)
    arguments = builder.emit_with_metadata(
      Call(
        @native.NativeCall::new(
          Internal(@native.CodeSymbol::new("callee")),
          @native.Signature::new(parameters, values),
          Internal,
          @native.CallBehavior::conservative(),
        ),
      ),
      operands,
      values,
      @lowering.InstructionMetadata::empty(),
    )
  }
  builder.return_(arguments)
  builder.finish()
  let (object, _) = @x64_target.compile_selected(
    session.finish_selected(),
    verify_allocation=true,
  )
  // Every call needs its own transfer group, including stack/vector results.
  assert_eq(object.relocations().length(), 32)
}
