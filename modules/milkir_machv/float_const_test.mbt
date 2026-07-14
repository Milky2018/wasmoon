///|
fn float_const_test_abi() -> @abi.EmbeddingABI {
  EmbeddingABI({
    context_arg: { index: 0, class: Int },
    user_arg_gprs: [{ index: 1, class: Int }, { index: 2, class: Int }],
    arg_fprs: [],
    ret_gprs: [{ index: 0, class: Int }],
    ret_fprs: [{ index: 0, class: Float64 }],
  })
}

///|
fn lowered_contains_f32_bits(bits : UInt) -> Bool raise {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("f32_bits")
  builder.add_result(F32)
  let value = builder.fconst_f32(Float::reinterpret_from_uint(bits))
  builder.return_([value])
  let lowered = @lower.lower_function(
    builder.finalize(),
    isa=AArch64,
    embedding_abi=Some(float_const_test_abi()),
    run_ir_opt=false,
  )
  for block in lowered.blocks {
    for inst in block.insts {
      if inst.opcode is LoadConstF32(actual) {
        return actual.reinterpret_as_uint() == bits
      }
    }
  }
  false
}

///|
fn lowered_contains_f64_bits(bits : UInt64) -> Bool raise {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("f64_bits")
  builder.add_result(F64)
  let value = builder.fconst_f64(bits.reinterpret_as_double())
  builder.return_([value])
  let lowered = @lower.lower_function(
    builder.finalize(),
    isa=AArch64,
    embedding_abi=Some(float_const_test_abi()),
    run_ir_opt=false,
  )
  for block in lowered.blocks {
    for inst in block.insts {
      if inst.opcode is LoadConstF64(actual) {
        return actual.reinterpret_as_uint64() == bits
      }
    }
  }
  false
}

///|
test "lower f32 constants without changing their bit patterns" {
  for bits in [0U, 0x80000000U, 0x3F800000U, 0x7FC00001U] {
    inspect(lowered_contains_f32_bits(bits), content="true")
  }
}

///|
test "lower f64 constants without changing their bit patterns" {
  for
    bits in [
      0UL, 0x8000000000000000UL, 0x3FF0000000000000UL, 0x7FF8000000000001UL,
    ] {
    inspect(lowered_contains_f64_bits(bits), content="true")
  }
}
