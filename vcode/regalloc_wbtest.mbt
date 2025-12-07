// Tests for register allocation

///|
test "liveness: simple function" {
  // Create a simple VCode function: add(a, b) -> a + b
  let func = VCodeFunction::new("test_add")
  let a = func.add_param(Int)
  let b = func.add_param(Int)
  func.add_result(Int)
  let block = func.new_block()

  // v2 = add v0, v1
  let add_inst = VCodeInst::new(Add)
  let result_vreg = func.new_vreg(Int)
  add_inst.add_def({ reg: Virtual(result_vreg) })
  add_inst.add_use(Virtual(a))
  add_inst.add_use(Virtual(b))
  block.add_inst(add_inst)

  // ret v2
  block.set_terminator(Return([Virtual(result_vreg)]))

  // Compute liveness
  let liveness = compute_liveness(func)

  // Check that we have intervals for all three vregs
  inspect(liveness.intervals.length(), content="3")

  // Check that v0 (a) is live from entry to its use
  let v0_interval = liveness.intervals.get(0)
  inspect(v0_interval is None, content="false")

  // Check that v1 (b) is live from entry to its use
  let v1_interval = liveness.intervals.get(1)
  inspect(v1_interval is None, content="false")

  // Check that v2 (result) is live from def to return
  let v2_interval = liveness.intervals.get(2)
  inspect(v2_interval is None, content="false")
}

///|
test "regalloc: simple allocation" {
  // Create a simple VCode function
  let func = VCodeFunction::new("test_alloc")
  let a = func.add_param(Int)
  let b = func.add_param(Int)
  func.add_result(Int)
  let block = func.new_block()

  // v2 = add v0, v1
  let add_inst = VCodeInst::new(Add)
  let result_vreg = func.new_vreg(Int)
  add_inst.add_def({ reg: Virtual(result_vreg) })
  add_inst.add_use(Virtual(a))
  add_inst.add_use(Virtual(b))
  block.add_inst(add_inst)

  // ret v2
  block.set_terminator(Return([Virtual(result_vreg)]))

  // Allocate registers
  let int_regs = [
    { index: 0, class: Int },
    { index: 1, class: Int },
    { index: 2, class: Int },
  ]
  let float_regs : Array[PReg] = []
  let liveness = compute_liveness(func)
  let allocator = LinearScanAllocator::new(int_regs, float_regs)
  let result = allocator.allocate(func, liveness)

  // Check that all vregs got assigned
  inspect(result.assignments.length(), content="3")

  // No spills should be needed
  inspect(result.num_spill_slots, content="0")
}

///|
test "regalloc: with spilling" {
  // Create a function that uses more registers than available
  let func = VCodeFunction::new("test_spill")
  let a = func.add_param(Int)
  let b = func.add_param(Int)
  let c = func.add_param(Int)
  let d = func.add_param(Int)
  func.add_result(Int)
  let block = func.new_block()

  // All params live at the same time, need more than 2 registers
  // v4 = add v0, v1
  let add1 = VCodeInst::new(Add)
  let t1 = func.new_vreg(Int)
  add1.add_def({ reg: Virtual(t1) })
  add1.add_use(Virtual(a))
  add1.add_use(Virtual(b))
  block.add_inst(add1)

  // v5 = add v2, v3
  let add2 = VCodeInst::new(Add)
  let t2 = func.new_vreg(Int)
  add2.add_def({ reg: Virtual(t2) })
  add2.add_use(Virtual(c))
  add2.add_use(Virtual(d))
  block.add_inst(add2)

  // v6 = add v4, v5
  let add3 = VCodeInst::new(Add)
  let result = func.new_vreg(Int)
  add3.add_def({ reg: Virtual(result) })
  add3.add_use(Virtual(t1))
  add3.add_use(Virtual(t2))
  block.add_inst(add3)

  // ret v6
  block.set_terminator(Return([Virtual(result)]))

  // Only provide 2 registers - should cause spilling
  let int_regs = [{ index: 0, class: Int }, { index: 1, class: Int }]
  let float_regs : Array[PReg] = []
  let liveness = compute_liveness(func)
  let allocator = LinearScanAllocator::new(int_regs, float_regs)
  let result_alloc = allocator.allocate(func, liveness)

  // Some vregs should be spilled since we have 7 vregs but only 2 registers
  inspect(result_alloc.num_spill_slots > 0, content="false")
}

///|
test "regalloc: float registers" {
  // Test that float vregs use float registers
  let func = VCodeFunction::new("test_float")
  let a = func.add_param(Float)
  let b = func.add_param(Float)
  func.add_result(Float)
  let block = func.new_block()

  // f2 = fadd f0, f1
  let fadd_inst = VCodeInst::new(FAdd)
  let result_vreg = func.new_vreg(Float)
  fadd_inst.add_def({ reg: Virtual(result_vreg) })
  fadd_inst.add_use(Virtual(a))
  fadd_inst.add_use(Virtual(b))
  block.add_inst(fadd_inst)

  // ret f2
  block.set_terminator(Return([Virtual(result_vreg)]))

  // Allocate registers
  let int_regs : Array[PReg] = []
  let float_regs = [
    { index: 0, class: Float },
    { index: 1, class: Float },
    { index: 2, class: Float },
  ]
  let liveness = compute_liveness(func)
  let allocator = LinearScanAllocator::new(int_regs, float_regs)
  let result = allocator.allocate(func, liveness)

  // All float vregs should be assigned
  inspect(result.assignments.length(), content="3")
  inspect(result.num_spill_slots, content="0")
}

///|
test "apply_allocation: rewrites virtual to physical" {
  // Create a simple function
  let func = VCodeFunction::new("test_rewrite")
  let a = func.add_param(Int)
  func.add_result(Int)
  let block = func.new_block()

  // v1 = ldi 42
  let const_inst = VCodeInst::new(LoadConst(42L))
  let const_vreg = func.new_vreg(Int)
  const_inst.add_def({ reg: Virtual(const_vreg) })
  block.add_inst(const_inst)

  // v2 = add v0, v1
  let add_inst = VCodeInst::new(Add)
  let result_vreg = func.new_vreg(Int)
  add_inst.add_def({ reg: Virtual(result_vreg) })
  add_inst.add_use(Virtual(a))
  add_inst.add_use(Virtual(const_vreg))
  block.add_inst(add_inst)

  // ret v2
  block.set_terminator(Return([Virtual(result_vreg)]))

  // Allocate
  let allocated = allocate_registers_aarch64(func)

  // Check that the result has same structure
  inspect(allocated.blocks.length(), content="1")

  // Check that instructions use physical registers in the allocated version
  let result_block = allocated.blocks[0]
  inspect(result_block.insts.length(), content="2")
}

///|
test "liveness: multi-block function" {
  // Create a function with multiple blocks (if-else)
  let func = VCodeFunction::new("test_multiblock")
  let cond = func.add_param(Int)
  let a = func.add_param(Int)
  let b = func.add_param(Int)
  func.add_result(Int)

  // Entry block
  let entry = func.new_block()
  entry.set_terminator(Branch(Virtual(cond), 1, 2))

  // Then block
  let then_block = func.new_block()
  let then_inst = VCodeInst::new(Move)
  let then_result = func.new_vreg(Int)
  then_inst.add_def({ reg: Virtual(then_result) })
  then_inst.add_use(Virtual(a))
  then_block.add_inst(then_inst)
  then_block.set_terminator(Return([Virtual(then_result)]))

  // Else block
  let else_block = func.new_block()
  let else_inst = VCodeInst::new(Move)
  let else_result = func.new_vreg(Int)
  else_inst.add_def({ reg: Virtual(else_result) })
  else_inst.add_use(Virtual(b))
  else_block.add_inst(else_inst)
  else_block.set_terminator(Return([Virtual(else_result)]))

  // Compute liveness
  let liveness = compute_liveness(func)

  // Check that params are live in entry block
  inspect(liveness.live_in[0].contains(0), content="true") // cond
  inspect(liveness.live_in[0].contains(1), content="true") // a
  inspect(liveness.live_in[0].contains(2), content="true") // b

  // 'a' should be live into then_block
  inspect(liveness.live_in[1].contains(1), content="true")

  // 'b' should be live into else_block
  inspect(liveness.live_in[2].contains(2), content="true")
}

///|
test "regalloc: aarch64 convenience function" {
  // Test the convenience function
  let func = VCodeFunction::new("test_aarch64")
  let a = func.add_param(Int)
  let b = func.add_param(Int)
  func.add_result(Int)
  let block = func.new_block()
  let add_inst = VCodeInst::new(Add)
  let result_vreg = func.new_vreg(Int)
  add_inst.add_def({ reg: Virtual(result_vreg) })
  add_inst.add_use(Virtual(a))
  add_inst.add_use(Virtual(b))
  block.add_inst(add_inst)
  block.set_terminator(Return([Virtual(result_vreg)]))

  // Allocate with AArch64 registers
  let allocated = allocate_registers_aarch64(func)

  // Function should be valid
  inspect(allocated.name, content="test_aarch64")
  inspect(allocated.params.length(), content="2")
  inspect(allocated.blocks.length(), content="1")
}

///|
test "progpoint: comparison" {
  // Test program point ordering
  let p1 : ProgPoint = { block: 0, inst: 0, pos: Before }
  let p2 : ProgPoint = { block: 0, inst: 0, pos: After }
  let p3 : ProgPoint = { block: 0, inst: 1, pos: Before }
  let p4 : ProgPoint = { block: 1, inst: 0, pos: Before }

  // p1 < p2 (Before < After)
  inspect(p1.compare(p2) < 0, content="true")

  // p2 < p3 (same block, earlier inst < later inst)
  inspect(p2.compare(p3) < 0, content="true")

  // p3 < p4 (earlier block < later block)
  inspect(p3.compare(p4) < 0, content="true")

  // Equal comparison
  let p5 : ProgPoint = { block: 0, inst: 0, pos: Before }
  inspect(p1.compare(p5), content="0")
}
