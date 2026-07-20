///|
test "AArch64 target compiles semantic MachV through the final target seams" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "shadow_integer_add",
    Internal,
    [Ptr64, I64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let result = builder.emit(IntBinary(Add), [parameters[1], parameters[2]], [
      I64,
    ])[0]
  builder.return_([result])
  debug_inspect(
    build_aarch64_target(builder.finish()).object,
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0x00,
      #|    0x00,
      #|    0x01,
      #|    0x8b,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 target binds product environment fields explicitly" {
  let field = @semantic_machv.EnvironmentField::new(
    "wasmoon.test.pointer",
    Ptr64,
  )
  let builder = @semantic_machv.FunctionBuilder::new(
    "shadow_environment_field",
    Internal,
    [Ptr64],
    [Ptr64],
  )
  let result = builder.emit(
      EnvironmentField(field),
      [builder.parameters()[0]],
      [Ptr64],
    )[0]
  builder.return_([result])
  debug_inspect(
    build_aarch64_target(builder.finish(), environment_field_path=fn(
      candidate,
    ) {
      if candidate == field {
        Some([16])
      } else {
        None
      }
    }).object,
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [0x00, 0x08, 0x40, 0xf9, 0xc0, 0x03, 0x5f, 0xd6],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "Wasmoon runtime ABI elaboration makes roots and stack maps explicit" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "shadow_allocation_abi",
    Internal,
    [Ptr64, GcRef64, GcRef64],
    [I64],
  )
  let parameters = builder.parameters()
  let fields = builder.create_stack_object(8, 8)
  let type_index = builder.emit(I32Const(7U), [], [I32])[0]
  let fields_address = builder.emit(StackAddress(fields), [], [Ptr64])[0]
  let field_count = builder.emit(I32Const(1U), [], [I32])[0]
  let allocation_symbol = @semantic_machv.ExternalSymbol::new(
    "wasm.runtime.gc.alloc_struct_slow",
  )
  let result = builder.emit_with_metadata(
      Call(
        @semantic_machv.SemanticCall::new(
          External(allocation_symbol),
          @semantic_machv.Signature::new([Ptr64, I32, Ptr64, I32], [I64]),
          Platform,
          @semantic_machv.CallBehavior::new(ReadWrite, true, false, true, false),
        ),
      ),
      [parameters[0], type_index, fields_address, field_count],
      [I64],
      @semantic_machv.InstructionMetadata::new(None, [
        parameters[1],
        parameters[2],
      ]),
    )[0]
  builder.return_([result])
  inspect(
    elaborate_wasmoon_runtime_abi(
      builder.finish(),
      [allocation_symbol],
      (
        @semantic_machv.ExternalSymbol::new(
          "wasmoon.runtime.gc.push_root_scope",
        ),
        @semantic_machv.ExternalSymbol::new("wasmoon.runtime.gc.pop_root_scope"),
      ),
    ),
    content=(
      #|machv shadow_allocation_abi [internal](v0:ptr64, v1:gcref64, v2:gcref64) -> (i64) {
      #|stack0: size=8, alignment=8
      #|stack1: size=16, alignment=16
      #|block0:
      #|  v3:i32 = i32.const 7
      #|  v4:ptr64 = stack.address stack0
      #|  v5:i32 = i32.const 1
      #|  v6:ptr64 = stack.address stack1
      #|  store {
      #|  width: W64,
      #|  value_type: GcRef64,
      #|  offset: 0,
      #|  endianness: Little,
      #|  trap: None,
      #|} v6, v1 [memory=write]
      #|  store {
      #|  width: W64,
      #|  value_type: GcRef64,
      #|  offset: 8,
      #|  endianness: Little,
      #|  trap: None,
      #|} v6, v2 [memory=write]
      #|  v7:i32 = i32.const 2
      #|  call external @wasmoon.runtime.gc.push_root_scope (ptr64, ptr64, i32) -> () [platform] v0, v6, v7 [memory=read-write, trap]
      #|  v8:i32 = i32.const 0
      #|  v9:i64 = call external @wasm.runtime.gc.alloc_struct_slow (ptr64, i32, ptr64, i32, i32) -> (i64) [platform] v0, v3, v4, v5, v8 [memory=read-write, trap, gc-safepoint] roots=[v1, v2] stack-map=0:1
      #|  call external @wasmoon.runtime.gc.pop_root_scope (ptr64) -> () [platform] v0 [memory=read-write, trap]
      #|  return v9
      #|}
    ),
  )
}

///|
test "runtime ABI elaboration follows CFG order instead of block storage order" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "shadow_cfg_order",
    Internal,
    [],
    [I32],
  )
  let return_block = builder.create_block([])
  let definition_block = builder.create_block([])
  builder.jump(definition_block, [])
  builder.switch_to_block(definition_block)
  let value = builder.emit(I32Const(42U), [], [I32])[0]
  builder.jump(return_block, [])
  builder.switch_to_block(return_block)
  builder.return_([value])
  inspect(
    elaborate_wasmoon_runtime_abi(
      builder.finish(),
      [],
      (
        @semantic_machv.ExternalSymbol::new(
          "wasmoon.runtime.gc.push_root_scope",
        ),
        @semantic_machv.ExternalSymbol::new("wasmoon.runtime.gc.pop_root_scope"),
      ),
    ),
    content=(
      #|machv shadow_cfg_order [internal]() -> (i32) {
      #|block0:
      #|  jump block2
      #|block1:
      #|  return v0
      #|block2:
      #|  v0:i32 = i32.const 42
      #|  jump block1
      #|}
    ),
  )
}

///|
test "AArch64 target code executes through the production entry ABI" {
  match host_target_arch() {
    AArch64 => ()
    _ => return
  }
  let builder = @semantic_machv.FunctionBuilder::new(
    "shadow_executable_add",
    Internal,
    [Ptr64, I64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let result = builder.emit(IntBinary(Add), [parameters[1], parameters[2]], [
      I64,
    ])[0]
  builder.return_([result])
  let object = build_aarch64_target(builder.finish()).object
  let candidate_bytes = object.code().map(byte => byte.to_int())
  guard ExecCode::try_alloc(candidate_bytes) is Some(candidate) else {
    fail("failed to allocate executable candidate code")
  }
  let trampoline_bytes = build_entry_trampoline_for_target(
    [I64, I64],
    [I64],
    AArch64,
  ) catch {
    error => fail("failed to build AArch64 entry trampoline: \{error}")
  }
  guard ExecCode::try_alloc(trampoline_bytes) is Some(trampoline) else {
    fail("failed to allocate executable entry trampoline")
  }
  guard NativeJITContext::try_alloc(1) is Some(context) else {
    fail("failed to allocate native JIT context")
  }
  let values = FixedArray::from_array([20L, 22L, 0L])
  let trap = context.call_trampoline(
    trampoline.ptr(),
    candidate.ptr(),
    values,
    values.length(),
    false,
  )
  debug_inspect(
    (trap, values[0], values[1], values[2]),
    content="(0, 20, 22, 42)",
  )
}

///|
fn install_aarch64_link_plan(
  plan : @aarch64_target.AArch64LinkPlan,
  executable : ExecCode,
  resolve : (@code_object.RelocationTarget) -> Int64?,
) -> Bool raise @aarch64_target.AArch64LinkError {
  let linked = plan.link(executable.ptr(), resolve)
  let bytes = FixedArray::make(linked.length(), b'\x00')
  for index, byte in linked {
    bytes[index] = byte
  }
  @jit_ffi.c_jit_copy_code(executable.ptr(), bytes, bytes.length()) == 0
}

///|
test "AArch64 target executes internal and external relocations" {
  match host_target_arch() {
    AArch64 => ()
    _ => return
  }
  let callee_symbol = @semantic_machv.CodeSymbol::new("shadow.callee")
  let poll_symbol = @semantic_machv.ExternalSymbol::new(
    "wasmoon.runtime.cancel_poll",
  )
  let callee = @semantic_machv.FunctionBuilder::new(
    "shadow_linked_callee",
    Internal,
    [Ptr64, I64],
    [I64],
  )
  let callee_parameters = callee.parameters()
  callee.emit(
    Call(
      @semantic_machv.SemanticCall::new(
        External(poll_symbol),
        @semantic_machv.Signature::new([Ptr64], [I32]),
        Platform,
        @semantic_machv.CallBehavior::new(ReadWrite, true, false, false, true),
      ),
    ),
    [callee_parameters[0]],
    [I32],
  )
  |> ignore
  let one = callee.emit(I64Const(1UL), [], [I64])[0]
  let incremented = callee.emit(IntBinary(Add), [callee_parameters[1], one], [
      I64,
    ])[0]
  callee.return_([incremented])

  let caller = @semantic_machv.FunctionBuilder::new(
    "shadow_linked_caller",
    Internal,
    [Ptr64, I64],
    [I64],
  )
  let caller_parameters = caller.parameters()
  let called = caller.emit(
      Call(
        @semantic_machv.SemanticCall::new(
          Internal(callee_symbol),
          @semantic_machv.Signature::new([Ptr64, I64], [I64]),
          Internal,
          @semantic_machv.CallBehavior::new(
            ReadWrite,
            true,
            false,
            false,
            false,
          ),
        ),
      ),
      caller_parameters,
      [I64],
    )[0]
  caller.return_([called])

  let callee_plan = @aarch64_target.prepare_aarch64_link(
    build_aarch64_target(callee.finish()).object,
  ) catch {
    error => fail("failed to prepare callee link plan: \{error}")
  }
  let caller_plan = @aarch64_target.prepare_aarch64_link(
    build_aarch64_target(caller.finish()).object,
  ) catch {
    error => fail("failed to prepare caller link plan: \{error}")
  }
  guard ExecCode::try_alloc(callee_plan.code().map(byte => byte.to_int()))
    is Some(callee_code) else {
    fail("failed to allocate linked callee")
  }
  guard ExecCode::try_alloc(caller_plan.code().map(byte => byte.to_int()))
    is Some(caller_code) else {
    fail("failed to allocate linked caller")
  }
  let runtime = RuntimeSymbolResolver::with_wasmoon_runtime_symbols()
  let callee_installed = install_aarch64_link_plan(callee_plan, callee_code, fn(
    target,
  ) {
    match target {
      External(symbol) => runtime.resolve(symbol.name)
      _ => None
    }
  }) catch {
    error => fail("failed to link AArch64 callee: \{error}")
  }
  if !callee_installed {
    fail("failed to install linked AArch64 callee")
  }
  let caller_installed = install_aarch64_link_plan(caller_plan, caller_code, fn(
    target,
  ) {
    match target {
      Code(symbol) if symbol == callee_symbol => Some(callee_code.ptr())
      _ => None
    }
  }) catch {
    error => fail("failed to link AArch64 caller: \{error}")
  }
  if !caller_installed {
    fail("failed to install linked AArch64 caller")
  }
  let trampoline_bytes = build_entry_trampoline_for_target(
    [I64],
    [I64],
    AArch64,
  ) catch {
    error => fail("failed to build linked-call trampoline: \{error}")
  }
  guard ExecCode::try_alloc(trampoline_bytes) is Some(trampoline) else {
    fail("failed to allocate linked-call trampoline")
  }
  guard NativeJITContext::try_alloc(2) is Some(context) else {
    fail("failed to allocate linked-call JIT context")
  }
  let values = FixedArray::from_array([41L, 0L])
  let trap = context.call_trampoline(
    trampoline.ptr(),
    caller_code.ptr(),
    values,
    values.length(),
    false,
  )
  debug_inspect((trap, values[0], values[1]), content="(0, 41, 42)")
}
