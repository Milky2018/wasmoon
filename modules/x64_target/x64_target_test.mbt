///|
test "x64 target owns ABI policy" {
  let abi = abi_policy()
  inspect(abi.pointer_size, content="8")
  inspect(abi.stack_alignment, content="16")
  inspect(abi.int_argument_regs.length(), content="6")
  inspect(abi.float_argument_regs.length(), content="8")
}

///|
test "x64 target owns Wasm indirect-call ABI policy" {
  inspect(wasm_vmctx_arg_preg().index, content="7")
  inspect(wasm_user_arg_gprs().length(), content="5")
  inspect(wasm_ret_gprs().length(), content="8")
}

///|
fn return_def_preg_index(inst : @machv.Instruction) -> Int {
  if inst.operands.length() > 1 && inst.operands[1].reg is Physical(preg) {
    preg.index
  } else {
    -1
  }
}

///|
test "x64 lowers Wasm function body return ABI separately from SystemV" {
  let func = @milkir.Function::new("wasm_body", @milkir.Signature::new([], []))
  func.add_param(Ptr) |> ignore
  let lhs = func.add_param(I64)
  let rhs = func.add_param(I64)
  func.add_result(I64)
  func.add_result(I64)
  let entry = func.new_block([])
  entry.set_terminator(Return([lhs, rhs]))
  let sysv = lower_function(func)
  let wasm = lower_wasm_body_function(func)
  guard wasm.param_pregs[0] is Some(vmctx) else { fail("missing vmctx") }
  guard wasm.param_pregs[1] is Some(arg0) else { fail("missing arg0") }
  inspect(vmctx.index, content="7")
  inspect(arg0.index, content="6")
  inspect(return_def_preg_index(sysv.blocks[0].instructions[1]), content="3")
  inspect(return_def_preg_index(wasm.blocks[0].instructions[1]), content="2")
}

///|
test "x64 records stack parameters and return area ABI locations" {
  let func = @milkir.Function::new_empty("abi_locations")
  for _ in 0..<7 {
    func.add_param(I64) |> ignore
  }
  for _ in 0..<3 {
    func.add_result(I64)
  }
  let entry = func.new_block([])
  entry.set_terminator(Return([]))
  let lowered = lower_function(func)
  inspect(lowered.param_locations.length(), content="7")
  guard lowered.param_locations[6] is Stack(offset~, size~, align~) else {
    fail("expected seventh SystemV integer parameter on stack")
  }
  inspect(offset, content="8")
  inspect(size, content="8")
  inspect(align, content="8")
  inspect(lowered.param_pregs[6] is None, content="true")
  inspect(lowered.result_locations.length(), content="3")
  guard lowered.result_locations[2]
    is ReturnArea(offset=ret_offset, size=ret_size, align=ret_align) else {
    fail("expected third SystemV integer result in return area")
  }
  inspect(ret_offset, content="0")
  inspect(ret_size, content="8")
  inspect(ret_align, content="8")
  guard lowered.return_area is Some(area) else { fail("missing return area") }
  inspect(area.size, content="8")
  inspect(area.align, content="16")
}

///|
test "x64 lowers Wasm return-area stores through ExtraResultsPtr" {
  let func = @milkir.Function::new_empty("wasm_return_area_store")
  let values : Array[@milkir.Value] = []
  for _ in 0..<9 {
    let value = func.new_value(I64)
    values.push(value)
    func.add_result(I64)
  }
  let entry = func.new_block([])
  entry.set_terminator(Return(values))
  let lowered = lower_wasm_body_function(func)
  let mut has_store = false
  for inst in lowered.blocks[0].instructions {
    if inst.opcode == StorePtr(MemI64, 0) &&
      inst.operands.length() >= 2 &&
      inst.operands[0].reg == Physical({ index: 12, class: Int }) {
      has_store = true
    }
  }
  inspect(has_store, content="true")
}

///|
test "x64 target owns SystemV machine environment policy" {
  inspect(call_clobbered_gprs().length(), content="9")
  inspect(call_clobbered_fprs().length(), content="16")
  inspect(int_reg_index(Vmctx), content="15")
  let env = build_machine_env(
    settings={ enable_pinned_reg: true },
    reserve_mem0_desc=true,
    reserve_func_table=true,
    reserve_extra_results_ptr=true,
  )
  inspect(env.preferred_int.length(), content="7")
  inspect(env.nonpreferred_int.length(), content="1")
  inspect(env.callee_saved_int.length(), content="1")
  inspect(env.scratch_int.length(), content="2")
  inspect(env.scratch_float.length(), content="2")
}

///|
test "x64 allocatable regs include floating point registers" {
  let regs = allocatable_regs()
  inspect(regs.any(fn(r) { r.class == Float32 }), content="true")
  inspect(regs.any(fn(r) { r.class == Float64 }), content="true")
  inspect(regs.any(fn(r) { r.class == Vector }), content="true")
}

///|
test "x64 lowers MilkIR arithmetic into MachV" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let func = @milkir.Function::new("add64", signature)
  let lhs = func.new_value(I64)
  let rhs = func.new_value(I64)
  let sum = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Iadd, [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let lowered = lower_function(func)
  inspect(lowered.blocks.length(), content="1")
  inspect(lowered.blocks[0].instructions.length(), content="2")
  inspect(lowered.blocks[0].instructions[0].opcode == IntAdd, content="true")
  inspect(lowered.blocks[0].terminator is Some(TermReturn(_)), content="true")
  inspect(lowered.verify(), content="()")
}

///|
test "x64 preserves MilkIR stack slots for StackAddr lowering" {
  let func = @milkir.Function::new_empty("stack_addr")
  let slot = func.new_stack_slot(16, 16)
  let ptr = func.new_value(Ptr)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(StackAddr(slot), [], [ptr]))
  entry.set_terminator(Return([ptr]))
  let lowered = lower_function(func)
  inspect(lowered.stack_slots.length(), content="1")
  inspect(lowered.stack_slots[0].size, content="16")
  inspect(lowered.stack_slots[0].align, content="16")
  inspect(
    lowered.blocks[0].instructions[0].opcode == StackAddr(0),
    content="true",
  )
}

///|
test "x64 lowers popcnt through generic MachV arithmetic sequence" {
  let func = @milkir.Function::new_empty("popcnt64")
  let value = func.new_value(I64)
  let count = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Popcnt, [value], [count]))
  entry.set_terminator(Return([count]))
  let lowered = lower_function(func)
  let mut has_popcnt = false
  let mut has_mul = false
  let mut has_rcx_shift = false
  for inst in lowered.blocks[0].instructions {
    if inst.opcode == IntPopcnt {
      has_popcnt = true
    }
    if inst.opcode == IntMul {
      has_mul = true
    }
    if inst.opcode == IntShr(false) {
      for constraint in inst.constraints {
        if constraint.allowed_regs.length() == 1 &&
          constraint.allowed_regs[0] == { index: 1, class: Int } {
          has_rcx_shift = true
        }
      }
    }
  }
  inspect(has_popcnt, content="false")
  inspect(has_mul, content="true")
  inspect(has_rcx_shift, content="true")
}

///|
test "x64 lowers bitcount ops through generic MachV arithmetic sequence" {
  let func = @milkir.Function::new_empty("bitcount64")
  let value = func.new_value(I64)
  let leading = func.new_value(I64)
  let trailing = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Clz, [value], [leading]))
  entry.append_inst(func.new_inst(Ctz, [value], [trailing]))
  entry.set_terminator(Return([leading, trailing]))
  let lowered = lower_function(func)
  let mut has_clz = false
  let mut has_ctz = false
  let mut has_mul = false
  for inst in lowered.blocks[0].instructions {
    if inst.opcode == IntClz {
      has_clz = true
    }
    if inst.opcode == IntCtz {
      has_ctz = true
    }
    if inst.opcode == IntMul {
      has_mul = true
    }
  }
  inspect(has_clz, content="false")
  inspect(has_ctz, content="false")
  inspect(has_mul, content="true")
  inspect(lowered.verify(), content="()")
}

///|
test "x64 lowers floating point select through integer MachV select" {
  let signature = @milkir.Signature::new([I32, F64, F64], [F64])
  let func = @milkir.Function::new("select_f64", signature)
  let cond = func.new_value(I32)
  let true_value = func.new_value(F64)
  let false_value = func.new_value(F64)
  let output = func.new_value(F64)
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(Select, [cond, true_value, false_value], [output]),
  )
  entry.set_terminator(Return([output]))
  let lowered = lower_function(func)
  inspect(lowered.blocks[0].instructions.length(), content="5")
  inspect(lowered.blocks[0].instructions[0].opcode == Bitcast, content="true")
  inspect(lowered.blocks[0].instructions[1].opcode == Bitcast, content="true")
  let select = lowered.blocks[0].instructions[2]
  inspect(select.opcode == Select, content="true")
  inspect(select.operands.length(), content="4")
  let mut selects_int_bits = false
  if select.operands[3].reg is Virtual(vreg) {
    selects_int_bits = vreg.class == Int
  }
  inspect(selects_int_bits, content="true")
  inspect(lowered.blocks[0].instructions[3].opcode == Bitcast, content="true")
  inspect(lowered.verify(), content="()")
}

///|
test "x64 legalizes integer division fixed-register operands" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let func = @milkir.Function::new("sdiv64", signature)
  let lhs = func.new_value(I64)
  let rhs = func.new_value(I64)
  let quotient = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Sdiv, [lhs, rhs], [quotient]))
  entry.set_terminator(Return([quotient]))
  let lowered = lower_function(func)
  inspect(lowered.blocks[0].instructions.length(), content="5")
  inspect(lowered.blocks[0].instructions[0].opcode == Move, content="true")
  inspect(lowered.blocks[0].instructions[1].opcode == Move, content="true")
  let div = lowered.blocks[0].instructions[2]
  inspect(div.opcode == IntDiv(true), content="true")
  inspect(div.operands.length(), content="4")
  inspect(div.constraints.length(), content="4")
  inspect(
    div.constraints[0].allowed_regs[0] == { index: 0, class: Int },
    content="true",
  )
  inspect(
    div.constraints[1].allowed_regs[0] == { index: 8, class: Int },
    content="true",
  )
  inspect(
    div.constraints[2].allowed_regs[0] == { index: 0, class: Int },
    content="true",
  )
  inspect(
    div.constraints[3].allowed_regs[0] == { index: 3, class: Int },
    content="true",
  )
  inspect(lowered.blocks[0].instructions[3].opcode == Move, content="true")
}

///|
test "x64 legalizes integer remainder fixed-register operands" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let func = @milkir.Function::new("srem64", signature)
  let lhs = func.new_value(I64)
  let rhs = func.new_value(I64)
  let rem = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Srem, [lhs, rhs], [rem]))
  entry.set_terminator(Return([rem]))
  let lowered = lower_function(func)
  inspect(lowered.blocks[0].instructions.length(), content="5")
  inspect(lowered.blocks[0].instructions[0].opcode == Move, content="true")
  inspect(lowered.blocks[0].instructions[1].opcode == Move, content="true")
  let rem_inst = lowered.blocks[0].instructions[2]
  inspect(rem_inst.opcode == IntRem(true), content="true")
  inspect(rem_inst.operands.length(), content="4")
  inspect(rem_inst.constraints.length(), content="4")
  inspect(
    rem_inst.constraints[0].allowed_regs[0] == { index: 0, class: Int },
    content="true",
  )
  inspect(
    rem_inst.constraints[1].allowed_regs[0] == { index: 8, class: Int },
    content="true",
  )
  inspect(
    rem_inst.constraints[2].allowed_regs[0] == { index: 3, class: Int },
    content="true",
  )
  inspect(
    rem_inst.constraints[3].allowed_regs[0] == { index: 0, class: Int },
    content="true",
  )
  inspect(lowered.blocks[0].instructions[3].opcode == Move, content="true")
}

///|
test "x64 legalizes multiply-high fixed-register operands" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let func = @milkir.Function::new("umulh64", signature)
  let lhs = func.new_value(I64)
  let rhs = func.new_value(I64)
  let high = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Umulh, [lhs, rhs], [high]))
  entry.set_terminator(Return([high]))
  let lowered = lower_function(func)
  inspect(lowered.blocks[0].instructions.length(), content="5")
  inspect(lowered.blocks[0].instructions[0].opcode == Move, content="true")
  inspect(lowered.blocks[0].instructions[1].opcode == Move, content="true")
  let mul = lowered.blocks[0].instructions[2]
  inspect(mul.opcode == IntMulHigh(false), content="true")
  inspect(mul.operands.length(), content="4")
  inspect(mul.constraints.length(), content="4")
  inspect(
    mul.constraints[0].allowed_regs[0] == { index: 0, class: Int },
    content="true",
  )
  inspect(
    mul.constraints[1].allowed_regs[0] == { index: 8, class: Int },
    content="true",
  )
  inspect(
    mul.constraints[2].allowed_regs[0] == { index: 3, class: Int },
    content="true",
  )
  inspect(
    mul.constraints[3].allowed_regs[0] == { index: 0, class: Int },
    content="true",
  )
  inspect(lowered.blocks[0].instructions[3].opcode == Move, content="true")
}

///|
test "x64 legalizes shift count into rcx" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let func = @milkir.Function::new("shl64", signature)
  let value = func.new_value(I64)
  let count = func.new_value(I64)
  let shifted = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Ishl, [value, count], [shifted]))
  entry.set_terminator(Return([shifted]))
  let lowered = lower_function(func)
  inspect(lowered.blocks[0].instructions.length(), content="5")
  inspect(lowered.blocks[0].instructions[0].opcode == Move, content="true")
  inspect(lowered.blocks[0].instructions[1].opcode == Move, content="true")
  let shift = lowered.blocks[0].instructions[2]
  inspect(shift.opcode == IntShl, content="true")
  inspect(shift.operands.length(), content="3")
  inspect(shift.constraints.length(), content="1")
  inspect(
    shift.constraints[0].allowed_regs[0] == { index: 1, class: Int },
    content="true",
  )
  inspect(lowered.blocks[0].instructions[3].opcode == Move, content="true")
}

///|
test "x64 legalizes rotate count into rcx" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let func = @milkir.Function::new("rotl64", signature)
  let value = func.new_value(I64)
  let count = func.new_value(I64)
  let rotated = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Rotl, [value, count], [rotated]))
  entry.set_terminator(Return([rotated]))
  let lowered = lower_function(func)
  inspect(lowered.blocks[0].instructions.length(), content="5")
  inspect(lowered.blocks[0].instructions[0].opcode == Move, content="true")
  inspect(lowered.blocks[0].instructions[1].opcode == Move, content="true")
  let rotate = lowered.blocks[0].instructions[2]
  inspect(rotate.opcode == IntRotl, content="true")
  inspect(rotate.operands.length(), content="3")
  inspect(rotate.constraints.length(), content="1")
  inspect(
    rotate.constraints[0].allowed_regs[0] == { index: 1, class: Int },
    content="true",
  )
  inspect(lowered.blocks[0].instructions[3].opcode == Move, content="true")
}

///|
test "x64 lowers extended MilkIR ops into structured MachV opcodes" {
  let func = @milkir.Function::new_empty("extended")
  let lhs = func.new_value(I64)
  let rhs = func.new_value(I64)
  let bits = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Band, [lhs, rhs], [bits]))
  entry.append_inst(func.new_inst(Ushr, [bits, rhs], [func.new_value(I64)]))
  entry.append_inst(
    func.new_inst(Fsqrt, [func.new_value(F64)], [func.new_value(F64)]),
  )
  entry.set_terminator(Return([]))
  let lowered = lower_function(func)
  inspect(lowered.blocks[0].instructions[0].opcode == IntAnd, content="true")
  inspect(
    lowered.blocks[0].instructions[3].opcode == IntShr(false),
    content="true",
  )
  inspect(lowered.blocks[0].instructions[5].opcode == FloatSqrt, content="true")
}

///|
test "x64 folds constant pointer offsets into MachV memory opcodes" {
  let builder = @milkir.IRBuilder::new("mem")
  let ptr = builder.add_param(Ptr)
  builder.add_result(I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let load_offset = builder.iconst_i64(4L)
  let loaded = builder.load_ptr(I32, ptr, load_offset)
  let store_offset = builder.iconst_i64(16L)
  builder.store_ptr(I64, ptr, builder.iconst_i64(99L), store_offset)
  builder.return_([loaded])
  let lowered = lower_function(builder.get_function())
  inspect(
    lowered.blocks[0].instructions[1].opcode == LoadPtr(MemI32, 4),
    content="true",
  )
  inspect(lowered.blocks[0].instructions[1].operands.length(), content="2")
  inspect(
    lowered.blocks[0].instructions[4].opcode == StorePtr(MemI64, 16),
    content="true",
  )
  inspect(lowered.blocks[0].instructions[4].operands.length(), content="2")
}

///|
test "x64 folds constant narrow pointer offsets into MachV memory opcodes" {
  let builder = @milkir.IRBuilder::new("narrow_mem")
  let ptr = builder.add_param(Ptr)
  builder.add_result(I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let load_offset = builder.iconst_i64(4L)
  let loaded = builder.load_ptr_narrow(I32, 8, false, ptr, load_offset)
  let store_offset = builder.iconst_i64(8L)
  builder.store_ptr_narrow(16, ptr, loaded, store_offset)
  builder.return_([loaded])
  let lowered = lower_function(builder.get_function())
  inspect(
    lowered.blocks[0].instructions[1].opcode == LoadPtrNarrow(8, false, 4),
    content="true",
  )
  inspect(lowered.blocks[0].instructions[1].operands.length(), content="2")
  inspect(
    lowered.blocks[0].instructions[3].opcode == StorePtrNarrow(16, 8),
    content="true",
  )
  inspect(lowered.blocks[0].instructions[3].operands.length(), content="2")
}

///|
test "x64 lowers generic load and store with value widths" {
  let func = @milkir.Function::new_empty("generic_mem")
  let ptr = func.new_value(Ptr)
  let value = func.new_value(I32)
  let loaded = func.new_value(I32)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Load, [ptr], [loaded]))
  entry.append_inst(func.new_inst(Store, [ptr, value], []))
  entry.set_terminator(Return([loaded]))
  let lowered = lower_function(func)
  inspect(
    lowered.blocks[0].instructions[0].opcode == LoadMemory(MemI32, 0),
    content="true",
  )
  inspect(
    lowered.blocks[0].instructions[1].opcode == StoreMemory(MemI32, 0),
    content="true",
  )
}

///|
test "x64 remaps sparse MilkIR block targets" {
  let func = @milkir.Function::new_empty("sparse_blocks")
  let cond = func.new_value(I32)
  let entry = func.new_block([])
  let trap = func.new_block([])
  let exit = func.new_block([])
  func.new_block([]) |> ignore
  let target = func.new_block([])
  func.blocks.remove(3) |> ignore
  entry.append_inst(func.new_inst(Iconst(1), [], [cond]))
  entry.set_terminator(Brnz(cond, target.id, trap.id))
  trap.set_terminator(TrapExit("trap"))
  exit.set_terminator(Return([]))
  target.set_terminator(Return([]))
  let lowered = lower_function(func)
  guard lowered.blocks[0].terminator
    is Some(TermBranchZero(_, _, _, true_target, _, false_target, _)) else {
    fail("expected branch-zero terminator")
  }
  inspect(true_target, content="3")
  inspect(false_target, content="1")
}

///|
test "x64 lowers direct calls with SystemV ABI constraints" {
  let func = @milkir.Function::new_empty("call")
  let int0 = func.new_value(I64)
  let float0 = func.new_value(F64)
  let int1 = func.new_value(I64)
  let result0 = func.new_value(I64)
  let result1 = func.new_value(F64)
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(
      Call(@milkir.ExternalSymbol::new("callee")),
      [int0, float0, int1],
      [result0, result1],
    ),
  )
  entry.set_terminator(Return([result0, result1]))
  let lowered = lower_function(func)
  let call = lowered.blocks[0].instructions[0]
  inspect(call.opcode == Call("callee"), content="true")
  inspect(call.constraints.length(), content="5")
  inspect(
    call.constraints[0].allowed_regs[0] == { index: 7, class: Int },
    content="true",
  )
  inspect(
    call.constraints[1].allowed_regs[0] == { index: 0, class: Float64 },
    content="true",
  )
  inspect(
    call.constraints[2].allowed_regs[0] == { index: 6, class: Int },
    content="true",
  )
  inspect(
    call.constraints[3].allowed_regs[0] == { index: 0, class: Int },
    content="true",
  )
  inspect(
    call.constraints[4].allowed_regs[0] == { index: 0, class: Float64 },
    content="true",
  )
  inspect(call.clobbers.length() > 0, content="true")
}

///|
test "x64 records outgoing stack arguments for direct calls" {
  let func = @milkir.Function::new_empty("call_stack_args")
  let args : Array[@milkir.Value] = []
  for _ in 0..<7 {
    args.push(func.new_value(I64))
  }
  let results : Array[@milkir.Value] = []
  for _ in 0..<3 {
    results.push(func.new_value(I64))
  }
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(Call(@milkir.ExternalSymbol::new("callee")), args, results),
  )
  entry.set_terminator(Return([]))
  let lowered = lower_function(func)
  let call = lowered.blocks[0].instructions[0]
  inspect(call.stack_effect == CallFrame(16), content="true")
  inspect(lowered.get_max_outgoing_args_size(), content="16")
  guard call.abi_arg_locations[6] is Stack(offset~, size~, align~) else {
    fail("expected seventh direct-call integer argument on stack")
  }
  inspect(offset, content="0")
  inspect(size, content="8")
  inspect(align, content="8")
  guard call.abi_result_locations[2]
    is ReturnArea(offset=ret_offset, size=ret_size, align=ret_align) else {
    fail("expected third direct-call integer result in return area")
  }
  inspect(ret_offset, content="0")
  inspect(ret_size, content="8")
  inspect(ret_align, content="8")
}

///|
test "x64 lowers CallPtr with Wasm ABI constraints and clobbers" {
  let func = @milkir.Function::new_empty("callptr")
  let callee = func.new_value(Ptr)
  let vmctx = func.new_value(Ptr)
  let int_arg = func.new_value(I64)
  let float_arg = func.new_value(F64)
  let result = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(CallPtr(2, 1), [callee, vmctx, int_arg, float_arg], [result]),
  )
  entry.set_terminator(Return([result]))
  let lowered = lower_function(func)
  let call = lowered.blocks[0].instructions[0]
  inspect(call.opcode == CallPtr(2, 1), content="true")
  inspect(call.constraints.length(), content="4")
  inspect(
    call.constraints[0].allowed_regs[0] == { index: 11, class: Int },
    content="true",
  )
  inspect(
    call.constraints[1].allowed_regs[0] == { index: 7, class: Int },
    content="true",
  )
  inspect(
    call.constraints[2].allowed_regs[0] == { index: 6, class: Int },
    content="true",
  )
  inspect(
    call.constraints[3].allowed_regs[0] == { index: 0, class: Float64 },
    content="true",
  )
  inspect(call.clobbers.length() > 0, content="true")
}

///|
test "x64 records outgoing stack arguments for Wasm CallPtr" {
  let func = @milkir.Function::new_empty("callptr_stack_args")
  let callee = func.new_value(Ptr)
  let vmctx = func.new_value(Ptr)
  let args : Array[@milkir.Value] = [callee, vmctx]
  for _ in 0..<6 {
    args.push(func.new_value(I64))
  }
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(CallPtr(6, 0), args, []))
  entry.set_terminator(Return([]))
  let lowered = lower_function(func)
  let call = lowered.blocks[0].instructions[0]
  inspect(call.stack_effect == CallFrame(16), content="true")
  inspect(lowered.get_max_outgoing_args_size(), content="16")
  guard call.abi_arg_locations[7] is Stack(offset~, size~, align~) else {
    fail("expected sixth Wasm CallPtr user argument on stack")
  }
  inspect(offset, content="0")
  inspect(size, content="8")
  inspect(align, content="8")
}

///|
test "x64 lowers Wasm CallPtr return-area loads through ExtraResultsPtr" {
  let func = @milkir.Function::new_empty("callptr_return_area_load")
  let callee = func.new_value(Ptr)
  let vmctx = func.new_value(Ptr)
  let results : Array[@milkir.Value] = []
  for _ in 0..<9 {
    results.push(func.new_value(I64))
  }
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(CallPtr(0, 9), [callee, vmctx], results))
  entry.set_terminator(Return([]))
  let lowered = lower_function(func)
  let mut has_load = false
  for inst in lowered.blocks[0].instructions {
    if inst.opcode == LoadPtr(MemI64, 0) &&
      inst.operands.length() >= 2 &&
      inst.operands[0].reg == Physical({ index: 12, class: Int }) {
      has_load = true
    }
  }
  inspect(has_load, content="true")
}
