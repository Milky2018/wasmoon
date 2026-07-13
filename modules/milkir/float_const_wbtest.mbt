///|
test "F32 numeric constants preserve their value" {
  let builder = FunctionBuilder::FunctionBuilder("f32_value")
  builder.add_result(F32)
  let value = builder.fconst_f32(1.0)
  builder.return_([value])
  inspect(builder.print().contains("fconst 1"), content="true")
}

///|
test "floating constants preserve zero signs and NaN payloads" {
  let f32_bits : Array[UInt] = [0U, 0x80000000U, 0x7FC00001U]
  let f32_builder = FunctionBuilder::FunctionBuilder("f32_bits")
  for bits in f32_bits {
    f32_builder.fconst_f32(Float::reinterpret_from_uint(bits)) |> ignore
  }
  for index, bits in f32_bits {
    inspect(
      f32_builder.current_block().instructions[index].opcode ==
      Scalar(FloatConst32(bits)),
      content="true",
    )
  }
  let f64_bits : Array[UInt64] = [
    0UL, 0x8000000000000000UL, 0x7FF8000000000001UL,
  ]
  let f64_builder = FunctionBuilder::FunctionBuilder("f64_bits")
  for bits in f64_bits {
    f64_builder.fconst_f64(bits.reinterpret_as_double()) |> ignore
  }
  for index, bits in f64_bits {
    inspect(
      f64_builder.current_block().instructions[index].opcode ==
      Scalar(FloatConst64(bits)),
      content="true",
    )
  }
}

///|
test "F32 instruction identity uses explicit bit patterns" {
  let func = Function::new_empty("f32_identity")
  let make = bits => {
    func.new_inst(Scalar(FloatConst32(bits)), [], [func.new_value(F32)])
  }
  let positive_zero = make(0U)
  let negative_zero = make(0x80000000U)
  let nan = make(0x7FC00001U)
  let same_nan = make(0x7FC00001U)
  let other_nan = make(0x7FC00002U)
  inspect(positive_zero == negative_zero, content="false")
  inspect(nan == same_nan, content="true")
  inspect(nan == other_nan, content="false")
  inspect(nan.hash() == same_nan.hash(), content="true")
}

///|
test "verify binds floating constant payload width to result type" {
  let narrow = Function::new_empty("narrow_as_wide")
  let narrow_result = narrow.new_value(F64)
  let narrow_entry = narrow.new_block([])
  narrow_entry.append_inst(
    narrow.new_inst(Scalar(FloatConst32(0U)), [], [narrow_result]),
  )
  narrow_entry.set_terminator(Return([]))
  try narrow.verify() catch {
    TypeMismatch(_) => ()
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected fconst32 result type mismatch")
  }
  let wide = Function::new_empty("wide_as_narrow")
  let wide_result = wide.new_value(F32)
  let wide_entry = wide.new_block([])
  wide_entry.append_inst(
    wide.new_inst(Scalar(FloatConst64(0UL)), [], [wide_result]),
  )
  wide_entry.set_terminator(Return([]))
  try wide.verify() catch {
    TypeMismatch(_) => ()
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected fconst64 result type mismatch")
  }
}
