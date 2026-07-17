///|
test "AArch64 shadow compiles semantic MachV through the final target seams" {
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
    build_aarch64_shadow(builder.finish()),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xe3,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0x02,
      #|    0x00,
      #|    0x01,
      #|    0x8b,
      #|    0xe0,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
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
test "AArch64 shadow binds product environment fields explicitly" {
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
    build_aarch64_shadow(builder.finish(), environment_field_path=fn(
      candidate,
    ) {
      if candidate == field {
        Some([16])
      } else {
        None
      }
    }),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xe1,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0x20,
      #|    0x08,
      #|    0x40,
      #|    0xf9,
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
