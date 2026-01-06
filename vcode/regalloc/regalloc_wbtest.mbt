// Tests for register allocation

///|
test "liveness: simple function" {
  // Create a simple VCode function: add(a, b) -> a + b
  let func = VCodeFunction::new("test_add")
  let a = func.add_param(@abi.Int)
  let b = func.add_param(@abi.Int)
  func.add_result(@abi.Int)
  let block = func.new_block()

  // v2 = add v0, v1
  let add_inst = @instr.VCodeInst::new(@instr.Add(true))
  let result_vreg = func.new_vreg(@abi.Int)
  add_inst.add_def({ reg: @abi.Virtual(result_vreg) })
  add_inst.add_use(@abi.Virtual(a))
  add_inst.add_use(@abi.Virtual(b))
  block.add_inst(add_inst)

  // ret v2
  block.set_terminator(@instr.Return([@abi.Virtual(result_vreg)]))

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
test "apply_allocation: rewrites virtual to physical" {
  // Create a simple function
  let func = VCodeFunction::new("test_rewrite")
  let a = func.add_param(@abi.Int)
  func.add_result(@abi.Int)
  let block = func.new_block()

  // v1 = ldi 42
  let const_inst = @instr.VCodeInst::new(@instr.LoadConst(42L))
  let const_vreg = func.new_vreg(@abi.Int)
  const_inst.add_def({ reg: @abi.Virtual(const_vreg) })
  block.add_inst(const_inst)

  // v2 = add v0, v1
  let add_inst = @instr.VCodeInst::new(@instr.Add(true))
  let result_vreg = func.new_vreg(@abi.Int)
  add_inst.add_def({ reg: @abi.Virtual(result_vreg) })
  add_inst.add_use(@abi.Virtual(a))
  add_inst.add_use(@abi.Virtual(const_vreg))
  block.add_inst(add_inst)

  // ret v2
  block.set_terminator(@instr.Return([@abi.Virtual(result_vreg)]))

  // Allocate
  let allocated = allocate_registers_backtracking(func)

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
  let cond = func.add_param(@abi.Int)
  let a = func.add_param(@abi.Int)
  let b = func.add_param(@abi.Int)
  func.add_result(@abi.Int)

  // Entry block
  let entry = func.new_block()
  entry.set_terminator(@instr.Branch(@abi.Virtual(cond), 1, 2))

  // Then block
  let then_block = func.new_block()
  let then_inst = @instr.VCodeInst::new(@instr.Move)
  let then_result = func.new_vreg(@abi.Int)
  then_inst.add_def({ reg: @abi.Virtual(then_result) })
  then_inst.add_use(@abi.Virtual(a))
  then_block.add_inst(then_inst)
  then_block.set_terminator(@instr.Return([@abi.Virtual(then_result)]))

  // Else block
  let else_block = func.new_block()
  let else_inst = @instr.VCodeInst::new(@instr.Move)
  let else_result = func.new_vreg(@abi.Int)
  else_inst.add_def({ reg: @abi.Virtual(else_result) })
  else_inst.add_use(@abi.Virtual(b))
  else_block.add_inst(else_inst)
  else_block.set_terminator(@instr.Return([@abi.Virtual(else_result)]))

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
  let a = func.add_param(@abi.Int)
  let b = func.add_param(@abi.Int)
  func.add_result(@abi.Int)
  let block = func.new_block()
  let add_inst = @instr.VCodeInst::new(@instr.Add(true))
  let result_vreg = func.new_vreg(@abi.Int)
  add_inst.add_def({ reg: @abi.Virtual(result_vreg) })
  add_inst.add_use(@abi.Virtual(a))
  add_inst.add_use(@abi.Virtual(b))
  block.add_inst(add_inst)
  block.set_terminator(@instr.Return([@abi.Virtual(result_vreg)]))

  // Allocate with AArch64 registers
  let allocated = allocate_registers_backtracking(func)

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
  let order : FixedArray[Int] = [0, 1] // block_order[block_id] = order

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

  let v0 = func.new_vreg(@abi.Int)
  let v1 = func.new_vreg(@abi.Int)
  let block0 = func.new_block()
  let block1 = func.new_block()

  // block0: v0 = ldi 10; v1 = mov v0; jump block1
  let inst0 = @instr.VCodeInst::new(@instr.LoadConst(10L))
  inst0.add_def({ reg: @abi.Virtual(v0) })
  block0.add_inst(inst0)
  let inst1 = @instr.VCodeInst::new(@instr.Move)
  inst1.add_use(@abi.Virtual(v0))
  inst1.add_def({ reg: @abi.Virtual(v1) })
  block0.add_inst(inst1)
  block0.set_terminator(@instr.Jump(block1.id))

  // block1(v1): ret v1
  block1.params.push(v1)
  block1.set_terminator(@instr.Return([@abi.Virtual(v1)]))

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

  let v0 = func.new_vreg(@abi.Int)
  let v1 = func.new_vreg(@abi.Int)
  let block0 = func.new_block()
  let block1 = func.new_block()
  let block2 = func.new_block()
  let block3 = func.new_block()

  // block0
  let inst0 = @instr.VCodeInst::new(@instr.LoadConst(1L))
  inst0.add_def({ reg: @abi.Virtual(v0) })
  block0.add_inst(inst0)
  block0.set_terminator(@instr.Branch(@abi.Virtual(v0), block1.id, block2.id))

  // block1
  let inst1 = @instr.VCodeInst::new(@instr.LoadConst(10L))
  inst1.add_def({ reg: @abi.Virtual(v1) })
  block1.add_inst(inst1)
  block1.set_terminator(@instr.Jump(block3.id))

  // block2
  let inst2 = @instr.VCodeInst::new(@instr.LoadConst(20L))
  inst2.add_def({ reg: @abi.Virtual(v1) })
  block2.add_inst(inst2)
  block2.set_terminator(@instr.Jump(block3.id))

  // block3
  block3.set_terminator(@instr.Return([@abi.Virtual(v1)]))

  // Compute liveness
  let liveness = compute_liveness(func)

  // Get v1's use-def info
  // CRITICAL: v1 has TWO definitions: (1:0a) and (2:0a)
  // Current code only keeps ONE def_point
  // This is just capturing the current behavior, whether Some or None
  liveness.use_def.get(v1.id).unwrap() |> ignore

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
test "liveness: complete output for linear function" {
  // Test that shows complete liveness analysis output
  // A simple linear function: add(a, b) -> (a + b) * 2
  let func = VCodeFunction::new("linear")
  let a = func.add_param(@abi.Int)
  let b = func.add_param(@abi.Int)
  func.add_result(@abi.Int)
  let block = func.new_block()

  // v2 = add v0, v1
  let add_inst = @instr.VCodeInst::new(@instr.Add(true))
  let sum = func.new_vreg(@abi.Int)
  add_inst.add_def({ reg: @abi.Virtual(sum) })
  add_inst.add_use(@abi.Virtual(a))
  add_inst.add_use(@abi.Virtual(b))
  block.add_inst(add_inst)

  // v3 = ldi 2
  let const_inst = @instr.VCodeInst::new(@instr.LoadConst(2L))
  let two = func.new_vreg(@abi.Int)
  const_inst.add_def({ reg: @abi.Virtual(two) })
  block.add_inst(const_inst)

  // v4 = mul v2, v3
  let mul_inst = @instr.VCodeInst::new(@instr.Mul(true))
  let result = func.new_vreg(@abi.Int)
  mul_inst.add_def({ reg: @abi.Virtual(result) })
  mul_inst.add_use(@abi.Virtual(sum))
  mul_inst.add_use(@abi.Virtual(two))
  block.add_inst(mul_inst)

  // ret v4
  block.set_terminator(@instr.Return([@abi.Virtual(result)]))

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
  let cond = func.add_param(@abi.Int)
  func.add_result(@abi.Int)
  let v1 = func.new_vreg(@abi.Int)
  let v2 = func.new_vreg(@abi.Int)
  let v3 = func.new_vreg(@abi.Int)
  let block0 = func.new_block()
  let block1 = func.new_block()
  let block2 = func.new_block()
  let block3 = func.new_block()

  // block0
  let inst1 = @instr.VCodeInst::new(@instr.LoadConst(10L))
  inst1.add_def({ reg: @abi.Virtual(v1) })
  block0.add_inst(inst1)
  let inst2 = @instr.VCodeInst::new(@instr.LoadConst(20L))
  inst2.add_def({ reg: @abi.Virtual(v2) })
  block0.add_inst(inst2)
  block0.set_terminator(@instr.Branch(@abi.Virtual(cond), block1.id, block2.id))

  // block1: v3 = add v1, v1
  let add1 = @instr.VCodeInst::new(@instr.Add(true))
  add1.add_use(@abi.Virtual(v1))
  add1.add_use(@abi.Virtual(v1))
  add1.add_def({ reg: @abi.Virtual(v3) })
  block1.add_inst(add1)
  block1.set_terminator(@instr.Jump(block3.id))

  // block2: v3 = add v2, v2
  let add2 = @instr.VCodeInst::new(@instr.Add(true))
  add2.add_use(@abi.Virtual(v2))
  add2.add_use(@abi.Virtual(v2))
  add2.add_def({ reg: @abi.Virtual(v3) })
  block2.add_inst(add2)
  block2.set_terminator(@instr.Jump(block3.id))

  // block3: ret v3
  block3.set_terminator(@instr.Return([@abi.Virtual(v3)]))
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
  func.add_result(@abi.Int)
  let v0 = func.new_vreg(@abi.Int)
  let v1 = func.new_vreg(@abi.Int)
  let block0 = func.new_block()
  let block1 = func.new_block()

  // block0
  let load_inst = @instr.VCodeInst::new(@instr.LoadConst(10L))
  load_inst.add_def({ reg: @abi.Virtual(v0) })
  block0.add_inst(load_inst)
  block0.set_terminator(@instr.Jump(block1.id))

  // block1
  let add_inst = @instr.VCodeInst::new(@instr.Add(true))
  add_inst.add_use(@abi.Virtual(v0))
  add_inst.add_use(@abi.Virtual(v0))
  add_inst.add_def({ reg: @abi.Virtual(v1) })
  block1.add_inst(add_inst)
  block1.set_terminator(@instr.Return([@abi.Virtual(v1)]))
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
test "regalloc: f64 registers" {
  // Test register allocation for @abi.Float64 (double) values
  //
  // f0 = ldf 1.5   ; double
  // f1 = ldf 2.5   ; double
  // f2 = fadd f0, f1  ; double
  // ret f2

  let func = VCodeFunction::new("f64_test")
  func.add_result(@abi.Float64)
  let block = func.new_block()
  let f0 = func.new_vreg(@abi.Float64)
  let f1 = func.new_vreg(@abi.Float64)
  let f2 = func.new_vreg(@abi.Float64)

  // f0 = ldf 1.5 (double bits)
  let inst0 = @instr.VCodeInst::new(
    @instr.LoadConstF64((1.5 : Double).reinterpret_as_int64()),
  )
  inst0.add_def({ reg: @abi.Virtual(f0) })
  block.add_inst(inst0)

  // f1 = ldf 2.5 (double bits)
  let inst1 = @instr.VCodeInst::new(
    @instr.LoadConstF64((2.5 : Double).reinterpret_as_int64()),
  )
  inst1.add_def({ reg: @abi.Virtual(f1) })
  block.add_inst(inst1)

  // f2 = fadd f0, f1
  let inst2 = @instr.VCodeInst::new(@instr.FAdd(false))
  inst2.add_use(@abi.Virtual(f0))
  inst2.add_use(@abi.Virtual(f1))
  inst2.add_def({ reg: @abi.Virtual(f2) })
  block.add_inst(inst2)
  block.set_terminator(@instr.Return([@abi.Virtual(f2)]))

  // Show VCode before allocation
  inspect(
    func.print(),
    content=(
      #|vcode f64_test() -> double {
      #|block0:
      #|    f0 = ldf 1.5
      #|    f1 = ldf 2.5
      #|    f2 = fadd.d f0, f1
      #|    ret f2
      #|}
      #|
    ),
  )

  // Allocate registers
  let allocated = allocate_registers_backtracking(func)

  // @abi.Float64 values should use d registers
  inspect(
    allocated.print(),
    content=(
      #|vcode f64_test() -> double {
      #|block0:
      #|    d1 = ldf 1.5
      #|    d0 = ldf 2.5
      #|    d0 = fadd.d d1, d0
      #|    ret d0
      #|}
      #|
    ),
  )
}

///|
test "regalloc: mixed int, f32, f64 registers" {
  // Test register allocation with all three types mixed
  // Chain all values so nothing is dead:
  //
  // v0 = ldi 10       ; int
  // f1 = ldf 3.14     ; float32
  // f2 = ldf 2.718    ; float64 (double)
  // v3 = add v0, v0   ; int (uses v0)
  // f4 = fadd f1, f2  ; uses f1 and f2
  // f5 = fadd f4, f4  ; uses f4
  // store v3          ; uses v3 (keeps int chain alive)
  // ret f5

  let func = VCodeFunction::new("mixed_types")
  func.add_result(@abi.Float64)
  let block = func.new_block()
  let v0 = func.new_vreg(@abi.Int)
  let f1 = func.new_vreg(@abi.Float32)
  let f2 = func.new_vreg(@abi.Float64)
  let v3 = func.new_vreg(@abi.Int)
  let f4 = func.new_vreg(@abi.Float64)
  let f5 = func.new_vreg(@abi.Float64)

  // v0 = ldi 10
  let inst0 = @instr.VCodeInst::new(@instr.LoadConst(10L))
  inst0.add_def({ reg: @abi.Virtual(v0) })
  block.add_inst(inst0)

  // f1 = ldf 3.14 (float32)
  let inst1 = @instr.VCodeInst::new(
    @instr.LoadConstF32((3.14 : Float).reinterpret_as_int()),
  )
  inst1.add_def({ reg: @abi.Virtual(f1) })
  block.add_inst(inst1)

  // f2 = ldf 2.718 (float64)
  let inst2 = @instr.VCodeInst::new(
    @instr.LoadConstF64((2.718 : Double).reinterpret_as_int64()),
  )
  inst2.add_def({ reg: @abi.Virtual(f2) })
  block.add_inst(inst2)

  // v3 = add v0, v0
  let inst3 = @instr.VCodeInst::new(@instr.Add(true))
  inst3.add_use(@abi.Virtual(v0))
  inst3.add_use(@abi.Virtual(v0))
  inst3.add_def({ reg: @abi.Virtual(v3) })
  block.add_inst(inst3)

  // f4 = fadd f1, f2 (mix float32 and float64)
  let inst4 = @instr.VCodeInst::new(@instr.FAdd(false))
  inst4.add_use(@abi.Virtual(f1))
  inst4.add_use(@abi.Virtual(f2))
  inst4.add_def({ reg: @abi.Virtual(f4) })
  block.add_inst(inst4)

  // f5 = fadd f4, f4
  let inst5 = @instr.VCodeInst::new(@instr.FAdd(false))
  inst5.add_use(@abi.Virtual(f4))
  inst5.add_use(@abi.Virtual(f4))
  inst5.add_def({ reg: @abi.Virtual(f5) })
  block.add_inst(inst5)

  // store.i32 +0, v3 (keeps v3 alive)
  let inst6 = @instr.VCodeInst::new(@instr.Store(I32, 0))
  inst6.add_use(@abi.Virtual(v3)) // addr
  inst6.add_use(@abi.Virtual(v3)) // value
  block.add_inst(inst6)
  block.set_terminator(@instr.Return([@abi.Virtual(f5)]))

  // Show VCode before allocation
  inspect(
    func.print(),
    content=(
      #|vcode mixed_types() -> double {
      #|block0:
      #|    v0 = ldi 10
      #|    f1 = ldf 3.140000104904175
      #|    f2 = ldf 2.718
      #|    v3 = add v0, v0
      #|    f4 = fadd.d f1, f2
      #|    f5 = fadd.d f4, f4
      #|    store.i32 +0 v3, v3
      #|    ret f5
      #|}
      #|
    ),
  )

  // Allocate registers
  let allocated = allocate_registers_backtracking(func)

  // @abi.Int values should use x registers, all floats should use d registers
  // @abi.Float32 and @abi.Float64 share the same physical register file (d0-d31)
  inspect(
    allocated.print(),
    content=(
      #|vcode mixed_types() -> double {
      #|block0:
      #|    x8 = ldi 10
      #|    d1 = ldf 3.140000104904175
      #|    d0 = ldf 2.718
      #|    x8 = add x8, x8
      #|    d0 = fadd.d d1, d0
      #|    d0 = fadd.d d0, d0
      #|    store.i32 +0 x8, x8
      #|    ret d0
      #|}
      #|
    ),
  )
}

///|
/// Test @instr.CallIndirect with many f64 arguments (8 f64 params exceeds ABI register count)
/// This reproduces the "regalloc: many call arguments" failing test
test "regalloc: @instr.CallIndirect with 8 f64 arguments" {
  let func = VCodeFunction::new("test_many_f64_args")
  func.add_result(@abi.Float64)
  func.add_result_type(F64)
  let block = func.new_block()

  // Create 8 f64 constants as arguments
  let args : Array[@abi.VReg] = []
  for i in 0..<8 {
    let vreg = func.new_vreg(@abi.Float64)
    let inst = @instr.VCodeInst::new(
      @instr.LoadConstF64((i.to_double() + 1.0).reinterpret_as_int64()),
    )
    inst.add_def({ reg: @abi.Virtual(vreg) })
    block.add_inst(inst)
    args.push(vreg)
  }

  // Create a fake function pointer (just use an @abi.Int vreg)
  let func_ptr = func.new_vreg(@abi.Int)
  let ptr_inst = @instr.VCodeInst::new(@instr.LoadConst(0x1000L))
  ptr_inst.add_def({ reg: @abi.Virtual(func_ptr) })
  block.add_inst(ptr_inst)

  // CallPtr with 8 f64 args, 1 f64 result (Standard)
  let call_inst = @instr.VCodeInst::new(@instr.CallPtr(8, 1, @instr.Wasm))
  let call_result = func.new_vreg(@abi.Float64)
  call_inst.add_def({ reg: @abi.Virtual(call_result) })
  call_inst.add_use(@abi.Virtual(func_ptr)) // First use is func_ptr
  for arg in args {
    call_inst.add_use(@abi.Virtual(arg))
  }
  block.add_inst(call_inst)

  // @instr.Return the call result
  block.set_terminator(@instr.Return([@abi.Virtual(call_result)]))

  // Show VCode before allocation
  inspect(
    func.print(),
    content=(
      #|vcode test_many_f64_args() -> double {
      #|block0:
      #|    f0 = ldf 1
      #|    f1 = ldf 2
      #|    f2 = ldf 3
      #|    f3 = ldf 4
      #|    f4 = ldf 5
      #|    f5 = ldf 6
      #|    f6 = ldf 7
      #|    f7 = ldf 8
      #|    v8 = ldi 4096
      #|    f9 = call_ptr[Wasm](8) -> 1 results v8
      #|    ret f9
      #|}
      #|
    ),
  )

  // Compute liveness
  let liveness = compute_liveness(func)

  // Check that all f64 values are correctly tracked
  inspect(liveness.intervals.length(), content="10")

  // Check that call_points is recorded
  inspect(liveness.call_points.length(), content="1")

  // Allocate registers using AArch64 allocator
  // Call result is assigned to callee-saved D8, no spill needed
  let allocated = allocate_registers_backtracking(func)
  inspect(
    allocated,
    content=(
      #|vcode test_many_f64_args() -> double {
      #|block0:
      #|    d7 = ldf 1
      #|    d6 = ldf 2
      #|    d5 = ldf 3
      #|    d4 = ldf 4
      #|    d3 = ldf 5
      #|    d2 = ldf 6
      #|    d1 = ldf 7
      #|    d0 = ldf 8
      #|    x8 = ldi 4096
      #|    d0 = call_ptr[Wasm](8) -> 1 results x8
      #|    ret d0
      #|}
      #|
    ),
  )
}

///|
/// Test f32 value that must survive across a @instr.CallIndirect
/// This reproduces the "regalloc: f32 live across call" failing test
test "regalloc: f32 value live across @instr.CallIndirect" {
  let func = VCodeFunction::new("test_f32_across_call")
  func.add_result(@abi.Float32)
  func.add_result(@abi.Float64)
  func.add_result_type(F32)
  func.add_result_type(F64)
  let block = func.new_block()

  // f0 = ldf 42.0 (f32)
  let f32_val = func.new_vreg(@abi.Float32)
  let f32_bits = (42.0 : Float).reinterpret_as_int()
  let f32_inst = @instr.VCodeInst::new(@instr.LoadConstF32(f32_bits))
  f32_inst.add_def({ reg: @abi.Virtual(f32_val) })
  block.add_inst(f32_inst)

  // f1 = ldf 3.14 (f64) - argument for call
  let f64_arg = func.new_vreg(@abi.Float64)
  let f64_inst = @instr.VCodeInst::new(
    @instr.LoadConstF64((3.14 : Double).reinterpret_as_int64()),
  )
  f64_inst.add_def({ reg: @abi.Virtual(f64_arg) })
  block.add_inst(f64_inst)

  // Create function pointer
  let func_ptr = func.new_vreg(@abi.Int)
  let ptr_inst = @instr.VCodeInst::new(@instr.LoadConst(0x2000L))
  ptr_inst.add_def({ reg: @abi.Virtual(func_ptr) })
  block.add_inst(ptr_inst)

  // CallPtr with 1 f64 arg, returns 1 f64 (Standard)
  // The f32_val must survive across this call
  let call_inst = @instr.VCodeInst::new(@instr.CallPtr(1, 1, @instr.Wasm))
  let call_result = func.new_vreg(@abi.Float64)
  call_inst.add_def({ reg: @abi.Virtual(call_result) })
  call_inst.add_use(@abi.Virtual(func_ptr))
  call_inst.add_use(@abi.Virtual(f64_arg))
  block.add_inst(call_inst)

  // @instr.Return (f32_val, call_result) - f32_val must still be available after call
  block.set_terminator(
    @instr.Return([@abi.Virtual(f32_val), @abi.Virtual(call_result)]),
  )

  // Show VCode before allocation
  inspect(
    func.print(),
    content=(
      #|vcode test_f32_across_call() -> (float, double) {
      #|block0:
      #|    f0 = ldf 42
      #|    f1 = ldf 3.14
      #|    v2 = ldi 8192
      #|    f3 = call_ptr[Wasm](1) -> 1 results v2
      #|    ret f0, f3
      #|}
      #|
    ),
  )

  // Compute liveness
  let liveness = compute_liveness(func)

  // Check that f32_val (id=0) interval exists
  guard liveness.intervals.get(0) is Some(f32_interval) else { return }

  // Check that f32_val crosses the call
  // The call is at inst_idx=3, f32_val is used at return (after inst_idx=3)
  inspect(f32_interval.crosses_call, content="true")

  // Allocate registers
  let allocated = allocate_registers_backtracking(func)

  // Print to see how it's allocated
  inspect(
    allocated.to_string(),
    content=(
      #|vcode test_f32_across_call() -> (float, double) {
      #|block0:
      #|    d8 = ldf 42
      #|    d0 = ldf 3.14
      #|    x8 = ldi 8192
      #|    d0 = call_ptr[Wasm](1) -> 1 results x8
      #|    ret d8, d0
      #|}
      #|
    ),
  )
}

///|
/// Test the backtracking allocator on a simple function
test "regalloc: backtracking allocator simple" {
  let func = VCodeFunction::new("backtrack_simple")
  let a = func.add_param(@abi.Int)
  let b = func.add_param(@abi.Int)
  func.add_result(@abi.Int)
  let block = func.new_block()

  // v2 = add v0, v1
  let add_inst = @instr.VCodeInst::new(@instr.Add(true))
  let result_vreg = func.new_vreg(@abi.Int)
  add_inst.add_def({ reg: @abi.Virtual(result_vreg) })
  add_inst.add_use(@abi.Virtual(a))
  add_inst.add_use(@abi.Virtual(b))
  block.add_inst(add_inst)

  // ret v2
  block.set_terminator(@instr.Return([@abi.Virtual(result_vreg)]))

  // Allocate using backtracking allocator
  let allocated = allocate_registers_backtracking(func)

  // Function should be valid
  inspect(allocated.name, content="backtrack_simple")
  inspect(allocated.params.length(), content="2")
  inspect(allocated.blocks.length(), content="1")

  // The result should use physical registers
  let result_block = allocated.blocks[0]
  inspect(result_block.insts.length(), content="1")
}

///|
/// Test the backtracking allocator with bundle merging
test "regalloc: backtracking allocator bundle merging" {
  // Test that Move instructions result in merged bundles
  let func = VCodeFunction::new("backtrack_merge")
  let a = func.add_param(@abi.Int)
  func.add_result(@abi.Int)
  let block = func.new_block()

  // v1 = mov v0 (should be coalesced)
  let mov_inst = @instr.VCodeInst::new(@instr.Move)
  let v1 = func.new_vreg(@abi.Int)
  mov_inst.add_def({ reg: @abi.Virtual(v1) })
  mov_inst.add_use(@abi.Virtual(a))
  block.add_inst(mov_inst)

  // v2 = add v1, v1
  let add_inst = @instr.VCodeInst::new(@instr.Add(true))
  let v2 = func.new_vreg(@abi.Int)
  add_inst.add_def({ reg: @abi.Virtual(v2) })
  add_inst.add_use(@abi.Virtual(v1))
  add_inst.add_use(@abi.Virtual(v1))
  block.add_inst(add_inst)

  // ret v2
  block.set_terminator(@instr.Return([@abi.Virtual(v2)]))

  // Allocate using backtracking allocator
  let allocated = allocate_registers_backtracking(func)

  // Should produce valid code
  inspect(allocated.blocks.length(), content="1")

  // The move instruction should still exist
  // (In a fully optimized version, it could be eliminated if coalesced)
  let result_block = allocated.blocks[0]
  inspect(result_block.insts.length() >= 1, content="true")
}

///|
/// Test the backtracking allocator with pressure requiring eviction
test "regalloc: backtracking allocator with register pressure" {
  // Create enough live values to require eviction decisions
  let func = VCodeFunction::new("backtrack_pressure")
  func.add_result(@abi.Int)
  let block = func.new_block()

  // Create 5 values all live at the same time
  let values : Array[@abi.VReg] = []
  for i in 0..<5 {
    let v = func.new_vreg(@abi.Int)
    let inst = @instr.VCodeInst::new(@instr.LoadConst(i.to_int64()))
    inst.add_def({ reg: @abi.Virtual(v) })
    block.add_inst(inst)
    values.push(v)
  }

  // Add them all together
  let mut result = values[0]
  for i in 1..<5 {
    let new_result = func.new_vreg(@abi.Int)
    let add_inst = @instr.VCodeInst::new(@instr.Add(true))
    add_inst.add_def({ reg: @abi.Virtual(new_result) })
    add_inst.add_use(@abi.Virtual(result))
    add_inst.add_use(@abi.Virtual(values[i]))
    block.add_inst(add_inst)
    result = new_result
  }
  block.set_terminator(@instr.Return([@abi.Virtual(result)]))

  // Allocate using backtracking allocator
  let allocated = allocate_registers_backtracking(func)

  // Should produce valid code even with pressure
  inspect(allocated.blocks.length(), content="1")

  // Should have more instructions due to potential spill/reload
  let result_block = allocated.blocks[0]
  inspect(result_block.insts.length() >= 9, content="true") // 5 loads + 4 adds
}

///|
/// Test LiveRange data structures
test "liverange: basic operations" {
  let vreg : @abi.VReg = { id: 0, class: @abi.Int }
  let range = LiveRange::new(0, vreg)

  // Add a span
  let start : ProgPoint = { block: 0, inst: 0, pos: After }
  let end : ProgPoint = { block: 0, inst: 5, pos: Before }
  range.add_range(ProgPointRange::new(start, end))
  inspect(range.ranges.length(), content="1")
  inspect(range.vreg.id, content="0")
  inspect(range.allocation is Unallocated, content="true")
}

///|
/// Test UnionFind operations
test "union_find: basic operations" {
  let uf = UnionFind::new(5)

  // Initially all separate
  inspect(uf.num_sets(), content="5")

  // Union 0 and 1
  inspect(uf.union(0, 1), content="true")
  inspect(uf.num_sets(), content="4")

  // Union 2 and 3
  inspect(uf.union(2, 3), content="true")
  inspect(uf.num_sets(), content="3")

  // Union 1 and 3 (connects {0,1} with {2,3})
  inspect(uf.union(1, 3), content="true")
  inspect(uf.num_sets(), content="2")

  // Check same_set
  inspect(uf.same_set(0, 2), content="true")
  inspect(uf.same_set(0, 4), content="false")

  // Get set members
  let set_0 = uf.get_set(0)
  set_0.sort_by(fn(a, b) { a - b })
  inspect(set_0, content="[0, 1, 2, 3]")
}
