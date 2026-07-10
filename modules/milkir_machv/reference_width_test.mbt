///|
fn reference_width_test_abi() -> @abi.EmbeddingABI {
  EmbeddingABI({
    context_arg: { index: 0, class: Int },
    user_arg_gprs: [{ index: 1, class: Int }, { index: 2, class: Int }],
    arg_fprs: [],
    ret_gprs: [{ index: 0, class: Int }],
    ret_fprs: [],
  })
}

///|
fn lower_equality(ty : @milkir.Type, name : String) -> String raise {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(name)
  builder.add_result(I32)
  let lhs = builder.add_param(ty)
  let rhs = builder.add_param(ty)
  let result = builder.icmp_eq(lhs, rhs)
  builder.return_([result])
  @lower.lower_function(
    builder.finalize(),
    isa=AArch64,
    embedding_abi=Some(reference_width_test_abi()),
    run_ir_opt=false,
  ).print()
}

///|
fn lower_word_binary(
  ty : @milkir.Type,
  opcode : @milkir.Opcode,
  name : String,
) -> String raise {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(name)
  builder.add_result(ty)
  let lhs = builder.add_param(ty)
  let rhs = builder.add_param(ty)
  let result = builder.emit_inst(ty, opcode, [lhs, rhs])
  builder.return_([result])
  @lower.lower_function(
    builder.finalize(),
    isa=AArch64,
    embedding_abi=Some(reference_width_test_abi()),
    run_ir_opt=false,
  ).print()
}

///|
fn lower_branch_equality(ty : @milkir.Type) -> @machv.Function raise {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "branch_equality_\{ty}",
  )
  let lhs = builder.add_param(ty)
  let rhs = builder.add_param(ty)
  let condition = builder.icmp_eq(lhs, rhs)
  let equal = builder.create_block()
  let not_equal = builder.create_block()
  builder.brnz(condition, equal, not_equal)
  builder.switch_to_block(equal)
  builder.return_([])
  builder.switch_to_block(not_equal)
  builder.return_([])
  @lower.lower_function(
    builder.finalize(),
    isa=AArch64,
    embedding_abi=Some(reference_width_test_abi()),
    run_ir_opt=false,
  )
}

///|
fn lower_select_equality(ty : @milkir.Type) -> String raise {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "select_equality_\{ty}",
  )
  builder.add_result(ty)
  let lhs = builder.add_param(ty)
  let rhs = builder.add_param(ty)
  let condition = builder.icmp_eq(lhs, rhs)
  let result = builder.select(condition, lhs, rhs)
  builder.return_([result])
  @lower.lower_function(
    builder.finalize(),
    isa=AArch64,
    embedding_abi=Some(reference_width_test_abi()),
    run_ir_opt=false,
  ).print()
}

///|
test "lower reference OR as a 64-bit MachV operation" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("reference_or")
  builder.add_result(Ref)
  let lhs = builder.add_param(Ref)
  let rhs = builder.add_param(Ref)
  let result = builder.bor(lhs, rhs)
  builder.return_([result])
  let lowered = @lower.lower_function(
    builder.finalize(),
    isa=AArch64,
    embedding_abi=Some(reference_width_test_abi()),
    run_ir_opt=false,
  )
  let text = lowered.print()
  inspect(text.contains("= or32 "), content="false")
  inspect(text.contains("= or "), content="true")
}

///|
test "lower bitwise operations on all 64-bit word carriers" {
  let carrier_types : Array[@milkir.Type] = [Ptr, Ref, CallableRef, OpaqueRef]
  let operations : Array[(@milkir.Opcode, String)] = [
    (Band, "and"),
    (Bor, "or"),
    (Bxor, "xor"),
  ]
  for ty in carrier_types {
    for operation in operations {
      let (opcode, mnemonic) = operation
      let text = lower_word_binary(ty, opcode, "\{mnemonic}_\{ty}")
      if text.contains("= \{mnemonic}32 ") || !text.contains("= \{mnemonic} ") {
        fail("expected 64-bit \{mnemonic} lowering for \{ty}:\n\{text}")
      }
    }
  }
}

///|
test "lower reference and pointer equality as 64-bit MachV comparisons" {
  let carrier_types : Array[@milkir.Type] = [Ptr, Ref, CallableRef, OpaqueRef]
  for ty in carrier_types {
    let text = lower_equality(ty, "equality_\{ty}")
    if text.contains("= cmp32.eq ") || !text.contains("= cmp.eq ") {
      fail("expected 64-bit equality lowering for \{ty}:\n\{text}")
    }
  }
}

///|
test "preserve reference comparison width when fusing branches and selects" {
  for ty in ([Ptr, Ref] : Array[@milkir.Type]) {
    let lowered = lower_branch_equality(ty)
    guard lowered.get_blocks()[0].terminator()
      is Some(BranchCmp(_, _, _, is_64, _, _)) else {
      fail("expected fused branch comparison for \{ty}")
    }
    if !is_64 {
      fail("expected 64-bit fused branch comparison for \{ty}")
    }
    let select_text = lower_select_equality(ty)
    if select_text.contains("= select_cmp32.eq ") ||
      !select_text.contains("= select_cmp.eq ") {
      fail("expected 64-bit fused select comparison for \{ty}:\n\{select_text}")
    }
  }
}
