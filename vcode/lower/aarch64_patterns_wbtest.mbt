// Tests for AArch64-specific instruction selection patterns

///|
test "aarch64: add with shifted operand" {
  // Build IR: fn(a: i32, b: i32) -> i32 { a + (b << 2) }
  let builder = @ir.IRBuilder::new("add_shifted_test")
  let a = builder.add_param(@ir.Type::I32)
  let b = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let shift_amount = builder.iconst_i32(2)
  let shifted = builder.ishl(b, shift_amount)
  let result = builder.iadd(a, shifted)
  builder.return_([result])

  // Get the AArch64 rules and try matching
  let rules = get_aarch64_rules()
  let ir_func = builder.get_function()
  let ctx = LoweringContext::new(ir_func, @abi.ABISettings::default(), -1)

  // Find the add instruction
  let block = ir_func.blocks[0]
  let add_inst = block.instructions[2] // iadd is the 3rd instruction

  // Try matching the aarch64_add_shifted pattern
  let mut matched = false
  for rule in rules {
    if rule.name == "aarch64_add_shifted" {
      let match_result = match_pattern(rule.pattern, add_inst, ctx)
      if match_result is Some(_) {
        matched = true
      }
    }
  }
  inspect(matched, content="true")
}

///|
test "aarch64: madd pattern" {
  // Build IR: fn(a: i32, b: i32, c: i32) -> i32 { a + b * c }
  let builder = @ir.IRBuilder::new("madd_test")
  let a = builder.add_param(@ir.Type::I32)
  let b = builder.add_param(@ir.Type::I32)
  let c = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let mul_result = builder.imul(b, c)
  let result = builder.iadd(a, mul_result)
  builder.return_([result])

  // Get the AArch64 rules
  let rules = get_aarch64_rules()
  let ir_func = builder.get_function()
  let ctx = LoweringContext::new(ir_func, @abi.ABISettings::default(), -1)

  // Find the add instruction
  let block = ir_func.blocks[0]
  let add_inst = block.instructions[1] // iadd is the 2nd instruction

  // Try to match the madd pattern
  for rule in rules {
    if rule.name == "aarch64_madd" {
      let match_result = match_pattern(rule.pattern, add_inst, ctx)
      if match_result is Some(result) {
        // The pattern matched - verify we captured the right values
        inspect(result.values.length() >= 3, content="true")
      }
    }
  }
}

///|
test "aarch64: msub pattern" {
  // Build IR: fn(a: i32, b: i32, c: i32) -> i32 { a - b * c }
  let builder = @ir.IRBuilder::new("msub_test")
  let a = builder.add_param(@ir.Type::I32)
  let b = builder.add_param(@ir.Type::I32)
  let c = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let mul_result = builder.imul(b, c)
  let result = builder.isub(a, mul_result)
  builder.return_([result])

  // Get the AArch64 rules
  let rules = get_aarch64_rules()
  let ir_func = builder.get_function()
  let ctx = LoweringContext::new(ir_func, @abi.ABISettings::default(), -1)

  // Find the sub instruction
  let block = ir_func.blocks[0]
  let sub_inst = block.instructions[1] // isub is the 2nd instruction

  // Try to match the msub pattern
  for rule in rules {
    if rule.name == "aarch64_msub" {
      let match_result = match_pattern(rule.pattern, sub_inst, ctx)
      if match_result is Some(result) {
        inspect(result.values.length() >= 3, content="true")
      }
    }
  }
}

///|
test "aarch64: mneg pattern" {
  // Build IR: fn(a: i32, b: i32) -> i32 { -(a * b) } => { 0 - (a * b) }
  let builder = @ir.IRBuilder::new("mneg_test")
  let a = builder.add_param(@ir.Type::I32)
  let b = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let zero = builder.iconst_i32(0)
  let mul_result = builder.imul(a, b)
  let result = builder.isub(zero, mul_result)
  builder.return_([result])

  // Get the AArch64 rules
  let rules = get_aarch64_rules()
  let ir_func = builder.get_function()
  let ctx = LoweringContext::new(ir_func, @abi.ABISettings::default(), -1)

  // Find the sub instruction
  let block = ir_func.blocks[0]
  let sub_inst = block.instructions[2] // isub is the 3rd instruction

  // Try to match the mneg pattern
  for rule in rules {
    if rule.name == "aarch64_mneg" {
      let match_result = match_pattern(rule.pattern, sub_inst, ctx)
      if match_result is Some(result) {
        inspect(result.values.length() >= 2, content="true")
      }
    }
  }
}

///|
test "is_valid_add_imm: simple 12-bit immediate" {
  // 12-bit immediates (0-4095) should be valid
  inspect(is_valid_add_imm(0L), content="true")
  inspect(is_valid_add_imm(1L), content="true")
  inspect(is_valid_add_imm(4095L), content="true")
  inspect(is_valid_add_imm(4096L), content="true") // shifted form: 0x1000
  inspect(is_valid_add_imm(0xFFF000L), content="true") // max shifted form
}

///|
test "is_valid_add_imm: invalid immediates" {
  // Values that don't fit either encoding
  inspect(is_valid_add_imm(-1L), content="false")
  inspect(is_valid_add_imm(4097L), content="false") // 0x1001 - has bits in both regions
  inspect(is_valid_add_imm(0xFFFFFF00L), content="false") // too large
}

///|
test "is_valid_logical_imm: valid patterns" {
  // Simple consecutive ones (64-bit element)
  inspect(is_valid_logical_imm(0x1L), content="true") // single bit
  inspect(is_valid_logical_imm(0x3L), content="true") // 2 consecutive bits
  inspect(is_valid_logical_imm(0xFFL), content="true") // 8 consecutive bits
  inspect(is_valid_logical_imm(0xFF00L), content="true") // rotated pattern
  // Repeating patterns (smaller elements)
  inspect(is_valid_logical_imm(0x5555555555555555L), content="true") // 0101... (2-bit element)
  inspect(is_valid_logical_imm(0xAAAAAAAAAAAAAAAAL), content="true") // 1010... (2-bit element)
  inspect(is_valid_logical_imm(0x0F0F0F0F0F0F0F0FL), content="true") // 8-bit element
  inspect(is_valid_logical_imm(0x00FF00FF00FF00FFL), content="true") // 16-bit element
}

///|
test "is_valid_logical_imm: invalid patterns" {
  // All zeros and all ones are invalid
  inspect(is_valid_logical_imm(0L), content="false")
  inspect(is_valid_logical_imm(-1L), content="false")
  // Non-repeating patterns
  inspect(is_valid_logical_imm(0x123456789ABCDEF0L), content="false")
}

///|
test "is_consecutive_ones: valid patterns" {
  // Values with consecutive 1s
  inspect(is_consecutive_ones(0x1L), content="true") // 0001
  inspect(is_consecutive_ones(0x3L), content="true") // 0011
  inspect(is_consecutive_ones(0x7L), content="true") // 0111
  inspect(is_consecutive_ones(0xFL), content="true") // 1111
  inspect(is_consecutive_ones(0xFFL), content="true") // 11111111
  inspect(is_consecutive_ones(0x6L), content="true") // 0110
  inspect(is_consecutive_ones(0xCL), content="true") // 1100
}

///|
test "is_consecutive_ones: invalid patterns" {
  // Values without consecutive 1s or edge cases
  inspect(is_consecutive_ones(0L), content="false") // no bits
  inspect(is_consecutive_ones(0x5L), content="false") // 0101 - not consecutive
  inspect(is_consecutive_ones(0x9L), content="false") // 1001 - not consecutive
  inspect(is_consecutive_ones(0xAL), content="false") // 1010 - not consecutive
}

///|
test "apply_aarch64_rule: add_shifted" {
  // Test that the rule application produces correct result
  let result : MatchResult = {
    values: [],
    int_consts: [3L], // shift by 3
    float_consts: [],
  }
  // Create a minimal function to get a context
  let builder = @ir.IRBuilder::new("test")
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let c = builder.iconst_i32(0)
  builder.return_([c])
  let ir_func = builder.get_function()
  let ctx = LoweringContext::new(ir_func, @abi.ABISettings::default(), -1)
  let test_inst = ir_func.blocks[0].instructions[0]
  let apply_result = apply_aarch64_rule(
    "aarch64_add_shifted", result, test_inst, ctx,
  )
  match apply_result {
    AArch64RewriteResult::AddShifted(src1, src2, shift) => {
      inspect(src1, content="0")
      inspect(src2, content="1")
      inspect(shift, content="3")
    }
    _ => inspect("unexpected", content="AddShifted")
  }
}

///|
test "apply_aarch64_rule: madd" {
  let result : MatchResult = { values: [], int_consts: [], float_consts: [] }
  let builder = @ir.IRBuilder::new("test")
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let c = builder.iconst_i32(0)
  builder.return_([c])
  let ir_func = builder.get_function()
  let ctx = LoweringContext::new(ir_func, @abi.ABISettings::default(), -1)
  let test_inst = ir_func.blocks[0].instructions[0]
  let apply_result = apply_aarch64_rule("aarch64_madd", result, test_inst, ctx)
  match apply_result {
    AArch64RewriteResult::Madd(acc, src1, src2) => {
      inspect(acc, content="0")
      inspect(src1, content="1")
      inspect(src2, content="2")
    }
    _ => inspect("unexpected", content="Madd")
  }
}
