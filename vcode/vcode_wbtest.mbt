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
  let p0 = builder.add_param(Float)
  let p1 = builder.add_param(Float)
  builder.add_result(Float)
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
      #|    f2 = fadd f0, f1
      #|    f3 = ldf 2
      #|    f4 = fmul f2, f3
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
test "float division and subtraction" {
  let builder = VCodeBuilder::new("float_ops")
  let p0 = builder.add_param(Float)
  let p1 = builder.add_param(Float)
  builder.add_result(Float)
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
      #|    f2 = fdiv f0, f1
      #|    f3 = fsub f2, f1
      #|    ret f3
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
  let _ = builder.cmp(Eq, p0, p1)
  let _ = builder.cmp(Ne, p0, p1)
  let _ = builder.cmp(Slt, p0, p1)
  let _ = builder.cmp(Sle, p0, p1)
  let _ = builder.cmp(Sge, p0, p1)
  let _ = builder.cmp(Ult, p0, p1)
  let _ = builder.cmp(Ule, p0, p1)
  let _ = builder.cmp(Ugt, p0, p1)
  let result = builder.cmp(Uge, p0, p1)
  builder.return_([result])
  inspect(builder.get_function().blocks[0].insts.length(), content="9")
}

///|
test "float comparison kinds" {
  let builder = VCodeBuilder::new("fcmp_all")
  let p0 = builder.add_param(Float)
  let p1 = builder.add_param(Float)
  builder.add_result(Int)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let _ = builder.fcmp(FCmpKind::Eq, p0, p1)
  let _ = builder.fcmp(FCmpKind::Ne, p0, p1)
  let _ = builder.fcmp(FCmpKind::Lt, p0, p1)
  let _ = builder.fcmp(FCmpKind::Le, p0, p1)
  let _ = builder.fcmp(FCmpKind::Gt, p0, p1)
  let result = builder.fcmp(FCmpKind::Ge, p0, p1)
  builder.return_([result])
  inspect(builder.get_function().blocks[0].insts.length(), content="6")
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
  match func.blocks[0].terminator {
    Some(Jump(1)) => ()
    _ => panic()
  }
  match func.blocks[2].terminator {
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
  let _ = builder.load(I8, addr, 0)
  let _ = builder.load(I16, addr, 1)
  let _ = builder.load(I64, addr, 2)
  let _ = builder.load(F32, addr, 3)
  let result = builder.load(F64, addr, 4)
  builder.return_([result])
  // Just check it doesn't crash
  ignore(builder.print())
}

///|
test "physical registers" {
  let preg = PReg::{ index: 0, class: Int }
  inspect(preg.to_string(), content="x0")
  let preg_f = PReg::{ index: 5, class: Float }
  inspect(preg_f.to_string(), content="d5")
}

///|
test "operand kinds and constraints" {
  let vreg : VReg = { id: 0, class: Int }
  let op1 : Operand = { reg: vreg, kind: Use, constraint: Any }
  let op2 : Operand = {
    reg: vreg,
    kind: Def,
    constraint: Fixed(PReg::{ index: 0, class: Int }),
  }
  let op3 : Operand = { reg: vreg, kind: UseDef, constraint: Reuse(0) }
  inspect(op1.kind.to_string(), content="use")
  inspect(op2.kind.to_string(), content="def")
  inspect(op3.kind.to_string(), content="use-def")
  inspect(op1.constraint.to_string(), content="any")
  inspect(op2.constraint.to_string(), content="fixed(x0)")
  inspect(op3.constraint.to_string(), content="reuse(0)")
}

///|
test "extend kinds" {
  inspect(Signed8To32.to_string(), content="s8_32")
  inspect(Signed8To64.to_string(), content="s8_64")
  inspect(Signed16To32.to_string(), content="s16_32")
  inspect(Signed16To64.to_string(), content="s16_64")
  inspect(Signed32To64.to_string(), content="s32_64")
  inspect(Unsigned8To32.to_string(), content="u8_32")
  inspect(Unsigned8To64.to_string(), content="u8_64")
  inspect(Unsigned16To32.to_string(), content="u16_32")
  inspect(Unsigned16To64.to_string(), content="u16_64")
  inspect(Unsigned32To64.to_string(), content="u32_64")
}

///|
test "vcode opcode strings" {
  inspect(Nop.to_string(), content="nop")
  inspect(Truncate.to_string(), content="trunc")
  inspect(IntToFloat.to_string(), content="i2f")
  inspect(FloatToInt.to_string(), content="f2i")
  inspect(Extend(Signed8To32).to_string(), content="extend.s8_32")
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
  match target.get_preg(Float, 31) {
    Some(preg) => {
      inspect(preg.index, content="31")
      inspect(preg.class.to_string(), content="float")
    }
    None => panic()
  }
  // Invalid GPR (x31 is zero register, not available)
  match target.get_preg(Int, 31) {
    Some(_) => panic()
    None => ()
  }
  // Out of range FPR
  match target.get_preg(Float, 32) {
    Some(_) => panic()
    None => ()
  }
}

///|
test "AArch64 register names" {
  let regs = AArch64Regs::new()
  inspect(regs.x0().to_string(), content="x0")
  inspect(regs.x7().to_string(), content="x7")
  inspect(regs.fp().to_string(), content="x29")
  inspect(regs.lr().to_string(), content="x30")
  inspect(regs.d0().to_string(), content="d0")
  inspect(regs.d7().to_string(), content="d7")
}

///|
test "AAPCS64 calling convention registers" {
  let arg_gprs = aapcs64_arg_gprs()
  inspect(arg_gprs.length(), content="8") // x0-x7
  let ret_gprs = aapcs64_ret_gprs()
  inspect(ret_gprs.length(), content="2") // x0-x1
  let callee_saved = aapcs64_callee_saved()
  inspect(callee_saved.length(), content="12") // x19-x28, fp, lr
  let caller_saved = aapcs64_caller_saved()
  inspect(caller_saved.length(), content="19") // x0-x18
  let arg_fprs = aapcs64_arg_fprs()
  inspect(arg_fprs.length(), content="8") // d0-d7
  let ret_fprs = aapcs64_ret_fprs()
  inspect(ret_fprs.length(), content="4") // d0-d3
}

///|
test "calling convention strings" {
  inspect(SystemV.to_string(), content="system_v")
  inspect(WindowsFastcall.to_string(), content="windows_fastcall")
  inspect(Aapcs64.to_string(), content="aapcs64")
  inspect(Wasm.to_string(), content="wasm")
}
