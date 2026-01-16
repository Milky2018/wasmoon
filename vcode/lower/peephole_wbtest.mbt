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
