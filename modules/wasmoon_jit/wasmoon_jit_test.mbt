///|
test "resolve runtime helper relocations into linked code" {
  let func = @machv.Function::new("caller")
  let entry = func.new_block()
  entry.append(func.new_inst(Call("wasmoon.runtime.helper")))
  let object = try! @machv_emit.emit_function_for_target(func, X64)
  let resolver = RuntimeSymbolResolver::new()
  resolver.add_symbol("wasmoon.runtime.helper", 4096L)
  let linked = try! link_code_object(object, resolver)
  inspect(linked.code.length(), content="5")
  inspect(linked.runtime_relocations.length(), content="1")
  inspect(linked.block_fixups.length(), content="0")
}

///|
test "resolve legacy runtime fixup ids in wasmoon_jit" {
  inspect(resolve_runtime_func_fixup_idx(-20000) is Some(_), content="true")
  inspect(resolve_runtime_func_fixup_idx(-21013) is Some(_), content="true")
  inspect(resolve_runtime_func_fixup_idx(-22011) is Some(_), content="true")
  inspect(resolve_runtime_func_fixup_idx(-1) is None, content="true")
}

///|
test "wrap linked code as cwasm artifact" {
  let func = @machv.Function::new("caller")
  let entry = func.new_block()
  entry.append(func.new_inst(Return))
  let object = try! @machv_emit.emit_function_for_target(func, X64)
  let resolver = RuntimeSymbolResolver::new()
  let linked = try! link_code_object(object, resolver)
  let artifact = CwasmArtifact::from_linked_code(linked, 7)
  inspect(artifact.functions.length(), content="1")
  inspect(artifact.manifest().length(), content="5")
}

///|
test "plan Wasmoon JIT integration without leaking into machv_emit" {
  let milk = @milkir.Function::new("entry", @milkir.Signature::new([], []))
  let mach = @machv.Function::new("entry")
  let entry = mach.new_block()
  entry.append(mach.new_inst(Return))
  let plan = try! plan_integration_for_target(milk, mach, X64)
  inspect(plan.entry_symbol, content="entry")
  debug_inspect(plan.target, content="X64")
  inspect(plan.native_glue.length(), content="6")
  inspect(plan.object.debug_entries.length(), content="1")
  inspect(plan.object.code.length(), content="1")
}

///|
test "plan MilkIR through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("add64", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let sum = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Iadd, [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let plan = try! plan_milkir_integration_for_target(milk, X64)
  debug_inspect(plan.target, content="X64")
  inspect(plan.entry_symbol, content="add64")
  debug_inspect(plan.object.code, content="[72, 137, 240, 72, 1, 248, 195]")
  inspect(plan.object.debug_entries.length(), content="2")
}

///|
test "plan MilkIR floating point through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([F64, F64], [F64])
  let milk = @milkir.Function::new("fadd64", signature)
  let lhs = milk.new_value(F64)
  let rhs = milk.new_value(F64)
  let sum = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fadd, [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let plan = try! plan_milkir_integration_for_target(milk, X64)
  debug_inspect(plan.target, content="X64")
  inspect(plan.entry_symbol, content="fadd64")
  debug_inspect(
    plan.object.code,
    content="[242, 15, 16, 208, 242, 15, 88, 209, 195]",
  )
  inspect(plan.object.debug_entries.length(), content="2")
}

///|
test "plan MilkIR floating abs and neg through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([F64], [F64])
  let milk = @milkir.Function::new("fabs_fneg64", signature)
  let input = milk.new_value(F64)
  let neg = milk.new_value(F64)
  let abs = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fneg, [input], [neg]))
  entry.append_inst(milk.new_inst(Fabs, [neg], [abs]))
  entry.set_terminator(Return([abs]))
  let plan = try! plan_milkir_integration_for_target(milk, X64)
  let mut has_abs_mask = false
  let mut has_neg_mask = false
  for byte in plan.object.code {
    if byte == 0x54 {
      has_abs_mask = true
    }
    if byte == 0x57 {
      has_neg_mask = true
    }
  }
  inspect(has_abs_mask, content="true")
  inspect(has_neg_mask, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR f64 const through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([], [F64])
  let milk = @milkir.Function::new("fconst64_x64", signature)
  let output = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fconst(1.5), [], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_movq_to_xmm = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0x6e {
      has_movq_to_xmm = true
    }
  }
  inspect(has_movq_to_xmm, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR f32 const through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([], [F32])
  let milk = @milkir.Function::new("fconst32_aarch64", signature)
  let output = milk.new_value(F32)
  let entry = milk.new_block([])
  let bits = (1.25 : Float).reinterpret_as_int().to_int64()
  entry.append_inst(
    milk.new_inst(Fconst(bits.reinterpret_as_double()), [], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_fmov_w_to_s = false
  for i in 0..<(plan.object.code.length() - 3) {
    if plan.object.code[i + 2] == 0x27 && plan.object.code[i + 3] == 0x1e {
      has_fmov_w_to_s = true
    }
  }
  inspect(has_fmov_w_to_s, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR float promote through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([F32], [F64])
  let milk = @milkir.Function::new("fpromote_x64", signature)
  let input = milk.new_value(F32)
  let output = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fpromote, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_cvtss2sd = false
  for i in 0..<(plan.object.code.length() - 2) {
    if plan.object.code[i] == 0xf3 &&
      plan.object.code[i + 1] == 0x0f &&
      plan.object.code[i + 2] == 0x5a {
      has_cvtss2sd = true
    }
  }
  inspect(has_cvtss2sd, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR float demote through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([F64], [F32])
  let milk = @milkir.Function::new("fdemote_aarch64", signature)
  let input = milk.new_value(F64)
  let output = milk.new_value(F32)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fdemote, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_fcvt_s_d = false
  for i in 0..<(plan.object.code.length() - 3) {
    if (plan.object.code[i + 1] & 0x40) == 0x40 &&
      plan.object.code[i + 2] == 0x62 &&
      plan.object.code[i + 3] == 0x1e {
      has_fcvt_s_d = true
    }
  }
  inspect(has_fcvt_s_d, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR float ceil through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([F32], [F32])
  let milk = @milkir.Function::new("fceil_x64", signature)
  let input = milk.new_value(F32)
  let output = milk.new_value(F32)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fceil, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_roundss_ceil = false
  for i in 0..<(plan.object.code.length() - 4) {
    if plan.object.code[i] == 0x0f &&
      plan.object.code[i + 1] == 0x3a &&
      plan.object.code[i + 2] == 0x0a &&
      plan.object.code[i + 4] == 0x02 {
      has_roundss_ceil = true
    }
  }
  inspect(has_roundss_ceil, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR float nearest through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([F64], [F64])
  let milk = @milkir.Function::new("fnearest_aarch64", signature)
  let input = milk.new_value(F64)
  let output = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fnearest, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_frintn_d = false
  for i in 0..<(plan.object.code.length() - 3) {
    if (plan.object.code[i + 1] & 0x40) == 0x40 &&
      plan.object.code[i + 2] == 0x64 &&
      plan.object.code[i + 3] == 0x1e {
      has_frintn_d = true
    }
  }
  inspect(has_frintn_d, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR float compare through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([F64, F64], [I32])
  let milk = @milkir.Function::new("fcmp_eq_x64", signature)
  let lhs = milk.new_value(F64)
  let rhs = milk.new_value(F64)
  let output = milk.new_value(I32)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fcmp(Eq), [lhs, rhs], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_ucomisd = false
  let mut has_setnp = false
  for i in 0..<(plan.object.code.length() - 2) {
    if plan.object.code[i] == 0x66 &&
      plan.object.code[i + 1] == 0x0f &&
      plan.object.code[i + 2] == 0x2e {
      has_ucomisd = true
    }
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0x9b {
      has_setnp = true
    }
  }
  inspect(has_ucomisd, content="true")
  inspect(has_setnp, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR float compare through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([F32, F32], [I32])
  let milk = @milkir.Function::new("fcmp_lt_aarch64", signature)
  let lhs = milk.new_value(F32)
  let rhs = milk.new_value(F32)
  let output = milk.new_value(I32)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fcmp(Lt), [lhs, rhs], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_fcmp_s = false
  let mut has_cset_mi = false
  for i in 0..<(plan.object.code.length() - 3) {
    if (plan.object.code[i + 2] & 0xe0) == 0x20 &&
      plan.object.code[i + 3] == 0x1e {
      has_fcmp_s = true
    }
    if (plan.object.code[i + 1] & 0xf0) == 0xa0 &&
      plan.object.code[i + 2] == 0x9f &&
      plan.object.code[i + 3] == 0x9a {
      has_cset_mi = true
    }
  }
  inspect(has_fcmp_s, content="true")
  inspect(has_cset_mi, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "emit MachV regalloc stack spills through reusable x64 pipeline" {
  let func = @machv.Function::new("spilled_x64")
  let entry = func.new_block()
  let values : Array[@machv.VReg] = []
  for i in 0..<5 {
    let value = func.new_vreg(Int)
    values.push(value)
    let inst = func.new_inst(IntConst(i.to_int64()))
    inst.add_operand(@machv.Operand::def(Virtual(value)))
    entry.append(inst)
  }
  let sum = func.new_vreg(Int)
  let add = func.new_inst(IntAdd)
  add.add_operand(@machv.Operand::use_reg(Virtual(values[0])))
  add.add_operand(@machv.Operand::use_reg(Virtual(values[4])))
  add.add_operand(@machv.Operand::def(Virtual(sum)))
  entry.append(add)
  entry.set_terminator(TermReturn([]))
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let result = @machv_regalloc.allocate_and_apply(func, [p0, p1])
  let object = try! @machv_emit.emit_function_for_target(func, X64)
  let mut has_stack_load = false
  let mut has_stack_store = false
  for i in 0..<(object.code.length() - 4) {
    if object.code[i] == 0x48 &&
      object.code[i + 1] == 0x8b &&
      object.code[i + 3] == 0x24 {
      has_stack_load = true
    }
    if object.code[i] == 0x48 &&
      object.code[i + 1] == 0x89 &&
      object.code[i + 3] == 0x24 {
      has_stack_store = true
    }
  }
  inspect(result.spill_slots.length() > 0, content="true")
  inspect(has_stack_load, content="true")
  inspect(has_stack_store, content="true")
  inspect(object.code[object.code.length() - 1], content="195")
}

///|
test "plan MilkIR bitcast through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64], [F64])
  let milk = @milkir.Function::new("bitcast_i64_f64", signature)
  let input = milk.new_value(I64)
  let output = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Bitcast, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_movq_to_xmm = false
  for i in 0..<(plan.object.code.length() - 2) {
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0x6e {
      has_movq_to_xmm = true
    }
  }
  inspect(has_movq_to_xmm, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR bitcast through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([F64], [I64])
  let milk = @milkir.Function::new("bitcast_f64_i64", signature)
  let input = milk.new_value(F64)
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Bitcast, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_fmov_to_gpr = false
  for i in 0..<(plan.object.code.length() - 3) {
    if plan.object.code[i + 2] == 0x66 && plan.object.code[i + 3] == 0x9e {
      has_fmov_to_gpr = true
    }
  }
  inspect(has_fmov_to_gpr, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR sign-extension through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64], [I64])
  let milk = @milkir.Function::new("sext8_x64", signature)
  let input = milk.new_value(I64)
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Sextend8, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_movsx = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0xbe {
      has_movsx = true
    }
  }
  inspect(has_movsx, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR sign-extension through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64], [I64])
  let milk = @milkir.Function::new("sext32_aarch64", signature)
  let input = milk.new_value(I64)
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Sextend32, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_sxtw = false
  for i in 0..<(plan.object.code.length() - 3) {
    if (plan.object.code[i + 1] & 0x7c) == 0x7c &&
      plan.object.code[i + 2] == 0x40 &&
      plan.object.code[i + 3] == 0x93 {
      has_sxtw = true
    }
  }
  inspect(has_sxtw, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR unsigned extend through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([I32], [I64])
  let milk = @milkir.Function::new("uextend_x64", signature)
  let input = milk.new_value(I32)
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Uextend, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_mov32 = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0x89 {
      has_mov32 = true
    }
  }
  inspect(has_mov32, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR integer reduce through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64], [I32])
  let milk = @milkir.Function::new("ireduce_aarch64", signature)
  let input = milk.new_value(I64)
  let output = milk.new_value(I32)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Ireduce, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_mov_w = false
  for i in 0..<(plan.object.code.length() - 3) {
    if plan.object.code[i + 3] == 0x2a {
      has_mov_w = true
    }
  }
  inspect(has_mov_w, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR integer select through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([I32, I64, I64], [I64])
  let milk = @milkir.Function::new("select_x64", signature)
  let cond = milk.new_value(I32)
  let true_value = milk.new_value(I64)
  let false_value = milk.new_value(I64)
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Select, [cond, true_value, false_value], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_cmovne = false
  for i in 0..<(plan.object.code.length() - 2) {
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0x45 {
      has_cmovne = true
    }
  }
  inspect(has_cmovne, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR integer select through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([I32, I64, I64], [I64])
  let milk = @milkir.Function::new("select_aarch64", signature)
  let cond = milk.new_value(I32)
  let true_value = milk.new_value(I64)
  let false_value = milk.new_value(I64)
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Select, [cond, true_value, false_value], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_csel = false
  for i in 0..<(plan.object.code.length() - 3) {
    if plan.object.code[i + 3] == 0x9a &&
      (plan.object.code[i + 2] & 0x80) == 0x80 {
      has_csel = true
    }
  }
  inspect(has_csel, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR signed integer division through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("sdiv64", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let quotient = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Sdiv, [lhs, rhs], [quotient]))
  entry.set_terminator(Return([quotient]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_cqo = false
  let mut has_div_opcode = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0x48 && plan.object.code[i + 1] == 0x99 {
      has_cqo = true
    }
  }
  for byte in plan.object.code {
    if byte == 0xf7 {
      has_div_opcode = true
    }
  }
  inspect(has_cqo, content="true")
  inspect(has_div_opcode, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR signed integer remainder through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("srem64", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let rem = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Srem, [lhs, rhs], [rem]))
  entry.set_terminator(Return([rem]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_cqo = false
  let mut has_div_opcode = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0x48 && plan.object.code[i + 1] == 0x99 {
      has_cqo = true
    }
  }
  for byte in plan.object.code {
    if byte == 0xf7 {
      has_div_opcode = true
    }
  }
  inspect(has_cqo, content="true")
  inspect(has_div_opcode, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR signed multiply-high through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("smulh64", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let high = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Smulh, [lhs, rhs], [high]))
  entry.set_terminator(Return([high]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_mul_opcode = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0xf7 && (plan.object.code[i + 1] & 0x38) == 0x28 {
      has_mul_opcode = true
    }
  }
  inspect(has_mul_opcode, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR integer not through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64], [I64])
  let milk = @milkir.Function::new("bnot64", signature)
  let input = milk.new_value(I64)
  let inverted = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Bnot, [input], [inverted]))
  entry.set_terminator(Return([inverted]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_not_opcode = false
  for byte in plan.object.code {
    if byte == 0xf7 {
      has_not_opcode = true
    }
  }
  inspect(has_not_opcode, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR integer compare through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I32])
  let milk = @milkir.Function::new("icmp_slt64", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let is_less = milk.new_value(I32)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Icmp(Slt), [lhs, rhs], [is_less]))
  entry.set_terminator(Return([is_less]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_setcc = false
  let mut has_movzx = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0x9c {
      has_setcc = true
    }
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0xb6 {
      has_movzx = true
    }
  }
  inspect(has_setcc, content="true")
  inspect(has_movzx, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR integer shift through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("shl64", signature)
  let value = milk.new_value(I64)
  let count = milk.new_value(I64)
  let shifted = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Ishl, [value, count], [shifted]))
  entry.set_terminator(Return([shifted]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_shift_cl = false
  for byte in plan.object.code {
    if byte == 0xd3 {
      has_shift_cl = true
    }
  }
  inspect(has_shift_cl, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR integer rotate through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("rotr64", signature)
  let value = milk.new_value(I64)
  let count = milk.new_value(I64)
  let rotated = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Rotr, [value, count], [rotated]))
  entry.set_terminator(Return([rotated]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_rotate_cl = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0xd3 && (plan.object.code[i + 1] & 0x38) == 0x08 {
      has_rotate_cl = true
    }
  }
  inspect(has_rotate_cl, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR integer ctz through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64], [I64])
  let milk = @milkir.Function::new("ctz64", signature)
  let value = milk.new_value(I64)
  let trailing = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Ctz, [value], [trailing]))
  entry.set_terminator(Return([trailing]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_rbit = false
  let mut has_clz = false
  for i in 0..<(plan.object.code.length() - 3) {
    if plan.object.code[i + 2] == 0xc0 && plan.object.code[i + 3] == 0xda {
      if (plan.object.code[i + 1] & 0x10) == 0 {
        has_rbit = true
      } else {
        has_clz = true
      }
    }
  }
  inspect(has_rbit, content="true")
  inspect(has_clz, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR unsigned multiply-high through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("umulh64", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let high = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Umulh, [lhs, rhs], [high]))
  entry.set_terminator(Return([high]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_umulh = false
  for i in 0..<(plan.object.code.length() - 3) {
    if (plan.object.code[i + 1] & 0x7c) == 0x7c &&
      (plan.object.code[i + 2] & 0xc0) == 0xc0 &&
      plan.object.code[i + 3] == 0x9b {
      has_umulh = true
    }
  }
  inspect(has_umulh, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR rotate-right through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("rotr64_aarch64", signature)
  let value = milk.new_value(I64)
  let count = milk.new_value(I64)
  let rotated = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Rotr, [value, count], [rotated]))
  entry.set_terminator(Return([rotated]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_rorv = false
  for i in 0..<(plan.object.code.length() - 3) {
    if (plan.object.code[i + 1] & 0x2c) == 0x2c &&
      (plan.object.code[i + 2] & 0xc0) == 0xc0 &&
      plan.object.code[i + 3] == 0x9a {
      has_rorv = true
    }
  }
  inspect(has_rorv, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR rotate-left through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("rotl64_aarch64", signature)
  let value = milk.new_value(I64)
  let count = milk.new_value(I64)
  let rotated = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Rotl, [value, count], [rotated]))
  entry.set_terminator(Return([rotated]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_rorv = false
  for i in 0..<(plan.object.code.length() - 3) {
    if (plan.object.code[i + 1] & 0x2c) == 0x2c &&
      (plan.object.code[i + 2] & 0xc0) == 0xc0 &&
      plan.object.code[i + 3] == 0x9a {
      has_rorv = true
    }
  }
  inspect(has_rorv, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "wrap reusable JIT plan as cwasm artifact" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("add64_artifact", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let sum = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Iadd, [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let plan = try! plan_milkir_integration_for_target(milk, X64)
  let artifact = try! CwasmArtifact::from_jit_plan(
    plan,
    RuntimeSymbolResolver::new(),
    3,
  )
  inspect(artifact.functions.length(), content="1")
  inspect(artifact.functions[0].function_index, content="3")
  inspect(artifact.code.length() > 0, content="true")
  inspect(artifact.debug_entries.length(), content="2")
}

///|
test "reference encoding helpers roundtrip JIT values" {
  inspect(is_null_ref(encode_null_ref()), content="true")
  debug_inspect(decode_funcref_idx(encode_funcref_idx(7)), content="Some(7)")
  let tagged = tag_funcref_ptr(0x1000L)
  inspect(is_funcref_ptr(tagged), content="true")
  inspect(untag_funcref_ptr(tagged), content="4096")
  debug_inspect(decode_externref(encode_externref(11)), content="Some(11)")
  debug_inspect(decode_gc_heap_ref(encode_gc_heap_ref(3)), content="Some(3)")
  debug_inspect(decode_gc_heap_ref(encode_null_ref()), content="None")
}
