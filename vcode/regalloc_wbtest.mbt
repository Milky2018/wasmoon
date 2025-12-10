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
  inspect(result_alloc.num_spill_slots > 0, content="true")
}

///|
test "regalloc: float registers" {
  // Test that float vregs use float registers
  let func = VCodeFunction::new("test_float")
  let a = func.add_param(Float64)
  let b = func.add_param(Float64)
  func.add_result(Float64)
  let block = func.new_block()

  // f2 = fadd f0, f1
  let fadd_inst = VCodeInst::new(FAdd)
  let result_vreg = func.new_vreg(Float64)
  fadd_inst.add_def({ reg: Virtual(result_vreg) })
  fadd_inst.add_use(Virtual(a))
  fadd_inst.add_use(Virtual(b))
  block.add_inst(fadd_inst)

  // ret f2
  block.set_terminator(Return([Virtual(result_vreg)]))

  // Allocate registers
  let int_regs : Array[PReg] = []
  let float_regs = [
    { index: 0, class: Float64 },
    { index: 1, class: Float64 },
    { index: 2, class: Float64 },
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
  let order : Map[Int, Int] = {}
  order.set(0, 0)
  order.set(1, 1)

  // p1 < p2 (Before < After)
  inspect(p1.compare_with_order(p2, order) < 0, content="true")

  // p2 < p3 (same block, earlier inst < later inst)
  inspect(p2.compare_with_order(p3, order) < 0, content="true")

  // p3 < p4 (earlier block < later block)
  inspect(p3.compare_with_order(p4, order) < 0, content="true")

  // Equal comparison
  let p5 : ProgPoint = { block: 0, inst: 0, pos: Before }
  inspect(p1.compare_with_order(p5, order), content="0")
}

///|
test "liveness: block parameters should have use points" {
  // This test verifies that block parameters get use points at block entry
  // Reproduces the bug found in f32_br_2locals.wast
  let func = VCodeFunction::new("test_block_param_use")

  // Create:
  // block0:
  //   v0 = ldi 10
  //   v1 = mov v0
  //   jump block1
  // block1(v1):  ; v1 is passed as block parameter
  //   ret v1

  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let block0 = func.new_block()
  let block1 = func.new_block()

  // block0: v0 = ldi 10; v1 = mov v0; jump block1
  let inst0 = VCodeInst::new(LoadConst(10L))
  inst0.add_def({ reg: Virtual(v0) })
  block0.add_inst(inst0)
  let inst1 = VCodeInst::new(Move)
  inst1.add_use(Virtual(v0))
  inst1.add_def({ reg: Virtual(v1) })
  block0.add_inst(inst1)
  block0.set_terminator(Jump(block1.id))

  // block1(v1): ret v1
  block1.params.push(v1)
  block1.set_terminator(Return([Virtual(v1)]))

  // Compute liveness
  let liveness = compute_liveness(func)

  // v1 should have use points in both blocks
  let v1_info = liveness.use_def.get(v1.id).unwrap()

  // Should have at least 2 use points: one at block0's move, one at block1 entry
  inspect(v1_info.use_points.length() >= 2, content="true")

  // v1 should be in block1's live-in set
  inspect(liveness.live_in[1].contains(v1.id), content="true")

  // v1's interval should extend into block1
  let v1_interval = liveness.intervals.get(v1.id).unwrap()
  inspect(v1_interval.end.block >= 1, content="true")
}

///|
test "liveness: mutually exclusive paths with same vreg" {
  // CRITICAL TEST: Same vreg defined on multiple mutually exclusive paths
  // This is the core issue in f32_br_2locals.wast
  let func = VCodeFunction::new("test_mutually_exclusive")

  // Create a diamond CFG:
  // block0:
  //   v0 = ldi 1
  //   branch v0, block1, block2
  // block1:
  //   v1 = ldi 10
  //   jump block3
  // block2:
  //   v1 = ldi 20  ; SAME vreg v1 defined here!
  //   jump block3
  // block3:
  //   ret v1

  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let block0 = func.new_block()
  let block1 = func.new_block()
  let block2 = func.new_block()
  let block3 = func.new_block()

  // block0
  let inst0 = VCodeInst::new(LoadConst(1L))
  inst0.add_def({ reg: Virtual(v0) })
  block0.add_inst(inst0)
  block0.set_terminator(Branch(Virtual(v0), block1.id, block2.id))

  // block1
  let inst1 = VCodeInst::new(LoadConst(10L))
  inst1.add_def({ reg: Virtual(v1) })
  block1.add_inst(inst1)
  block1.set_terminator(Jump(block3.id))

  // block2
  let inst2 = VCodeInst::new(LoadConst(20L))
  inst2.add_def({ reg: Virtual(v1) })
  block2.add_inst(inst2)
  block2.set_terminator(Jump(block3.id))

  // block3
  block3.set_terminator(Return([Virtual(v1)]))

  // Compute liveness
  let liveness = compute_liveness(func)

  // Get v1's use-def info
  let v1_info = liveness.use_def.get(v1.id).unwrap()

  // CRITICAL: v1 has TWO definitions: (1:0a) and (2:0a)
  // Current code only keeps ONE def_point
  match v1_info.def_point {
    Some(_) => ()
    None => ()
  }

  // v1 should be in block3's live-in set
  inspect(liveness.live_in[3].contains(v1.id), content="true")

  // v1's interval
  let v1_interval = liveness.intervals.get(v1.id).unwrap()

  // The interval should end at block3
  inspect(v1_interval.end.block == 3, content="true")

  // PROBLEM: The interval start is only at ONE of the two definitions!
  // This means one path will have an uninitialized register!
  //
  // If def_point is block1, then block2 path will use uninitialized v1
  // If def_point is block2, then block1 path will use uninitialized v1
  //
  // This test DEMONSTRATES the bug but doesn't fix it.
  // The fix would require either:
  // 1. Splitting v1 into two vregs (v1_then, v1_else)
  // 2. Creating separate intervals for each definition
  // 3. Ensuring both paths define v1 in the same physical register
}

///|
test "regalloc: SSA deconstruction scenario" {
  // Test SSA deconstruction with block parameters
  // Simulates the br_table lowering pattern
  let func = VCodeFunction::new("test_ssa_decon")

  // Create:
  // block0:
  //   v0 = ldi 0
  //   f1 = ldf32 0x41200000  ; 10.0
  //   v2 = ldi 1
  //   v3 = cmp.eq v0, v2
  //   branch v3, block2, block3
  //
  // block1(v4, f5):  ; common target with block params
  //   ret f5
  //
  // block2:
  //   v4 = mov v0
  //   f5 = mov f1
  //   jump block1
  //
  // block3:
  //   v4 = mov v0
  //   f5 = mov f1
  //   jump block1

  let v0 = func.new_vreg(Int)
  let f1 = func.new_vreg(Float64)
  let v2 = func.new_vreg(Int)
  let v3 = func.new_vreg(Int)
  let v4 = func.new_vreg(Int)
  let f5 = func.new_vreg(Float64)
  let block0 = func.new_block()
  let block1 = func.new_block()
  let block2 = func.new_block()
  let block3 = func.new_block()

  // block0
  let inst0 = VCodeInst::new(LoadConst(0L))
  inst0.add_def({ reg: Virtual(v0) })
  block0.add_inst(inst0)
  let inst1 = VCodeInst::new(LoadConstF32(0x41200000)) // 10.0
  inst1.add_def({ reg: Virtual(f1) })
  block0.add_inst(inst1)
  let inst2 = VCodeInst::new(LoadConst(1L))
  inst2.add_def({ reg: Virtual(v2) })
  block0.add_inst(inst2)
  let inst3 = VCodeInst::new(Cmp(Eq))
  inst3.add_use(Virtual(v0))
  inst3.add_use(Virtual(v2))
  inst3.add_def({ reg: Virtual(v3) })
  block0.add_inst(inst3)
  block0.set_terminator(Branch(Virtual(v3), block2.id, block3.id))

  // block1 with params
  block1.params.push(v4)
  block1.params.push(f5)
  block1.set_terminator(Return([Virtual(f5)]))

  // block2: moves to pass values to block1 params
  let inst4 = VCodeInst::new(Move)
  inst4.add_use(Virtual(v0))
  inst4.add_def({ reg: Virtual(v4) })
  block2.add_inst(inst4)
  let inst5 = VCodeInst::new(Move)
  inst5.add_use(Virtual(f1))
  inst5.add_def({ reg: Virtual(f5) })
  block2.add_inst(inst5)
  block2.set_terminator(Jump(block1.id))

  // block3: same moves
  let inst6 = VCodeInst::new(Move)
  inst6.add_use(Virtual(v0))
  inst6.add_def({ reg: Virtual(v4) })
  block3.add_inst(inst6)
  let inst7 = VCodeInst::new(Move)
  inst7.add_use(Virtual(f1))
  inst7.add_def({ reg: Virtual(f5) })
  block3.add_inst(inst7)
  block3.set_terminator(Jump(block1.id))

  // Compute liveness
  let liveness = compute_liveness(func)

  // f5 should be in block1's live-in set (v4 is not used, so it's not live-in)
  inspect(liveness.live_in[1].contains(f5.id), content="true")

  // Allocate registers
  let allocator = LinearScanAllocator::new(
    allocatable_scratch_regs(),
    aapcs64_arg_fprs(),
  )
  let alloc_result = allocator.allocate(func, liveness)

  // f5 should get assignment (v4 is dead code, so it might not get assigned)
  inspect(alloc_result.assignments.get(f5.id) is Some(_), content="true")

  // Verify f5 got the right register class
  match alloc_result.assignments.get(f5.id) {
    Some(preg) => {
      let class_name = match preg.class {
        Int => "Int"
        Float32 | Float64 => "Float"
      }
      inspect(class_name, content="Float")
    }
    None => ()
  }

  // The CRITICAL question: when both block2 and block3 define f5,
  // do they both write to the SAME physical register?
  // If not, block1 will see garbage in one of the paths!
  //
  // Apply allocation to see the final code
  let allocated_func = apply_allocation(func, alloc_result)

  // Check that block2 and block3 both define f5 to the same preg
  let block2_last = allocated_func.blocks[2].insts.last().unwrap()
  let block3_last = allocated_func.blocks[3].insts.last().unwrap()

  // Both should be Move instructions defining the same physical register
  match (block2_last.defs.get(0), block3_last.defs.get(0)) {
    (Some(def2), Some(def3)) =>
      match (def2.reg, def3.reg) {
        (Physical(preg2), Physical(preg3)) => {
          // They should be THE SAME register!
          let same_reg = preg2.index == preg3.index &&
            reg_class_eq(preg2.class, preg3.class)
          inspect(same_reg, content="true")
        }
        _ => inspect(false, content="true")
      }
    _ => inspect(false, content="true")
  }
}

///|
test "liveness: complete output for linear function" {
  // Test that shows complete liveness analysis output
  // A simple linear function: add(a, b) -> (a + b) * 2
  let func = VCodeFunction::new("linear")
  let a = func.add_param(Int)
  let b = func.add_param(Int)
  func.add_result(Int)
  let block = func.new_block()

  // v2 = add v0, v1
  let add_inst = VCodeInst::new(Add)
  let sum = func.new_vreg(Int)
  add_inst.add_def({ reg: Virtual(sum) })
  add_inst.add_use(Virtual(a))
  add_inst.add_use(Virtual(b))
  block.add_inst(add_inst)

  // v3 = ldi 2
  let const_inst = VCodeInst::new(LoadConst(2L))
  let two = func.new_vreg(Int)
  const_inst.add_def({ reg: Virtual(two) })
  block.add_inst(const_inst)

  // v4 = mul v2, v3
  let mul_inst = VCodeInst::new(Mul)
  let result = func.new_vreg(Int)
  mul_inst.add_def({ reg: Virtual(result) })
  mul_inst.add_use(Virtual(sum))
  mul_inst.add_use(Virtual(two))
  block.add_inst(mul_inst)

  // ret v4
  block.set_terminator(Return([Virtual(result)]))

  // Compute liveness
  let liveness = compute_liveness(func)

  // Show complete debug output
  let debug_output = debug_liveness(liveness)
  inspect(
    debug_output,
    content=(
      #|=== Liveness Debug ===
      #|Use-Def Chains:
      #|  v0: def=Some((0:-1a)), uses=[(0:0b)]
      #|  v1: def=Some((0:-1a)), uses=[(0:0b)]
      #|  v2: def=Some((0:0a)), uses=[(0:2b)]
      #|  v3: def=Some((0:1a)), uses=[(0:2b)]
      #|  v4: def=Some((0:2a)), uses=[(0:3b)]
      #|
      #|Live-in/out:
      #|  block0: in=[0, 1], out=[]
      #|
      #|Intervals:
      #|  v0: (0:-1a) - (0:0b)
      #|  v1: (0:-1a) - (0:0b)
      #|  v2: (0:0a) - (0:2b)
      #|  v3: (0:1a) - (0:2b)
      #|  v4: (0:2a) - (0:3b)
      #|
    ),
  )
}

///|
test "liveness: complete output for diamond CFG" {
  // Diamond control flow: if-else that merges
  // block0:
  //   v0 = param (condition)
  //   v1 = ldi 10
  //   v2 = ldi 20
  //   branch v0, block1, block2
  // block1:
  //   v3 = add v1, v1
  //   jump block3
  // block2:
  //   v3 = add v2, v2
  //   jump block3
  // block3:
  //   ret v3

  let func = VCodeFunction::new("diamond")
  let cond = func.add_param(Int)
  func.add_result(Int)
  let v1 = func.new_vreg(Int)
  let v2 = func.new_vreg(Int)
  let v3 = func.new_vreg(Int)
  let block0 = func.new_block()
  let block1 = func.new_block()
  let block2 = func.new_block()
  let block3 = func.new_block()

  // block0
  let inst1 = VCodeInst::new(LoadConst(10L))
  inst1.add_def({ reg: Virtual(v1) })
  block0.add_inst(inst1)
  let inst2 = VCodeInst::new(LoadConst(20L))
  inst2.add_def({ reg: Virtual(v2) })
  block0.add_inst(inst2)
  block0.set_terminator(Branch(Virtual(cond), block1.id, block2.id))

  // block1: v3 = add v1, v1
  let add1 = VCodeInst::new(Add)
  add1.add_use(Virtual(v1))
  add1.add_use(Virtual(v1))
  add1.add_def({ reg: Virtual(v3) })
  block1.add_inst(add1)
  block1.set_terminator(Jump(block3.id))

  // block2: v3 = add v2, v2
  let add2 = VCodeInst::new(Add)
  add2.add_use(Virtual(v2))
  add2.add_use(Virtual(v2))
  add2.add_def({ reg: Virtual(v3) })
  block2.add_inst(add2)
  block2.set_terminator(Jump(block3.id))

  // block3: ret v3
  block3.set_terminator(Return([Virtual(v3)]))
  let liveness = compute_liveness(func)
  let debug_output = debug_liveness(liveness)
  inspect(
    debug_output,
    content=(
      #|=== Liveness Debug ===
      #|Use-Def Chains:
      #|  v0: def=Some((0:-1a)), uses=[(0:2b)]
      #|  v1: def=Some((0:0a)), uses=[(1:0b), (1:0b)]
      #|  v2: def=Some((0:1a)), uses=[(2:0b), (2:0b)]
      #|  v3: def=Some((2:0a)), uses=[(3:0b)]
      #|
      #|Live-in/out:
      #|  block0: in=[0], out=[1, 2]
      #|  block1: in=[1], out=[3]
      #|  block2: in=[2], out=[3]
      #|  block3: in=[3], out=[]
      #|
      #|Intervals:
      #|  v0: (0:-1a) - (0:2b)
      #|  v1: (0:0a) - (1:0b)
      #|  v2: (0:1a) - (2:0b)
      #|  v3: (2:0a) - (3:0b)
      #|
    ),
  )
}

///|
test "regalloc: complete allocation output for simple function" {
  // Show full allocation result for a simple function
  let func = VCodeFunction::new("alloc_demo")
  let a = func.add_param(Int)
  let b = func.add_param(Int)
  func.add_result(Int)
  let block = func.new_block()

  // v2 = add v0, v1
  let add_inst = VCodeInst::new(Add)
  let result = func.new_vreg(Int)
  add_inst.add_def({ reg: Virtual(result) })
  add_inst.add_use(Virtual(a))
  add_inst.add_use(Virtual(b))
  block.add_inst(add_inst)

  // ret v2
  block.set_terminator(Return([Virtual(result)]))

  // Show VCode before allocation
  inspect(
    func.print(),
    content=(
      #|vcode alloc_demo(v0:int, v1:int) -> int {
      #|block0:
      #|    v2 = add v0, v1
      #|    ret v2
      #|}
      #|
    ),
  )

  // Allocate with limited registers
  let int_regs = [
    { index: 8, class: Int },
    { index: 19, class: Int },
    { index: 23, class: Int },
  ]
  let float_regs : Array[PReg] = []
  let liveness = compute_liveness(func)
  let allocator = LinearScanAllocator::new(int_regs, float_regs)
  let alloc_result = allocator.allocate(func, liveness)

  // Show assignments
  let mut assignments_str = ""
  let assignments_arr : Array[(Int, PReg)] = []
  for entry in alloc_result.assignments {
    assignments_arr.push(entry)
  }
  assignments_arr.sort_by(fn(a, b) { a.0 - b.0 })
  for entry in assignments_arr {
    let (vreg_id, preg) = entry
    assignments_str = assignments_str + "v\{vreg_id} -> \{preg}\n"
  }
  inspect(
    assignments_str,
    content=(
      #|v0 -> x3
      #|v1 -> x4
      #|v2 -> x8
      #|
    ),
  )

  // Apply and show final code
  let allocated = apply_allocation(func, alloc_result)
  inspect(
    allocated.print(),
    content=(
      #|vcode alloc_demo(v0:int, v1:int) -> int {
      #|block0:
      #|    x8 = add x3, x4
      #|    ret x8
      #|}
      #|
    ),
  )
}

///|
test "regalloc: same instruction use-def conflict" {
  // Test the critical fix: a use and def in the same instruction
  // must not share the same physical register
  //
  // v0 = ldi 10
  // v1 = add v0, v0  ; v0 used, v1 defined - must be different registers!

  let func = VCodeFunction::new("same_inst_conflict")
  func.add_result(Int)
  let block = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)

  // v0 = ldi 10
  let load_inst = VCodeInst::new(LoadConst(10L))
  load_inst.add_def({ reg: Virtual(v0) })
  block.add_inst(load_inst)

  // v1 = add v0, v0
  let add_inst = VCodeInst::new(Add)
  add_inst.add_use(Virtual(v0))
  add_inst.add_use(Virtual(v0))
  add_inst.add_def({ reg: Virtual(v1) })
  block.add_inst(add_inst)

  // ret v1
  block.set_terminator(Return([Virtual(v1)]))

  // Show liveness - v0 ends at (0:1b) and v1 starts at (0:1a)
  let liveness = compute_liveness(func)
  let debug_output = debug_liveness(liveness)
  inspect(
    debug_output,
    content=(
      #|=== Liveness Debug ===
      #|Use-Def Chains:
      #|  v0: def=Some((0:0a)), uses=[(0:1b), (0:1b)]
      #|  v1: def=Some((0:1a)), uses=[(0:2b)]
      #|
      #|Live-in/out:
      #|  block0: in=[], out=[]
      #|
      #|Intervals:
      #|  v0: (0:0a) - (0:1b)
      #|  v1: (0:1a) - (0:2b)
      #|
    ),
  )

  // Allocate with only ONE register - this forces the conflict check
  let int_regs = [{ index: 8, class: Int }]
  let float_regs : Array[PReg] = []
  let allocator = LinearScanAllocator::new(int_regs, float_regs)
  let alloc_result = allocator.allocate(func, liveness)

  // With only 1 register and same-instruction conflict detection,
  // one vreg MUST be spilled
  inspect(alloc_result.num_spill_slots > 0, content="true")
}

///|
test "regalloc: interval extension across blocks" {
  // Test that intervals extend correctly when a value is live across blocks
  //
  // block0:
  //   v0 = ldi 10
  //   jump block1
  // block1:
  //   v1 = add v0, v0  ; v0 must be live here
  //   ret v1

  let func = VCodeFunction::new("cross_block")
  func.add_result(Int)
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let block0 = func.new_block()
  let block1 = func.new_block()

  // block0
  let load_inst = VCodeInst::new(LoadConst(10L))
  load_inst.add_def({ reg: Virtual(v0) })
  block0.add_inst(load_inst)
  block0.set_terminator(Jump(block1.id))

  // block1
  let add_inst = VCodeInst::new(Add)
  add_inst.add_use(Virtual(v0))
  add_inst.add_use(Virtual(v0))
  add_inst.add_def({ reg: Virtual(v1) })
  block1.add_inst(add_inst)
  block1.set_terminator(Return([Virtual(v1)]))
  let liveness = compute_liveness(func)

  // v0 should be live-out of block0 and live-in to block1
  inspect(liveness.live_out[0].contains(v0.id), content="true")
  inspect(liveness.live_in[1].contains(v0.id), content="true")

  // Show the full debug output
  let debug_output = debug_liveness(liveness)
  inspect(
    debug_output,
    content=(
      #|=== Liveness Debug ===
      #|Use-Def Chains:
      #|  v0: def=Some((0:0a)), uses=[(1:0b), (1:0b)]
      #|  v1: def=Some((1:0a)), uses=[(1:1b)]
      #|
      #|Live-in/out:
      #|  block0: in=[], out=[0]
      #|  block1: in=[0], out=[]
      #|
      #|Intervals:
      #|  v0: (0:0a) - (1:0b)
      #|  v1: (1:0a) - (1:1b)
      #|
    ),
  )
}

///|
test "regalloc: float and int mixed allocation" {
  // Test that float and int registers are allocated independently
  //
  // v0 = ldi 10       ; int
  // f1 = ldf 3.14     ; float
  // v2 = add v0, v0   ; int
  // f3 = fadd f1, f1  ; float
  // ret f3

  let func = VCodeFunction::new("mixed")
  func.add_result(Float64)
  let block = func.new_block()
  let v0 = func.new_vreg(Int)
  let f1 = func.new_vreg(Float64)
  let v2 = func.new_vreg(Int)
  let f3 = func.new_vreg(Float64)

  // v0 = ldi 10
  let inst0 = VCodeInst::new(LoadConst(10L))
  inst0.add_def({ reg: Virtual(v0) })
  block.add_inst(inst0)

  // f1 = ldf 3.14
  let inst1 = VCodeInst::new(LoadConstF64(3.14.reinterpret_as_int64()))
  inst1.add_def({ reg: Virtual(f1) })
  block.add_inst(inst1)

  // v2 = add v0, v0
  let inst2 = VCodeInst::new(Add)
  inst2.add_use(Virtual(v0))
  inst2.add_use(Virtual(v0))
  inst2.add_def({ reg: Virtual(v2) })
  block.add_inst(inst2)

  // f3 = fadd f1, f1
  let inst3 = VCodeInst::new(FAdd)
  inst3.add_use(Virtual(f1))
  inst3.add_use(Virtual(f1))
  inst3.add_def({ reg: Virtual(f3) })
  block.add_inst(inst3)

  // ret f3
  block.set_terminator(Return([Virtual(f3)]))

  // Show VCode before allocation
  inspect(
    func.print(),
    content=(
      #|vcode mixed() -> float {
      #|block0:
      #|    v0 = ldi 10
      #|    f1 = ldf 3.14
      #|    v2 = add v0, v0
      #|    f3 = fadd f1, f1
      #|    ret f3
      #|}
      #|
    ),
  )

  // Allocate with separate int and float registers
  // Need 2 int regs (v0 live until v2 defined) and 2 float regs (f1 live until f3 defined)
  let int_regs = [{ index: 8, class: Int }, { index: 19, class: Int }]
  let float_regs = [{ index: 0, class: Float64 }, { index: 1, class: Float64 }]
  let liveness = compute_liveness(func)
  let allocator = LinearScanAllocator::new(int_regs, float_regs)
  let alloc_result = allocator.allocate(func, liveness)

  // No spills should be needed
  inspect(alloc_result.num_spill_slots, content="0")

  // Apply and show final code
  let allocated = apply_allocation(func, alloc_result)

  // Int regs should use x8/x19, float regs should use d0/d1
  // Due to same-instruction conflict fix:
  // - v0 and v2 CANNOT share x8 because in "v2 = add v0, v0", v0 is used and v2 is defined
  // - f1 and f3 CANNOT share d0 because in "f3 = fadd f1, f1", f1 is used and f3 is defined
  inspect(
    allocated.print(),
    content=(
      #|vcode mixed() -> float {
      #|block0:
      #|    x8 = ldi 10
      #|    d0 = ldf 3.14
      #|    x19 = add x8, x8
      #|    d1 = fadd d0, d0
      #|    ret d1
      #|}
      #|
    ),
  )
}

///|
test "regalloc: spill and reload complete flow" {
  // Test complete spill/reload flow with inspection of generated code
  //
  // v0 = ldi 1
  // v1 = ldi 2
  // v2 = ldi 3
  // v3 = add v0, v1  ; all three must be live here
  // v4 = add v3, v2
  // ret v4

  let func = VCodeFunction::new("spill_flow")
  func.add_result(Int)
  let block = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let v2 = func.new_vreg(Int)
  let v3 = func.new_vreg(Int)
  let v4 = func.new_vreg(Int)
  let inst0 = VCodeInst::new(LoadConst(1L))
  inst0.add_def({ reg: Virtual(v0) })
  block.add_inst(inst0)
  let inst1 = VCodeInst::new(LoadConst(2L))
  inst1.add_def({ reg: Virtual(v1) })
  block.add_inst(inst1)
  let inst2 = VCodeInst::new(LoadConst(3L))
  inst2.add_def({ reg: Virtual(v2) })
  block.add_inst(inst2)
  let inst3 = VCodeInst::new(Add)
  inst3.add_use(Virtual(v0))
  inst3.add_use(Virtual(v1))
  inst3.add_def({ reg: Virtual(v3) })
  block.add_inst(inst3)
  let inst4 = VCodeInst::new(Add)
  inst4.add_use(Virtual(v3))
  inst4.add_use(Virtual(v2))
  inst4.add_def({ reg: Virtual(v4) })
  block.add_inst(inst4)
  block.set_terminator(Return([Virtual(v4)]))

  // Show original VCode
  inspect(
    func.print(),
    content=(
      #|vcode spill_flow() -> int {
      #|block0:
      #|    v0 = ldi 1
      #|    v1 = ldi 2
      #|    v2 = ldi 3
      #|    v3 = add v0, v1
      #|    v4 = add v3, v2
      #|    ret v4
      #|}
      #|
    ),
  )

  // Only 2 registers - must spill at least one
  let int_regs = [{ index: 8, class: Int }, { index: 19, class: Int }]
  let float_regs : Array[PReg] = []
  let liveness = compute_liveness(func)
  let allocator = LinearScanAllocator::new(int_regs, float_regs)
  let alloc_result = allocator.allocate(func, liveness)

  // Should have spills
  inspect(alloc_result.num_spill_slots > 0, content="true")

  // Show allocated code with spill/reload instructions
  let allocated = apply_allocation(func, alloc_result)
  // The exact output depends on spill decisions, but should have stack_load/stack_store
  let output = allocated.print()
  inspect(output.contains("stack_"), content="true")
}

///|
test "regalloc: br_table pattern with 4 targets" {
  // Simulate the exact pattern from f32_br_2locals.wast
  // Multiple mutually exclusive blocks all defining same vregs to pass to common target
  let func = VCodeFunction::new("test_br_table_pattern")
  let v0 = func.new_vreg(Int) // selector
  let f1 = func.new_vreg(Float64) // constant 1
  let f2 = func.new_vreg(Float64) // constant 2

  // Common target block parameters
  let v_target = func.new_vreg(Int)
  let f_target1 = func.new_vreg(Float64)
  let f_target2 = func.new_vreg(Float64)
  let block0 = func.new_block()
  let block_target = func.new_block()
  let block_case0 = func.new_block()
  let block_case1 = func.new_block()
  let block_case2 = func.new_block()
  let block_case3 = func.new_block()

  // block0: load constants
  let inst0 = VCodeInst::new(LoadConst(0L))
  inst0.add_def({ reg: Virtual(v0) })
  block0.add_inst(inst0)
  let inst1 = VCodeInst::new(LoadConstF32(0x41200000)) // 10.0
  inst1.add_def({ reg: Virtual(f1) })
  block0.add_inst(inst1)
  let inst2 = VCodeInst::new(LoadConstF32(0x41A00000)) // 20.0
  inst2.add_def({ reg: Virtual(f2) })
  block0.add_inst(inst2)
  block0.set_terminator(Branch(Virtual(v0), block_case0.id, block_case1.id))

  // block_target with params
  block_target.params.push(v_target)
  block_target.params.push(f_target1)
  block_target.params.push(f_target2)
  block_target.set_terminator(Return([Virtual(f_target1)]))

  // Each case block moves values to target params
  // case0
  {
    let mov0 = VCodeInst::new(Move)
    mov0.add_use(Virtual(v0))
    mov0.add_def({ reg: Virtual(v_target) })
    block_case0.add_inst(mov0)
    let mov1 = VCodeInst::new(Move)
    mov1.add_use(Virtual(f1))
    mov1.add_def({ reg: Virtual(f_target1) })
    block_case0.add_inst(mov1)
    let mov2 = VCodeInst::new(Move)
    mov2.add_use(Virtual(f2))
    mov2.add_def({ reg: Virtual(f_target2) })
    block_case0.add_inst(mov2)
    block_case0.set_terminator(Jump(block_target.id))
  }

  // case1
  {
    let mov0 = VCodeInst::new(Move)
    mov0.add_use(Virtual(v0))
    mov0.add_def({ reg: Virtual(v_target) })
    block_case1.add_inst(mov0)
    let mov1 = VCodeInst::new(Move)
    mov1.add_use(Virtual(f1))
    mov1.add_def({ reg: Virtual(f_target1) })
    block_case1.add_inst(mov1)
    let mov2 = VCodeInst::new(Move)
    mov2.add_use(Virtual(f2))
    mov2.add_def({ reg: Virtual(f_target2) })
    block_case1.add_inst(mov2)
    block_case1.set_terminator(Jump(block_target.id))
  }

  // case2
  {
    let mov0 = VCodeInst::new(Move)
    mov0.add_use(Virtual(v0))
    mov0.add_def({ reg: Virtual(v_target) })
    block_case2.add_inst(mov0)
    let mov1 = VCodeInst::new(Move)
    mov1.add_use(Virtual(f1))
    mov1.add_def({ reg: Virtual(f_target1) })
    block_case2.add_inst(mov1)
    let mov2 = VCodeInst::new(Move)
    mov2.add_use(Virtual(f2))
    mov2.add_def({ reg: Virtual(f_target2) })
    block_case2.add_inst(mov2)
    block_case2.set_terminator(Jump(block_target.id))
  }

  // case3
  {
    let mov0 = VCodeInst::new(Move)
    mov0.add_use(Virtual(v0))
    mov0.add_def({ reg: Virtual(v_target) })
    block_case3.add_inst(mov0)
    let mov1 = VCodeInst::new(Move)
    mov1.add_use(Virtual(f1))
    mov1.add_def({ reg: Virtual(f_target1) })
    block_case3.add_inst(mov1)
    let mov2 = VCodeInst::new(Move)
    mov2.add_use(Virtual(f2))
    mov2.add_def({ reg: Virtual(f_target2) })
    block_case3.add_inst(mov2)
    block_case3.set_terminator(Jump(block_target.id))
  }

  // Compute liveness and allocate
  let liveness = compute_liveness(func)

  // CRITICAL CHECK: f_target1 is defined in 4 different blocks
  // They MUST all get assigned to the SAME physical register!
  let allocator = LinearScanAllocator::new(
    allocatable_scratch_regs(),
    aapcs64_arg_fprs(),
  )
  let alloc_result = allocator.allocate(func, liveness)

  // Apply allocation
  let allocated_func = apply_allocation(func, alloc_result)

  // Verify all 4 case blocks define f_target1 to the same physical register
  let pregs : Array[PReg?] = []
  for i in 2..<6 {
    // blocks 2-5 are case0-case3
    let block = allocated_func.blocks[i]
    if block.insts.length() >= 2 {
      let mov1 = block.insts[1] // second mov (f_target1)
      match mov1.defs.get(0) {
        Some(def) =>
          match def.reg {
            Physical(preg) => pregs.push(Some(preg))
            _ => pregs.push(None)
          }
        None => pregs.push(None)
      }
    }
  }

  // All should be Some and all should be equal
  // They should all be the same!
  if pregs.length() == 4 {
    match (pregs[0], pregs[1], pregs[2], pregs[3]) {
      (Some(p0), Some(p1), Some(p2), Some(p3)) => {
        let all_same = p0.index == p1.index &&
          p1.index == p2.index &&
          p2.index == p3.index &&
          reg_class_eq(p0.class, p1.class) &&
          reg_class_eq(p1.class, p2.class) &&
          reg_class_eq(p2.class, p3.class)
        inspect(all_same, content="true")
      }
      _ => inspect(false, content="true")
    }
  }
  inspect(pregs, content="[Some(x8), Some(x8), Some(x8), Some(x8)]")
}
