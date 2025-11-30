// IR to VCode Lowering
// Converts high-level SSA IR to low-level VCode representation
//
// This is the instruction selection phase that:
// 1. Maps IR values to virtual registers
// 2. Converts IR opcodes to VCode opcodes
// 3. Handles control flow translation

///|
/// Lowering context - tracks state during IR to VCode conversion
pub(all) struct LoweringContext {
  ir_func : @ir.Function
  vcode_func : VCodeFunction
  // Map from IR Value id to VReg
  value_map : Map[Int, VReg]
  // Map from IR Block id to VCode block id
  block_map : Map[Int, Int]
}

///|
pub fn LoweringContext::new(ir_func : @ir.Function) -> LoweringContext {
  {
    ir_func,
    vcode_func: VCodeFunction::new(ir_func.name),
    value_map: {},
    block_map: {},
  }
}

///|
/// Get or create a VReg for an IR Value
fn LoweringContext::get_vreg(self : LoweringContext, value : @ir.Value) -> VReg {
  match self.value_map.get(value.id) {
    Some(vreg) => vreg
    None => {
      let class = ir_type_to_reg_class(value.ty)
      let vreg = self.vcode_func.new_vreg(class)
      self.value_map.set(value.id, vreg)
      vreg
    }
  }
}

///|
/// Create a new VReg with the given class
fn LoweringContext::new_vreg(self : LoweringContext, class : RegClass) -> VReg {
  self.vcode_func.new_vreg(class)
}

///|
/// Get VCode block id for an IR block id
fn LoweringContext::get_block_id(
  self : LoweringContext,
  ir_block_id : Int,
) -> Int {
  match self.block_map.get(ir_block_id) {
    Some(id) => id
    None => panic()
  }
}

///|
/// Convert IR Type to RegClass
fn ir_type_to_reg_class(ty : @ir.Type) -> RegClass {
  match ty {
    @ir.Type::I32 | @ir.Type::I64 | @ir.Type::FuncRef | @ir.Type::ExternRef =>
      Int
    @ir.Type::F32 | @ir.Type::F64 => Float
  }
}

///|
/// Convert IR Type to MemType
fn ir_type_to_mem_type(ty : @ir.Type) -> MemType {
  match ty {
    @ir.Type::I32 => I32
    @ir.Type::I64 => I64
    @ir.Type::F32 => F32
    @ir.Type::F64 => F64
    _ => I32 // Fallback
  }
}

///|
/// Lower an entire IR function to VCode
pub fn lower_function(ir_func : @ir.Function) -> VCodeFunction {
  let ctx = LoweringContext::new(ir_func)

  // Phase 1: Create VCode blocks and set up block mapping
  for ir_block in ir_func.blocks {
    let vcode_block = ctx.vcode_func.new_block()
    ctx.block_map.set(ir_block.id, vcode_block.id)
  }

  // Phase 2: Lower function parameters
  for param in ir_func.params {
    let (value, ty) = param
    let class = ir_type_to_reg_class(ty)
    let vreg = ctx.vcode_func.add_param(class)
    ctx.value_map.set(value.id, vreg)
  }

  // Phase 3: Lower result types
  for ty in ir_func.results {
    let class = ir_type_to_reg_class(ty)
    ctx.vcode_func.add_result(class)
  }

  // Phase 4: Lower each block
  for i, ir_block in ir_func.blocks {
    lower_block(ctx, ir_block, ctx.vcode_func.blocks[i])
  }
  ctx.vcode_func
}

///|
/// Lower a single IR block to VCode
fn lower_block(
  ctx : LoweringContext,
  ir_block : @ir.Block,
  vcode_block : VCodeBlock,
) -> Unit {
  // Lower block parameters
  for param in ir_block.params {
    let (value, ty) = param
    let class = ir_type_to_reg_class(ty)
    let vreg = ctx.vcode_func.new_vreg(class)
    ctx.value_map.set(value.id, vreg)
    vcode_block.params.push(vreg)
  }

  // Lower instructions
  for inst in ir_block.instructions {
    lower_inst(ctx, inst, vcode_block)
  }

  // Lower terminator
  match ir_block.terminator {
    Some(term) => lower_terminator(ctx, term, vcode_block)
    None => ()
  }
}

///|
/// Lower a single IR instruction to VCode
fn lower_inst(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  match inst.opcode {
    // Constants
    @ir.Opcode::Iconst(val) => lower_iconst(ctx, inst, block, val)
    @ir.Opcode::Fconst(val) => lower_fconst(ctx, inst, block, val)

    // Integer arithmetic
    @ir.Opcode::Iadd => lower_binary_int(ctx, inst, block, Add)
    @ir.Opcode::Isub => lower_binary_int(ctx, inst, block, Sub)
    @ir.Opcode::Imul => lower_binary_int(ctx, inst, block, Mul)
    @ir.Opcode::Sdiv => lower_binary_int(ctx, inst, block, SDiv)
    @ir.Opcode::Udiv => lower_binary_int(ctx, inst, block, UDiv)

    // Bitwise operations
    @ir.Opcode::Band => lower_binary_int(ctx, inst, block, And)
    @ir.Opcode::Bor => lower_binary_int(ctx, inst, block, Or)
    @ir.Opcode::Bxor => lower_binary_int(ctx, inst, block, Xor)
    @ir.Opcode::Ishl => lower_binary_int(ctx, inst, block, Shl)
    @ir.Opcode::Sshr => lower_binary_int(ctx, inst, block, AShr)
    @ir.Opcode::Ushr => lower_binary_int(ctx, inst, block, LShr)

    // Integer comparisons
    @ir.Opcode::Icmp(cc) => lower_icmp(ctx, inst, block, cc)

    // Floating point arithmetic
    @ir.Opcode::Fadd => lower_binary_float(ctx, inst, block, FAdd)
    @ir.Opcode::Fsub => lower_binary_float(ctx, inst, block, FSub)
    @ir.Opcode::Fmul => lower_binary_float(ctx, inst, block, FMul)
    @ir.Opcode::Fdiv => lower_binary_float(ctx, inst, block, FDiv)

    // Floating point comparisons
    @ir.Opcode::Fcmp(cc) => lower_fcmp(ctx, inst, block, cc)

    // Memory operations
    @ir.Opcode::Load(ty, offset) => lower_load(ctx, inst, block, ty, offset)
    @ir.Opcode::Store(ty, offset) => lower_store(ctx, inst, block, ty, offset)

    // Conversions
    @ir.Opcode::Sextend => lower_extend(ctx, inst, block, signed=true)
    @ir.Opcode::Uextend => lower_extend(ctx, inst, block, signed=false)
    @ir.Opcode::Ireduce => lower_truncate(ctx, inst, block)
    @ir.Opcode::FcvtToSint | @ir.Opcode::FcvtToUint =>
      lower_float_to_int(ctx, inst, block)
    @ir.Opcode::SintToFcvt | @ir.Opcode::UintToFcvt =>
      lower_int_to_float(ctx, inst, block)

    // Misc
    @ir.Opcode::Copy => lower_copy(ctx, inst, block)
    @ir.Opcode::Select => lower_select(ctx, inst, block)

    // Unimplemented opcodes - emit nop for now
    _ => ()
  }
}

///|
/// Lower integer constant
fn lower_iconst(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  val : Int64,
) -> Unit {
  match inst.result {
    Some(result) => {
      let vreg = ctx.get_vreg(result)
      let vcode_inst = VCodeInst::new(LoadConst(val))
      vcode_inst.add_def({ reg: Virtual(vreg) })
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower float constant
fn lower_fconst(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  val : Double,
) -> Unit {
  match inst.result {
    Some(result) => {
      let vreg = ctx.get_vreg(result)
      let vcode_inst = VCodeInst::new(LoadConstF(val))
      vcode_inst.add_def({ reg: Virtual(vreg) })
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower binary integer operation
fn lower_binary_int(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  opcode : VCodeOpcode,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let lhs = ctx.get_vreg(inst.operands[0])
      let rhs = ctx.get_vreg(inst.operands[1])
      let vcode_inst = VCodeInst::new(opcode)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(lhs))
      vcode_inst.add_use(Virtual(rhs))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower binary float operation
fn lower_binary_float(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  opcode : VCodeOpcode,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let lhs = ctx.get_vreg(inst.operands[0])
      let rhs = ctx.get_vreg(inst.operands[1])
      let vcode_inst = VCodeInst::new(opcode)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(lhs))
      vcode_inst.add_use(Virtual(rhs))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Convert IR IntCC to VCode CmpKind
fn ir_intcc_to_cmp_kind(cc : @ir.IntCC) -> CmpKind {
  match cc {
    @ir.IntCC::Eq => Eq
    @ir.IntCC::Ne => Ne
    @ir.IntCC::Slt => Slt
    @ir.IntCC::Sle => Sle
    @ir.IntCC::Sgt => Sgt
    @ir.IntCC::Sge => Sge
    @ir.IntCC::Ult => Ult
    @ir.IntCC::Ule => Ule
    @ir.IntCC::Ugt => Ugt
    @ir.IntCC::Uge => Uge
  }
}

///|
/// Lower integer comparison
fn lower_icmp(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  cc : @ir.IntCC,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let lhs = ctx.get_vreg(inst.operands[0])
      let rhs = ctx.get_vreg(inst.operands[1])
      let kind = ir_intcc_to_cmp_kind(cc)
      let vcode_inst = VCodeInst::new(Cmp(kind))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(lhs))
      vcode_inst.add_use(Virtual(rhs))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Convert IR FloatCC to VCode FCmpKind
fn ir_floatcc_to_fcmp_kind(cc : @ir.FloatCC) -> FCmpKind {
  match cc {
    @ir.FloatCC::Eq => FCmpKind::Eq
    @ir.FloatCC::Ne => FCmpKind::Ne
    @ir.FloatCC::Lt => FCmpKind::Lt
    @ir.FloatCC::Le => FCmpKind::Le
    @ir.FloatCC::Gt => FCmpKind::Gt
    @ir.FloatCC::Ge => FCmpKind::Ge
  }
}

///|
/// Lower float comparison
fn lower_fcmp(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  cc : @ir.FloatCC,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let lhs = ctx.get_vreg(inst.operands[0])
      let rhs = ctx.get_vreg(inst.operands[1])
      let kind = ir_floatcc_to_fcmp_kind(cc)
      let vcode_inst = VCodeInst::new(FCmp(kind))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(lhs))
      vcode_inst.add_use(Virtual(rhs))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower load instruction
fn lower_load(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  ty : @ir.Type,
  offset : Int,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let addr = ctx.get_vreg(inst.operands[0])
      let mem_ty = ir_type_to_mem_type(ty)
      let vcode_inst = VCodeInst::new(Load(mem_ty, offset))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(addr))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower store instruction
fn lower_store(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  ty : @ir.Type,
  offset : Int,
) -> Unit {
  // Store has no result, just uses: addr, value
  let addr = ctx.get_vreg(inst.operands[0])
  let value = ctx.get_vreg(inst.operands[1])
  let mem_ty = ir_type_to_mem_type(ty)
  let vcode_inst = VCodeInst::new(Store(mem_ty, offset))
  vcode_inst.add_use(Virtual(addr))
  vcode_inst.add_use(Virtual(value))
  block.add_inst(vcode_inst)
}

///|
/// Lower extend operation (sign or zero extend)
fn lower_extend(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
  signed~ : Bool,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let src = ctx.get_vreg(inst.operands[0])
      // Determine the extend kind based on source and destination types
      let src_ty = inst.operands[0].ty
      let dst_ty = result.ty
      let kind = get_extend_kind(src_ty, dst_ty, signed)
      let vcode_inst = VCodeInst::new(Extend(kind))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(src))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Determine the extend kind based on source and destination types
fn get_extend_kind(
  src_ty : @ir.Type,
  dst_ty : @ir.Type,
  signed : Bool,
) -> ExtendKind {
  match (src_ty, dst_ty, signed) {
    (@ir.Type::I32, @ir.Type::I64, true) => Signed32To64
    (@ir.Type::I32, @ir.Type::I64, false) => Unsigned32To64
    // Default to 32->64 extend
    _ => if signed { Signed32To64 } else { Unsigned32To64 }
  }
}

///|
/// Lower truncate operation
fn lower_truncate(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let src = ctx.get_vreg(inst.operands[0])
      let vcode_inst = VCodeInst::new(Truncate)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(src))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower float to int conversion
fn lower_float_to_int(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let src = ctx.get_vreg(inst.operands[0])
      let vcode_inst = VCodeInst::new(FloatToInt)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(src))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower int to float conversion
fn lower_int_to_float(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let src = ctx.get_vreg(inst.operands[0])
      let vcode_inst = VCodeInst::new(IntToFloat)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(src))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower copy instruction
fn lower_copy(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let src = ctx.get_vreg(inst.operands[0])
      let vcode_inst = VCodeInst::new(Move)
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(src))
      block.add_inst(vcode_inst)
    }
    None => ()
  }
}

///|
/// Lower select instruction (cond ? a : b)
fn lower_select(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : VCodeBlock,
) -> Unit {
  // For now, lower select to a conditional move sequence
  // In the future, this could be pattern-matched to cmov on x86 or csel on AArch64
  match inst.result {
    Some(result) => {
      let dst = ctx.get_vreg(result)
      let cond = ctx.get_vreg(inst.operands[0])
      let true_val = ctx.get_vreg(inst.operands[1])
      let false_val = ctx.get_vreg(inst.operands[2])

      // For now, emit a simple sequence:
      // mov dst, false_val
      // cmp cond, 0
      // cmov.ne dst, true_val (conceptually)
      // We'll simplify to just a move for now - proper select lowering
      // requires target-specific patterns

      // Move false value first
      let mov_inst = VCodeInst::new(Move)
      mov_inst.add_def({ reg: Virtual(dst) })
      mov_inst.add_use(Virtual(false_val))
      block.add_inst(mov_inst)

      // TODO: Add conditional move when we have target-specific patterns
      ignore(cond)
      ignore(true_val)
    }
    None => ()
  }
}

///|
/// Lower a terminator
fn lower_terminator(
  ctx : LoweringContext,
  term : @ir.Terminator,
  block : VCodeBlock,
) -> Unit {
  match term {
    @ir.Terminator::Jump(target, _args) => {
      let target_id = ctx.get_block_id(target)
      block.set_terminator(Jump(target_id))
    }
    @ir.Terminator::Brz(cond, then_block, else_block) => {
      let cond_vreg = ctx.get_vreg(cond)
      let then_id = ctx.get_block_id(then_block)
      let else_id = ctx.get_block_id(else_block)
      // brz means branch if zero, so swap then/else for Branch semantics
      block.set_terminator(Branch(Virtual(cond_vreg), else_id, then_id))
    }
    @ir.Terminator::Brnz(cond, then_block, else_block) => {
      let cond_vreg = ctx.get_vreg(cond)
      let then_id = ctx.get_block_id(then_block)
      let else_id = ctx.get_block_id(else_block)
      block.set_terminator(Branch(Virtual(cond_vreg), then_id, else_id))
    }
    @ir.Terminator::Return(values) => {
      let regs : Array[Reg] = []
      for v in values {
        regs.push(Virtual(ctx.get_vreg(v)))
      }
      block.set_terminator(Return(regs))
    }
    @ir.Terminator::Trap(msg) => block.set_terminator(Trap(msg))
    @ir.Terminator::BrTable(index, targets, default) => {
      // For now, lower br_table to a simple branch
      // TODO: Implement proper switch lowering with jump tables
      let _index_vreg = ctx.get_vreg(index)
      let default_id = ctx.get_block_id(default)
      block.set_terminator(Jump(default_id))
      ignore(targets)
    }
  }
}
