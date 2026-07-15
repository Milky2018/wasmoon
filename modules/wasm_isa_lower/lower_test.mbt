///|
fn test_context_slots() -> WasmContextSlots {
  {
    memory0_base: 0,
    function_table: 0,
    table0_base: 0,
    table_directory: 0,
    memory_directory: 0,
    pointer_stride: 8,
  }
}

///|
fn test_embedding_abi() -> @abi.EmbeddingABI {
  EmbeddingABI(
    {
      context_arg: { index: 0, class: Int },
      user_arg_gprs: [
        { index: 1, class: Int },
        { index: 2, class: Int },
        { index: 3, class: Int },
        { index: 4, class: Int },
      ],
      arg_fprs: [],
      ret_gprs: [{ index: 0, class: Int }],
      ret_fprs: [],
    },
    reg_roles={
      context: Some({ index: 27, class: Int }),
      context_cache_0: None,
      context_cache_1: None,
      extra_results_ptr: None,
    },
    context_layout=Some({
      slots: [
        { id: 0, offset: 0, mutability: Immutable, cache_role: NoContextCache },
      ],
      active_function_index_slot: None,
      allocation_cursor_slot: None,
      allocation_limit_slot: None,
    }),
  )
}

///|
test "Wasm lowering returns validation errors for unknown opcodes" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("unknown_wasm_opcode")
  builder.emit_void_ext_inst(ExtOp("wasm", "typo", []), [])
  builder.return_([])
  try lower_function(builder.get_function(), test_context_slots()) catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="unknown Wasm MilkIR extension opcode 'typo'")
        ),
      )
  } noraise {
    _ => fail("expected Wasm lowering to return the validation error")
  }
}

///|
test "Wasm lowering returns validation errors for malformed immediates" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "malformed_wasm_immediate",
  )
  builder.emit_void_ext_inst(
    ExtOp(
      "wasm",
      "ref_test",
      FixedArray::makei(2, fn(i) { if i == 0 { 3 } else { 2 } }),
    ),
    [],
  )
  builder.return_([])
  try lower_function(builder.get_function(), test_context_slots()) catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="malformed Wasm MilkIR extension 'ref_test': immediate 1 is a bool flag encoded as 0 or 1, got 2")
        ),
      )
  } noraise {
    _ => fail("expected Wasm lowering to reject malformed immediates")
  }
}

///|
test "Wasm lowering rejects missing fixed results before instruction selection" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "missing_wasm_extension_result",
  )
  builder.emit_void_ext_inst(@wasm_milkir.encode(GetExceptionTag), [])
  builder.return_([])
  try lower_function(builder.get_function(), test_context_slots()) catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="malformed Wasm MilkIR extension 'get_exception_tag': expected results [i32], got []")
        ),
      )
  } noraise {
    _ => fail("expected Wasm lowering to reject a missing extension result")
  }
}

///|
test "Wasm lowering rejects removed memory and table extension names" {
  let rejected : Array[@milkir.VerifyError] = []
  let removed : Array[@milkir.ExtOp] = [
    ExtOp("wasm", "memory_grow", [0]),
    ExtOp("wasm", "table_grow", [0]),
  ]
  for ext in removed {
    let builder = @milkir.FunctionBuilder::FunctionBuilder(
      "removed_wasm_opcode",
    )
    builder.emit_void_ext_inst(ext, [])
    builder.return_([])
    try lower_function(builder.get_function(), test_context_slots()) catch {
      err => rejected.push(err)
    } noraise {
      _ => fail("expected Wasm lowering to reject the removed opcode")
    }
  }
  debug_inspect(
    rejected,
    content=(
      #|[
      #|  UnverifiableInstruction(message="unknown Wasm MilkIR extension opcode 'memory_grow'"),
      #|  UnverifiableInstruction(message="unknown Wasm MilkIR extension opcode 'table_grow'"),
      #|]
    ),
  )
}

///|
fn lower_call_indirect_fixture(
  index_type : @milkir.Type,
) -> @machv.Function raise @milkir.VerifyError {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "call_indirect_\{index_type}",
  )
  let index = builder.add_param(index_type)
  @wasm_milkir.call_indirect_multi(builder, 0, 0, [], index, []) |> ignore
  builder.return_([])
  lower_function(
    builder.finalize(),
    test_context_slots(),
    embedding_abi=Some(test_embedding_abi()),
    run_ir_opt=false,
    use_subtype_indirect_check=false,
  )
}

///|
test "table64 call_indirect preserves the full index width" {
  inspect(
    lower_call_indirect_fixture(I64).print(),
    content=(
      #|machv call_indirect_i64(v0:int) {
      #|block0:
      #|    v1 = load.i64 +0 x27
      #|    v4 = add.lsl #4 v1, v0
      #|    v5 = load.i64 +0 v4
      #|    v2 = and #-2305843009213693953 v5
      #|    v3 = load.i32 +8 v4
      #|    v6 = ldi 0
      #|    icmp32 v3, v6
      #|    trap_if.ne #2
      #|    call_ptr[Internal](0) -> 0 results v2
      #|    ret
      #|}
      #|
    ),
  )
}

///|
test "table32 call_indirect zero-extends the index" {
  inspect(
    lower_call_indirect_fixture(I32).print(),
    content=(
      #|machv call_indirect_i32(v0:int) {
      #|block0:
      #|    v1 = load.i64 +0 x27
      #|    v4 = add.uxtw #4 v1, v0
      #|    v5 = load.i64 +0 v4
      #|    v2 = and #-2305843009213693953 v5
      #|    v3 = load.i32 +8 v4
      #|    v6 = ldi 0
      #|    icmp32 v3, v6
      #|    trap_if.ne #2
      #|    call_ptr[Internal](0) -> 0 results v2
      #|    ret
      #|}
      #|
    ),
  )
}

///|
fn lower_return_call_indirect_fixture(
  index_type : @milkir.Type,
) -> @machv.Function raise @milkir.VerifyError {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "return_call_indirect_\{index_type}",
  )
  let index = builder.add_param(index_type)
  @wasm_milkir.return_call_indirect_multi(builder, 0, 0, index, [])
  builder.trap("unreachable after return_call_indirect")
  lower_function(
    builder.finalize(),
    test_context_slots(),
    embedding_abi=Some(test_embedding_abi()),
    run_ir_opt=false,
    use_subtype_indirect_check=false,
  )
}

///|
test "table64 return_call_indirect preserves the full index width" {
  inspect(
    lower_return_call_indirect_fixture(I64).print(),
    content=(
      #|machv return_call_indirect_i64(v0:int) {
      #|block0:
      #|    v1 = load.i64 +0 x27
      #|    v2 = add.lsl #4 v1, v0
      #|    v3 = load.i64 +0 v2
      #|    v4 = and #-2305843009213693953 v3
      #|    v5 = load.i32 +8 v2
      #|    v6 = ldi 0
      #|    icmp32 v5, v6
      #|    trap_if.ne #2
      #|    return_call_indirect(stack=0) -> 0 results v4
      #|    trap #0
      #|}
      #|
    ),
  )
}

///|
test "table32 return_call_indirect zero-extends the index" {
  inspect(
    lower_return_call_indirect_fixture(I32).print(),
    content=(
      #|machv return_call_indirect_i32(v0:int) {
      #|block0:
      #|    v1 = load.i64 +0 x27
      #|    v2 = add.uxtw #4 v1, v0
      #|    v3 = load.i64 +0 v2
      #|    v4 = and #-2305843009213693953 v3
      #|    v5 = load.i32 +8 v2
      #|    v6 = ldi 0
      #|    icmp32 v5, v6
      #|    trap_if.ne #2
      #|    return_call_indirect(stack=0) -> 0 results v4
      #|    trap #0
      #|}
      #|
    ),
  )
}
