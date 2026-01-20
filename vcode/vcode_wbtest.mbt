// Tests for VCode structures

///|
test "simple add function" {
  let builder = VCodeBuilder::new("add")
  let p0 = builder.add_param(Int)
  let p1 = builder.add_param(Int)
  builder.add_result(Int)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let sum = builder.add(p0, p1)
  builder.return_([sum])
  let output = builder.print()
  let expected =
    #|vcode add(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = add v0, v1
    #|    ret v2
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "constants and arithmetic" {
  let builder = VCodeBuilder::new("const_arith")
  builder.add_result(Int)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let c10 = builder.iconst(10L)
  let c20 = builder.iconst(20L)
  let sum = builder.add(c10, c20)
  let c2 = builder.iconst(2L)
  let result = builder.mul(sum, c2)
  builder.return_([result])
  let output = builder.print()
  let expected =
    #|vcode const_arith() -> int {
    #|block0:
    #|    v0 = ldi 10
    #|    v1 = ldi 20
    #|    v2 = add v0, v1
    #|    v3 = ldi 2
    #|    v4 = mul v2, v3
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "conditional branch" {
  let builder = VCodeBuilder::new("max")
  let p0 = builder.add_param(Int)
  let p1 = builder.add_param(Int)
  builder.add_result(Int)
  let entry = builder.create_block()
  let then_block = builder.create_block()
  let else_block = builder.create_block()
  builder.switch_to_block(entry)
  let cmp = builder.cmp(Sgt, p0, p1)
  builder.branch(cmp, then_block, else_block)
  builder.switch_to_block(then_block)
  builder.return_([p0])
  builder.switch_to_block(else_block)
  builder.return_([p1])
  let output = builder.print()
  let expected =
    #|vcode max(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = cmp.sgt v0, v1
    #|    branch v2, block1, block2
    #|block1:
    #|    ret v0
    #|block2:
    #|    ret v1
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "float operations" {
  let builder = VCodeBuilder::new("float_add")
  let p0 = builder.add_param(Float32)
  let p1 = builder.add_param(Float32)
  builder.add_result(Float32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let sum = builder.fadd(p0, p1)
  let c2 = builder.fconst(2.0)
  let result = builder.fmul(sum, c2)
  builder.return_([result])
  let output = builder.print()
  inspect(
    output,
    content=(
      #|vcode float_add(f0:float, f1:float) -> float {
      #|block0:
      #|    f2 = fadd.d f0, f1
      #|    f3 = ldf 2
      #|    f4 = fmul.d f2, f3
      #|    ret f4
      #|}
      #|
    ),
  )
}

///|
test "memory operations" {
  let builder = VCodeBuilder::new("load_store")
  let addr = builder.add_param(Int)
  builder.add_result(Int)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let val = builder.load(I32, addr, 0)
  let one = builder.iconst(1L)
  let result = builder.add(val, one)
  builder.store(I32, addr, result, 4)
  builder.return_([result])
  let output = builder.print()
  let expected =
    #|vcode load_store(v0:int) -> int {
    #|block0:
    #|    v1 = load.i32 +0 v0
    #|    v2 = ldi 1
    #|    v3 = add v1, v2
    #|    store.i32 +4 v0, v3
    #|    ret v3
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "bitwise operations" {
  let builder = VCodeBuilder::new("bitwise")
  let p0 = builder.add_param(Int)
  let p1 = builder.add_param(Int)
  builder.add_result(Int)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let and_result = builder.band(p0, p1)
  let or_result = builder.bor(p0, p1)
  let xor_result = builder.bxor(and_result, or_result)
  builder.return_([xor_result])
  let output = builder.print()
  let expected =
    #|vcode bitwise(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = and v0, v1
    #|    v3 = or v0, v1
    #|    v4 = xor v2, v3
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "shift operations" {
  let builder = VCodeBuilder::new("shifts")
  let p0 = builder.add_param(Int)
  builder.add_result(Int)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let c1 = builder.iconst(1L)
  let shl_result = builder.shl(p0, c1)
  let ashr_result = builder.ashr(shl_result, c1)
  let lshr_result = builder.lshr(ashr_result, c1)
  builder.return_([lshr_result])
  let output = builder.print()
  let expected =
    #|vcode shifts(v0:int) -> int {
    #|block0:
    #|    v1 = ldi 1
    #|    v2 = shl v0, v1
    #|    v3 = ashr v2, v1
    #|    v4 = lshr v3, v1
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "division operations" {
  let builder = VCodeBuilder::new("division")
  let p0 = builder.add_param(Int)
  let p1 = builder.add_param(Int)
  builder.add_result(Int)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let sdiv_result = builder.sdiv(p0, p1)
  let udiv_result = builder.udiv(p0, p1)
  let sum = builder.add(sdiv_result, udiv_result)
  builder.return_([sum])
  let output = builder.print()
  let expected =
    #|vcode division(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = sdiv v0, v1
    #|    v3 = udiv v0, v1
    #|    v4 = add v2, v3
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "regalloc: call result is not cross-call" {
  let func = @regalloc.VCodeFunction::new("test_regalloc_call_result")
  func.add_result(Int)
  let block = func.new_block()

  // A call-like instruction that defines a result.
  // Use CallPtr so liveness sees a call point.
  let func_ptr = func.new_vreg(Int)
  let load_ptr = @instr.VCodeInst::new(LoadConst(0L))
  load_ptr.add_def({ reg: @abi.Virtual(func_ptr) })
  block.add_inst(load_ptr)
  let call_result = func.new_vreg(Int)
  let call_inst = @instr.VCodeInst::new(CallPtr(1, 1, C))
  call_inst.add_use(@abi.Virtual(func_ptr))
  call_inst.add_def({ reg: @abi.Virtual(call_result) })
  block.add_inst(call_inst)

  // Use the call result later so it has a non-empty live range.
  let one = func.new_vreg(Int)
  let one_inst = @instr.VCodeInst::new(LoadConst(1L))
  one_inst.add_def({ reg: @abi.Virtual(one) })
  block.add_inst(one_inst)
  let sum = func.new_vreg(Int)
  let add_inst = @instr.VCodeInst::new(Add(true))
  add_inst.add_def({ reg: @abi.Virtual(sum) })
  add_inst.add_use(@abi.Virtual(call_result))
  add_inst.add_use(@abi.Virtual(one))
  block.add_inst(add_inst)
  block.set_terminator(Return([@abi.Virtual(sum)]))
  let liveness = @regalloc.compute_liveness(func)
  let interval = liveness.intervals.get(call_result.id).unwrap()
  inspect(interval.crosses_call, content="false")
}

///|
test "float division and subtraction" {
  let builder = VCodeBuilder::new("float_ops")
  let p0 = builder.add_param(Float32)
  let p1 = builder.add_param(Float32)
  builder.add_result(Float32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let div_result = builder.fdiv(p0, p1)
  let sub_result = builder.fsub(div_result, p1)
  builder.return_([sub_result])
  let output = builder.print()
  inspect(
    output,
    content=(
      #|vcode float_ops(f0:float, f1:float) -> float {
      #|block0:
      #|    f2 = fdiv.d f0, f1
      #|    f3 = fsub.d f2, f1
      #|    ret f3
      #|}
      #|
    ),
  )
}

///|
test "f64 operations" {
  let builder = VCodeBuilder::new("f64_add")
  let p0 = builder.add_param(Float64)
  let p1 = builder.add_param(Float64)
  builder.add_result(Float64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let sum = builder.fadd(p0, p1)
  let c2 = builder.fconst(2.0)
  let result = builder.fmul(sum, c2)
  builder.return_([result])
  let output = builder.print()
  inspect(
    output,
    content=(
      #|vcode f64_add(f0:double, f1:double) -> double {
      #|block0:
      #|    f2 = fadd.d f0, f1
      #|    f3 = ldf 2
      #|    f4 = fmul.d f2, f3
      #|    ret f4
      #|}
      #|
    ),
  )
}

///|
test "f64 division and subtraction" {
  let builder = VCodeBuilder::new("f64_ops")
  let p0 = builder.add_param(Float64)
  let p1 = builder.add_param(Float64)
  builder.add_result(Float64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let div_result = builder.fdiv(p0, p1)
  let sub_result = builder.fsub(div_result, p1)
  builder.return_([sub_result])
  let output = builder.print()
  inspect(
    output,
    content=(
      #|vcode f64_ops(f0:double, f1:double) -> double {
      #|block0:
      #|    f2 = fdiv.d f0, f1
      #|    f3 = fsub.d f2, f1
      #|    ret f3
      #|}
      #|
    ),
  )
}

///|
test "mixed int and float parameters" {
  // fn mixed(a: int, b: float32, c: int, d: float64) -> float64
  let builder = VCodeBuilder::new("mixed_params")
  let a = builder.add_param(Int)
  let b = builder.add_param(Float32)
  let c = builder.add_param(Int)
  let d = builder.add_param(Float64)
  builder.add_result(Float64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  // Just add the two floats together (both promoted to double internally)
  let result = builder.fadd(b, d)
  builder.return_([result])
  ignore(a)
  ignore(c)
  let output = builder.print()
  inspect(
    output,
    content=(
      #|vcode mixed_params(v0:int, f1:float, v2:int, f3:double) -> double {
      #|block0:
      #|    f4 = fadd.d f1, f3
      #|    ret f4
      #|}
      #|
    ),
  )
}

///|
test "all comparison kinds" {
  let builder = VCodeBuilder::new("cmp_all")
  let p0 = builder.add_param(Int)
  let p1 = builder.add_param(Int)
  builder.add_result(Int)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  builder.cmp(Eq, p0, p1) |> ignore
  builder.cmp(Ne, p0, p1) |> ignore
  builder.cmp(Slt, p0, p1) |> ignore
  builder.cmp(Sle, p0, p1) |> ignore
  builder.cmp(Sge, p0, p1) |> ignore
  builder.cmp(Ult, p0, p1) |> ignore
  builder.cmp(Ule, p0, p1) |> ignore
  builder.cmp(Ugt, p0, p1) |> ignore
  let result = builder.cmp(Uge, p0, p1)
  builder.return_([result])
  inspect(builder.get_function().get_blocks()[0].insts.length(), content="9")
}

///|
test "float comparison kinds" {
  let builder = VCodeBuilder::new("fcmp_all")
  let p0 = builder.add_param(Float64)
  let p1 = builder.add_param(Float64)
  builder.add_result(Int)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  builder.fcmp(Eq, p0, p1) |> ignore
  builder.fcmp(Ne, p0, p1) |> ignore
  builder.fcmp(Lt, p0, p1) |> ignore
  builder.fcmp(Le, p0, p1) |> ignore
  builder.fcmp(Gt, p0, p1) |> ignore
  let result = builder.fcmp(Ge, p0, p1)
  builder.return_([result])
  inspect(builder.get_function().get_blocks()[0].insts.length(), content="6")
}

///|
test "jump and trap" {
  let builder = VCodeBuilder::new("control")
  builder.add_result(Int)
  let entry = builder.create_block()
  let middle = builder.create_block()
  let trap_block = builder.create_block()
  builder.switch_to_block(entry)
  builder.jump(middle)
  builder.switch_to_block(middle)
  let c0 = builder.iconst(0L)
  builder.jump(trap_block)
  builder.switch_to_block(trap_block)
  builder.trap("unreachable")
  let func = builder.get_function()
  match func.get_blocks()[0].terminator {
    Some(Jump(1, _)) => ()
    _ => panic()
  }
  match func.get_blocks()[2].terminator {
    Some(Trap("unreachable")) => ()
    _ => panic()
  }
  ignore(c0)
}

///|
test "mov operation" {
  let builder = VCodeBuilder::new("mov_test")
  let p0 = builder.add_param(Int)
  builder.add_result(Int)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let copy = builder.mov(p0)
  builder.return_([copy])
  let output = builder.print()
  let expected =
    #|vcode mov_test(v0:int) -> int {
    #|block0:
    #|    v1 = mov v0
    #|    ret v1
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "memory types" {
  let builder = VCodeBuilder::new("mem_types")
  let addr = builder.add_param(Int)
  builder.add_result(Int)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  builder.load(I32, addr, 0) |> ignore
  builder.load(I64, addr, 2) |> ignore
  builder.load(F32, addr, 3) |> ignore
  let result = builder.load(F64, addr, 4)
  builder.return_([result])
  // Just check it doesn't crash
  ignore(builder.print())
}

///|
test "sub operation" {
  let builder = VCodeBuilder::new("sub_test")
  let p0 = builder.add_param(Int)
  let p1 = builder.add_param(Int)
  builder.add_result(Int)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let result = builder.sub(p0, p1)
  builder.return_([result])
  let output = builder.print()
  let expected =
    #|vcode sub_test(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = sub v0, v1
    #|    ret v2
    #|}
    #|
  inspect(output, content=expected)
}

// ============ Target ISA Tests ============

///|
test "AArch64 target basics" {
  let target = AArch64::new()
  inspect(target.name(), content="aarch64")
  inspect(target.gpr_count(), content="31")
  inspect(target.fpr_count(), content="32")
  inspect(target.pointer_size(), content="8")
}

///|
test "AArch64 get_preg" {
  let target = AArch64::new()
  // Valid GPR
  match target.get_preg(Int, 0) {
    Some(preg) => {
      inspect(preg.index, content="0")
      inspect(preg.class.to_string(), content="int")
    }
    None => panic()
  }
  // Valid FPR
  match target.get_preg(Float64, 31) {
    Some(preg) => {
      inspect(preg.index, content="31")
      inspect(preg.class.to_string(), content="double")
    }
    None => panic()
  }
  // Invalid GPR (x31 is zero register, not available)
  if target.get_preg(Int, 31) is Some(_) {
    panic()
  }
  // Out of range FPR
  if target.get_preg(Float64, 32) is Some(_) {
    panic()
  }
}

///|
test "AAPCS64 calling convention registers" {
  let arg_gprs = @abi.aapcs64_arg_gprs()
  inspect(arg_gprs, content="[x0, x1, x2, x3, x4, x5, x6, x7]") // x0-x7
  let ret_gprs = @abi.aapcs64_ret_gprs()
  inspect(ret_gprs, content="[x0, x1, x2, x3, x4, x5, x6, x7]") // x0-x1
  let callee_saved = @abi.aapcs64_callee_saved()
  inspect(
    callee_saved,
    content="[x19, x20, x21, x22, x23, x24, x25, x26, x27, x28, x29, x30]",
  ) // x19-x28, fp, lr
  let scratch_regs = @abi.allocatable_scratch_regs()
  inspect(
    scratch_regs,
    content="[x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15]",
  ) // x8-x15
  let callee_saved_regs = @abi.allocatable_callee_saved_regs()
  inspect(
    callee_saved_regs,
    content="[x19, x20, x22, x23, x24, x25, x26, x27, x28]",
  ) // x19-x28 excluding pinned x21
  let arg_fprs = @abi.aapcs64_arg_fprs()
  inspect(arg_fprs, content="[d0, d1, d2, d3, d4, d5, d6, d7]") // d0-d7
  let ret_fprs = @abi.aapcs64_ret_fprs()
  inspect(ret_fprs, content="[d0, d1, d2, d3, d4, d5, d6, d7]") // d0-d3
}
