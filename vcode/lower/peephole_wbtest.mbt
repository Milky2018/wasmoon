///|
/// Tests for peephole optimizations
test "store_merging_combines_adjacent_store8" {
  // Create a test function with two adjacent store8 operations
  let func = @regalloc.VCodeFunction::new("test_store_merge")

  // Add parameters: base address and two values to store
  let base = func.new_vreg(Int)
  func.push_param(base)
  let val1 = func.new_vreg(Int)
  func.push_param(val1)
  let val2 = func.new_vreg(Int)
  func.push_param(val2)

  // Create a block with two adjacent store8 operations
  let block = @block.VCodeBlock::new(0)

  // store8 [base+0], val1
  let store1 = @instr.VCodeInst::new(StorePtrNarrow(8, 0))
  store1.add_use(Virtual(base))
  store1.add_use(Virtual(val1))
  block.add_inst(store1)

  // store8 [base+1], val2
  let store2 = @instr.VCodeInst::new(StorePtrNarrow(8, 1))
  store2.add_use(Virtual(base))
  store2.add_use(Virtual(val2))
  block.add_inst(store2)

  // Add return terminator
  block.set_terminator(Return([]))
  func.blocks.push(block)

  // Before optimization: 2 instructions
  inspect(func.blocks[0].insts.length(), content="2")

  // Run peephole optimization
  optimize_vcode(func)

  // After optimization: should have merged into fewer instructions
  // Expected: 1 OrShifted + 1 store16 = 2 instructions (but combined value)
  // The key is that we now have a store16 instead of two store8
  let insts = func.blocks[0].insts
  let mut has_store16 = false
  let mut has_or_shifted = false
  for inst in insts {
    match inst.opcode {
      StorePtrNarrow(16, 0) => has_store16 = true
      OrShifted(Lsl, 8) => has_or_shifted = true
      _ => ()
    }
  }
  inspect(has_store16, content="true")
  inspect(has_or_shifted, content="true")
}

///|
test "load_store_forwarding_eliminates_redundant_load" {
  // Create a test function
  let func = @regalloc.VCodeFunction::new("test_forwarding")

  // Add parameters
  let base = func.new_vreg(Int)
  func.push_param(base)
  let val = func.new_vreg(Int)
  func.push_param(val)

  // Create a block with store followed by load from same address
  let block = @block.VCodeBlock::new(0)

  // store8 [base+0], val
  let store = @instr.VCodeInst::new(StorePtrNarrow(8, 0))
  store.add_use(Virtual(base))
  store.add_use(Virtual(val))
  block.add_inst(store)

  // result = load8u [base+0]
  let result = func.new_vreg(Int)
  let load = @instr.VCodeInst::new(LoadPtrNarrow(8, false, 0))
  load.add_def({ reg: Virtual(result) })
  load.add_use(Virtual(base))
  block.add_inst(load)

  // return result
  block.set_terminator(Return([Virtual(result)]))
  func.blocks.push(block)

  // Before optimization: store + load
  inspect(func.blocks[0].insts.length(), content="2")

  // Run peephole optimization
  optimize_vcode(func)

  // After optimization: store + extend (load is forwarded with correct semantics)
  let insts = func.blocks[0].insts
  let mut has_store = false
  let mut has_extend = false
  for inst in insts {
    match inst.opcode {
      StorePtrNarrow(8, 0) => has_store = true
      Extend(@instr.Unsigned8To64) => has_extend = true
      _ => ()
    }
  }
  inspect(has_store, content="true")
  inspect(has_extend, content="true")
}

///|
test "thread_trivial_jump_blocks_forwards_block_args" {
  let func = @regalloc.VCodeFunction::new("test_thread_jump_args")
  let arg0 = func.new_vreg(Int)
  let arg1 = func.new_vreg(Int)
  func.push_param(arg0)
  func.push_param(arg1)
  let block0 = func.new_block()
  let block1 = func.new_block()
  let block2 = func.new_block()
  let p0 = func.new_vreg(Int)
  let p1 = func.new_vreg(Int)
  block1.params.push(p0)
  block1.params.push(p1)
  let q0 = func.new_vreg(Int)
  let q1 = func.new_vreg(Int)
  block2.params.push(q0)
  block2.params.push(q1)
  block0.set_terminator(Jump(block1.id, [Virtual(arg0), Virtual(arg1)]))
  block1.set_terminator(Jump(block2.id, [Virtual(p1), Virtual(p0)]))
  block2.set_terminator(Return([Virtual(q0)]))
  optimize_vcode(func)
  if block0.terminator is Some(Jump(target, args)) {
    inspect(target == block2.id, content="true")
    inspect(args.length(), content="2")
    if args[0] is Virtual(v) {
      inspect(v.id == arg1.id, content="true")
    } else {
      inspect(false, content="true")
    }
    if args[1] is Virtual(v) {
      inspect(v.id == arg0.id, content="true")
    } else {
      inspect(false, content="true")
    }
  } else {
    inspect(false, content="true")
  }
}

///|
test "thread_trivial_jump_blocks_updates_branch_targets" {
  let func = @regalloc.VCodeFunction::new("test_thread_branch_targets")
  let cond = func.new_vreg(Int)
  func.push_param(cond)
  let block0 = func.new_block()
  let block1 = func.new_block()
  let block2 = func.new_block()
  let block3 = func.new_block()
  let block4 = func.new_block()
  block0.set_terminator(Branch(Virtual(cond), block1.id, block2.id))
  block1.set_terminator(Jump(block3.id, []))
  block2.set_terminator(Jump(block4.id, []))
  block3.set_terminator(Return([]))
  block4.set_terminator(Return([]))
  optimize_vcode(func)
  if block0.terminator is Some(Branch(_, then_b, else_b)) {
    inspect(then_b == block3.id, content="true")
    inspect(else_b == block4.id, content="true")
  } else {
    inspect(false, content="true")
  }
}

///|
test "mul_power_of_two_becomes_shl_imm" {
  let func = @regalloc.VCodeFunction::new("test_mul_pow2")
  let lhs = func.new_vreg(Int)
  func.push_param(lhs)
  let block = func.new_block()
  let c16 = func.new_vreg(Int)
  let load_16 = @instr.VCodeInst::new(LoadConst(16L))
  load_16.add_def({ reg: Virtual(c16) })
  block.add_inst(load_16)
  let out = func.new_vreg(Int)
  let mul = @instr.VCodeInst::new(Mul(true))
  mul.add_def({ reg: Virtual(out) })
  mul.add_use(Virtual(lhs))
  mul.add_use(Virtual(c16))
  block.add_inst(mul)
  block.set_terminator(Return([Virtual(out)]))
  optimize_vcode(func)
  let mut has_mul = false
  let mut has_shl = false
  for inst in block.insts {
    match inst.opcode {
      Mul(true) => has_mul = true
      ShlImm(4, true) => has_shl = true
      _ => ()
    }
  }
  inspect(has_mul, content="false")
  inspect(has_shl, content="true")
}

///|
test "mem_base_cse_reuses_load_without_call_barrier" {
  let func = @regalloc.VCodeFunction::new("test_mem_base_cse_no_call")
  let vmctx = func.new_vreg(Int)
  func.push_param(vmctx)
  let block = func.new_block()

  let mem0_a = func.new_vreg(Int)
  let load0 = @instr.VCodeInst::new(LoadMemBase(0))
  load0.add_def({ reg: Virtual(mem0_a) })
  load0.add_use(Virtual(vmctx))
  block.add_inst(load0)

  let mem0_b = func.new_vreg(Int)
  let load1 = @instr.VCodeInst::new(LoadMemBase(0))
  load1.add_def({ reg: Virtual(mem0_b) })
  load1.add_use(Virtual(vmctx))
  block.add_inst(load1)

  let sum = func.new_vreg(Int)
  let add = @instr.VCodeInst::new(Add(true))
  add.add_def({ reg: Virtual(sum) })
  add.add_use(Virtual(mem0_a))
  add.add_use(Virtual(mem0_b))
  block.add_inst(add)
  block.set_terminator(Return([Virtual(sum)]))

  optimize_vcode(func)

  let mut load_mem_base_count = 0
  let mut move_count = 0
  for inst in block.insts {
    match inst.opcode {
      LoadMemBase(0) => load_mem_base_count = load_mem_base_count + 1
      Move => move_count = move_count + 1
      _ => ()
    }
  }
  inspect(load_mem_base_count, content="1")
  inspect(move_count, content="0")
}

///|
test "mem_base_cse_does_not_cross_wasm_call_barrier" {
  let func = @regalloc.VCodeFunction::new("test_mem_base_cse_call_barrier")
  let vmctx = func.new_vreg(Int)
  func.push_param(vmctx)
  let callee = func.new_vreg(Int)
  func.push_param(callee)
  let block = func.new_block()

  let mem0_a = func.new_vreg(Int)
  let load0 = @instr.VCodeInst::new(LoadMemBase(0))
  load0.add_def({ reg: Virtual(mem0_a) })
  load0.add_use(Virtual(vmctx))
  block.add_inst(load0)

  let call_inst = @instr.VCodeInst::new(CallPtr(0, 0, Wasm))
  call_inst.add_use(Virtual(callee))
  block.add_inst(call_inst)

  let mem0_b = func.new_vreg(Int)
  let load1 = @instr.VCodeInst::new(LoadMemBase(0))
  load1.add_def({ reg: Virtual(mem0_b) })
  load1.add_use(Virtual(vmctx))
  block.add_inst(load1)

  let sum = func.new_vreg(Int)
  let add = @instr.VCodeInst::new(Add(true))
  add.add_def({ reg: Virtual(sum) })
  add.add_use(Virtual(mem0_a))
  add.add_use(Virtual(mem0_b))
  block.add_inst(add)
  block.set_terminator(Return([Virtual(sum)]))

  optimize_vcode(func)

  let mut load_mem_base_count = 0
  let mut move_count = 0
  for inst in block.insts {
    match inst.opcode {
      LoadMemBase(0) => load_mem_base_count = load_mem_base_count + 1
      Move => move_count = move_count + 1
      _ => ()
    }
  }
  inspect(load_mem_base_count, content="2")
  inspect(move_count, content="0")
}
