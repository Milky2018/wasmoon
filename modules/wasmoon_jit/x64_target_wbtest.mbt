///|
test "x64 target preserves the Wasmoon overflow-result ABI" {
  let result_types : Array[@native.ValueType] = [
    I32,
    I32,
    I32,
    I32,
    I32,
    I32,
    I32,
    I32,
    I32,
  ]
  let builder = @semantic_machv.FunctionBuilder::new(
    "x64_overflow_results",
    Internal,
    [Ptr64],
    result_types,
  )
  let results : Array[@semantic_machv.Value] = []
  for index in 0..<result_types.length() {
    results.push(
      builder.emit(I32Const((index + 1).reinterpret_as_uint()), [], [I32])[0],
    )
  }
  builder.return_(results)
  debug_inspect(
    build_x64_target(builder.finish_prepared_selection()).object,
    content=(
      #|{
      #|  architecture: X64,
      #|  code: [
      #|    0x55,
      #|    0x48,
      #|    0x89,
      #|    0xe5,
      #|    0x48,
      #|    0x81,
      #|    0xec,
      #|    0x20,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x89,
      #|    0x9c,
      #|    0x24,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x4c,
      #|    0x89,
      #|    0xa4,
      #|    0x24,
      #|    0x08,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x4c,
      #|    0x89,
      #|    0xac,
      #|    0x24,
      #|    0x10,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x4c,
      #|    0x89,
      #|    0xe0,
      #|    0x48,
      #|    0xb9,
      #|    0x01,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0xba,
      #|    0x02,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0xbb,
      #|    0x03,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0xbe,
      #|    0x04,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0xbf,
      #|    0x05,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x49,
      #|    0xb8,
      #|    0x06,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x49,
      #|    0xb9,
      #|    0x07,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x49,
      #|    0xbc,
      #|    0x08,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x49,
      #|    0xbd,
      #|    0x09,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x44,
      #|    0x89,
      #|    0xa8,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x89,
      #|    0xc8,
      #|    0x89,
      #|    0xd9,
      #|    0x45,
      #|    0x89,
      #|    0xe2,
      #|    0x45,
      #|    0x89,
      #|    0xc7,
      #|    0x41,
      #|    0x89,
      #|    0xf0,
      #|    0x44,
      #|    0x89,
      #|    0xfe,
      #|    0x45,
      #|    0x89,
      #|    0xcf,
      #|    0x41,
      #|    0x89,
      #|    0xf9,
      #|    0x44,
      #|    0x89,
      #|    0xff,
      #|    0x4c,
      #|    0x8b,
      #|    0xac,
      #|    0x24,
      #|    0x10,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x4c,
      #|    0x8b,
      #|    0xa4,
      #|    0x24,
      #|    0x08,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x8b,
      #|    0x9c,
      #|    0x24,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x81,
      #|    0xc4,
      #|    0x20,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x5d,
      #|    0xc3,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [
      #|    { offset: 1, operation: StackAlloc(size=8) },
      #|    { offset: 1, operation: SaveRegister(Int, 5, cfa_offset=-16) },
      #|    { offset: 4, operation: SetFramePointer(Int, 5, cfa_offset=16) },
      #|    { offset: 11, operation: StackAlloc(size=32) },
      #|    { offset: 19, operation: SaveRegister(Int, 3, cfa_offset=-48) },
      #|    { offset: 27, operation: SaveRegister(Int, 12, cfa_offset=-40) },
      #|    { offset: 35, operation: SaveRegister(Int, 13, cfa_offset=-32) },
      #|  ],
      #|}
    ),
  )
}

///|
test "x64 target preserves an incoming result area across indirect calls" {
  let result_types : Array[@native.ValueType] = [
    I32,
    I32,
    I32,
    I32,
    I32,
    I32,
    I32,
    I32,
    I32,
  ]
  let builder = @semantic_machv.FunctionBuilder::new(
    "x64_indirect_overflow_results",
    Internal,
    [Ptr64, Ptr64],
    result_types,
  )
  let parameters = builder.parameters()
  let call = @semantic_machv.SemanticCall::new(
    Indirect,
    @native.Signature::new([Ptr64], result_types),
    Internal,
    @native.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  let results = builder.emit(
    Call(call),
    [parameters[1], parameters[0]],
    result_types,
  )
  builder.return_(results)
  debug_inspect(
    build_x64_target(builder.finish_prepared_selection()).object,
    content=(
      #|{
      #|  architecture: X64,
      #|  code: [
      #|    0x55,
      #|    0x48,
      #|    0x89,
      #|    0xe5,
      #|    0x48,
      #|    0x81,
      #|    0xec,
      #|    0x30,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x89,
      #|    0x9c,
      #|    0x24,
      #|    0x10,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x4c,
      #|    0x89,
      #|    0xa4,
      #|    0x24,
      #|    0x18,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x4c,
      #|    0x89,
      #|    0xac,
      #|    0x24,
      #|    0x20,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x4c,
      #|    0x89,
      #|    0xe3,
      #|    0x48,
      #|    0x89,
      #|    0xf0,
      #|    0x49,
      #|    0x89,
      #|    0xe4,
      #|    0xff,
      #|    0xd0,
      #|    0x45,
      #|    0x89,
      #|    0xd4,
      #|    0x44,
      #|    0x8b,
      #|    0xac,
      #|    0x24,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x44,
      #|    0x89,
      #|    0xab,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x45,
      #|    0x89,
      #|    0xe2,
      #|    0x4c,
      #|    0x8b,
      #|    0xac,
      #|    0x24,
      #|    0x20,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x4c,
      #|    0x8b,
      #|    0xa4,
      #|    0x24,
      #|    0x18,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x8b,
      #|    0x9c,
      #|    0x24,
      #|    0x10,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x81,
      #|    0xc4,
      #|    0x30,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x5d,
      #|    0xc3,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [
      #|    { offset: 1, operation: StackAlloc(size=8) },
      #|    { offset: 1, operation: SaveRegister(Int, 5, cfa_offset=-16) },
      #|    { offset: 4, operation: SetFramePointer(Int, 5, cfa_offset=16) },
      #|    { offset: 11, operation: StackAlloc(size=48) },
      #|    { offset: 19, operation: SaveRegister(Int, 3, cfa_offset=-48) },
      #|    { offset: 27, operation: SaveRegister(Int, 12, cfa_offset=-40) },
      #|    { offset: 35, operation: SaveRegister(Int, 13, cfa_offset=-32) },
      #|  ],
      #|}
    ),
  )
}

///|
fn install_x64_link_plan(
  plan : @x64_target.X64LinkPlan,
  executable : ExecCode,
  resolve : (@code_object.RelocationTarget) -> Int64?,
) -> Bool raise @x64_target.X64LinkError {
  let linked = plan.link(executable.ptr(), resolve)
  executable.finalize(linked)
}

///|
test "x64 expanded tail calls preserve native helper stack alignment" {
  let host = host_native_target() catch { _ => return }
  match host {
    X64 => ()
    _ => return
  }
  let alignment_probe = @native_test_support.x64_stack_alignment_probe_ptr()
  if alignment_probe == 0L {
    return
  }
  let callee_symbol = @native.CodeSymbol::new(
    "shadow.expanded_tail_alignment_callee",
  )
  let probe_symbol = @native.ExternalSymbol::new(
    "wasmoon.test.x64_stack_alignment_probe",
  )
  let callee_params : Array[@native.ValueType] = [Ptr64]
  for _ in 0..<8 {
    callee_params.push(I64)
  }
  let callee = @semantic_machv.FunctionBuilder::new(
    "shadow_expanded_tail_alignment_callee",
    Internal,
    callee_params,
    [I64],
  )
  let callee_parameters = callee.parameters()
  let alignment = callee.emit(
      Call(
        @semantic_machv.SemanticCall::new(
          External(probe_symbol),
          @native.Signature::new([], [I64]),
          Platform,
          @native.CallBehavior::new(ReadWrite, true, false, false, false),
        ),
      ),
      [],
      [I64],
    )[0]
  let stack_sum = callee.emit(
      IntBinary(Add),
      [callee_parameters[6], callee_parameters[7]],
      [I64],
    )[0]
  let complete_stack_sum = callee.emit(
      IntBinary(Add),
      [stack_sum, callee_parameters[8]],
      [I64],
    )[0]
  let hundred = callee.emit(I64Const(100UL), [], [I64])[0]
  let scaled_alignment = callee.emit(IntBinary(Mul), [alignment, hundred], [I64])[0]
  let result = callee.emit(
      IntBinary(Add),
      [scaled_alignment, complete_stack_sum],
      [I64],
    )[0]
  callee.return_([result])

  let caller = @semantic_machv.FunctionBuilder::new(
    "shadow_expanded_tail_alignment_caller",
    Internal,
    [Ptr64],
    [I64],
  )
  let caller_operands = [caller.parameters()[0]]
  for index in 0..<8 {
    caller_operands.push(caller.emit(I64Const(index.to_uint64()), [], [I64])[0])
  }
  caller.tail_call(
    @semantic_machv.SemanticCall::new(
      Internal(callee_symbol),
      @native.Signature::new(callee_params, [I64]),
      Internal,
      @native.CallBehavior::new(ReadWrite, true, true, false, false),
    ),
    caller_operands,
  )

  let callee_plan = @x64_target.prepare_x64_link(
    build_x64_target(callee.finish_prepared_selection()).object,
  ) catch {
    error => fail("failed to prepare x64 callee link plan: \{error}")
  }
  let caller_plan = @x64_target.prepare_x64_link(
    build_x64_target(caller.finish_prepared_selection()).object,
  ) catch {
    error => fail("failed to prepare x64 caller link plan: \{error}")
  }
  guard ExecCode::try_stage(callee_plan.code().length()) is Some(callee_code) else {
    fail("failed to allocate linked x64 callee")
  }
  guard ExecCode::try_stage(caller_plan.code().length()) is Some(caller_code) else {
    fail("failed to allocate linked x64 caller")
  }
  let callee_installed = install_x64_link_plan(callee_plan, callee_code, fn(
    target,
  ) {
    match target {
      External(symbol) if symbol == probe_symbol => Some(alignment_probe)
      _ => None
    }
  }) catch {
    error => fail("failed to link x64 callee: \{error}")
  }
  if !callee_installed {
    fail("failed to install linked x64 callee")
  }
  let caller_installed = install_x64_link_plan(caller_plan, caller_code, fn(
    target,
  ) {
    match target {
      Code(symbol) if symbol == callee_symbol => Some(callee_code.ptr())
      _ => None
    }
  }) catch {
    error => fail("failed to link x64 caller: \{error}")
  }
  if !caller_installed {
    fail("failed to install linked x64 caller")
  }

  let direct_trampoline_bytes = build_entry_trampoline_for_target(
    [I64, I64, I64, I64, I64, I64, I64, I64],
    [I64],
    X64,
  ) catch {
    error => fail("failed to build direct x64 trampoline: \{error}")
  }
  guard ExecCode::try_alloc(direct_trampoline_bytes) is Some(direct_trampoline) else {
    fail("failed to allocate direct x64 trampoline")
  }
  let tail_trampoline_bytes = build_entry_trampoline_for_target([], [I64], X64) catch {
    error => fail("failed to build tail-call x64 trampoline: \{error}")
  }
  guard ExecCode::try_alloc(tail_trampoline_bytes) is Some(tail_trampoline) else {
    fail("failed to allocate tail-call x64 trampoline")
  }
  guard NativeJITContext::try_alloc(2) is Some(context) else {
    fail("failed to allocate x64 JIT context")
  }
  let direct_values = FixedArray::from_array([
    0L, 1L, 2L, 3L, 4L, 5L, 6L, 7L, 0L,
  ])
  let direct_trap = context.call_trampoline(
    direct_trampoline.ptr(),
    callee_code.ptr(),
    direct_values,
    direct_values.length(),
    false,
  )
  let tail_values = FixedArray::from_array([0L])
  let tail_trap = context.call_trampoline(
    tail_trampoline.ptr(),
    caller_code.ptr(),
    tail_values,
    tail_values.length(),
    false,
  )
  debug_inspect(
    (direct_trap, direct_values[8], tail_trap, tail_values[0]),
    content="(0, 818, 0, 818)",
  )
  tail_trampoline.release() |> ignore
  direct_trampoline.release() |> ignore
  caller_code.release() |> ignore
  callee_code.release() |> ignore
}
