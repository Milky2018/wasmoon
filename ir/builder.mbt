// IR Builder - Convenient API for constructing IR
// Similar to Cranelift's FunctionBuilder

///|
/// IRBuilder - helps construct IR functions
/// Tracks the current block and provides methods for emitting instructions
pub(all) struct IRBuilder {
  func : Function
  mut current_block : Block?
}

///|
pub fn IRBuilder::new(name : String) -> IRBuilder {
  let func = Function::new(name)
  { func, current_block: None }
}

///|
/// Get the function being built
pub fn IRBuilder::get_function(self : IRBuilder) -> Function {
  self.func
}

///|
/// Add a parameter to the function
pub fn IRBuilder::add_param(self : IRBuilder, ty : Type) -> Value {
  self.func.add_param(ty)
}

///|
/// Add a result type to the function
pub fn IRBuilder::add_result(self : IRBuilder, ty : Type) -> Unit {
  self.func.add_result(ty)
}

///|
/// Create a new block and make it the current block
pub fn IRBuilder::create_block(self : IRBuilder) -> Block {
  let block = self.func.new_block()
  block
}

///|
/// Switch to a different block for emitting instructions
pub fn IRBuilder::switch_to_block(self : IRBuilder, block : Block) -> Unit {
  self.current_block = Some(block)
}

///|
/// Get the current block
pub fn IRBuilder::current_block(self : IRBuilder) -> Block? {
  self.current_block
}

///|
/// Add a block parameter (for SSA phi nodes)
pub fn IRBuilder::add_block_param(
  self : IRBuilder,
  block : Block,
  ty : Type,
) -> Value {
  let v = self.func.new_value(ty)
  block.add_param(v, ty)
  v
}

///|
/// Emit an instruction that produces a result
fn IRBuilder::emit_inst(
  self : IRBuilder,
  ty : Type,
  opcode : Opcode,
  operands : Array[Value],
) -> Value {
  let result = self.func.new_value(ty)
  let inst = Inst::new(Some(result), opcode, operands)
  match self.current_block {
    Some(block) => block.add_inst(inst)
    None => () // No current block, instruction is dropped
  }
  result
}

///|
/// Emit an instruction without a result
fn IRBuilder::emit_void_inst(
  self : IRBuilder,
  opcode : Opcode,
  operands : Array[Value],
) -> Unit {
  let inst = Inst::new(None, opcode, operands)
  match self.current_block {
    Some(block) => block.add_inst(inst)
    None => ()
  }
}

// ============ Constants ============

///|
/// Emit an integer constant
pub fn IRBuilder::iconst(self : IRBuilder, ty : Type, value : Int64) -> Value {
  self.emit_inst(ty, Opcode::Iconst(value), [])
}

///|
/// Emit an i32 constant
pub fn IRBuilder::iconst_i32(self : IRBuilder, value : Int) -> Value {
  self.iconst(Type::I32, value.to_int64())
}

///|
/// Emit an i64 constant
pub fn IRBuilder::iconst_i64(self : IRBuilder, value : Int64) -> Value {
  self.iconst(Type::I64, value)
}

///|
/// Emit a float constant
pub fn IRBuilder::fconst(self : IRBuilder, ty : Type, value : Double) -> Value {
  self.emit_inst(ty, Opcode::Fconst(value), [])
}

///|
/// Emit an f32 constant
pub fn IRBuilder::fconst_f32(self : IRBuilder, value : Float) -> Value {
  self.fconst(Type::F32, value.to_double())
}

///|
/// Emit an f64 constant
pub fn IRBuilder::fconst_f64(self : IRBuilder, value : Double) -> Value {
  self.fconst(Type::F64, value)
}

// ============ Integer Arithmetic ============

///|
/// Integer add
pub fn IRBuilder::iadd(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Iadd, [a, b])
}

///|
/// Integer subtract
pub fn IRBuilder::isub(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Isub, [a, b])
}

///|
/// Integer multiply
pub fn IRBuilder::imul(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Imul, [a, b])
}

///|
/// Signed integer divide
pub fn IRBuilder::sdiv(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Sdiv, [a, b])
}

///|
/// Unsigned integer divide
pub fn IRBuilder::udiv(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Udiv, [a, b])
}

///|
/// Signed integer remainder
pub fn IRBuilder::srem(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Srem, [a, b])
}

///|
/// Unsigned integer remainder
pub fn IRBuilder::urem(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Urem, [a, b])
}

// ============ Bitwise Operations ============

///|
/// Bitwise and
pub fn IRBuilder::band(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Band, [a, b])
}

///|
/// Bitwise or
pub fn IRBuilder::bor(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Bor, [a, b])
}

///|
/// Bitwise xor
pub fn IRBuilder::bxor(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Bxor, [a, b])
}

///|
/// Bitwise not
pub fn IRBuilder::bnot(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Bnot, [a])
}

///|
/// Shift left
pub fn IRBuilder::ishl(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Ishl, [a, b])
}

///|
/// Signed shift right
pub fn IRBuilder::sshr(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Sshr, [a, b])
}

///|
/// Unsigned shift right
pub fn IRBuilder::ushr(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Ushr, [a, b])
}

///|
/// Rotate left
pub fn IRBuilder::rotl(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Rotl, [a, b])
}

///|
/// Rotate right
pub fn IRBuilder::rotr(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Rotr, [a, b])
}

// ============ Integer Comparisons ============

///|
/// Integer comparison (returns i32 0 or 1)
pub fn IRBuilder::icmp(
  self : IRBuilder,
  cc : IntCC,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(Type::I32, Opcode::Icmp(cc), [a, b])
}

///|
/// Integer equal
pub fn IRBuilder::icmp_eq(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(IntCC::Eq, a, b)
}

///|
/// Integer not equal
pub fn IRBuilder::icmp_ne(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(IntCC::Ne, a, b)
}

///|
/// Signed less than
pub fn IRBuilder::icmp_slt(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(IntCC::Slt, a, b)
}

///|
/// Signed less than or equal
pub fn IRBuilder::icmp_sle(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(IntCC::Sle, a, b)
}

///|
/// Signed greater than
pub fn IRBuilder::icmp_sgt(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(IntCC::Sgt, a, b)
}

///|
/// Signed greater than or equal
pub fn IRBuilder::icmp_sge(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(IntCC::Sge, a, b)
}

///|
/// Unsigned less than
pub fn IRBuilder::icmp_ult(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(IntCC::Ult, a, b)
}

///|
/// Unsigned less than or equal
pub fn IRBuilder::icmp_ule(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(IntCC::Ule, a, b)
}

///|
/// Unsigned greater than
pub fn IRBuilder::icmp_ugt(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(IntCC::Ugt, a, b)
}

///|
/// Unsigned greater than or equal
pub fn IRBuilder::icmp_uge(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(IntCC::Uge, a, b)
}

// ============ Floating Point Arithmetic ============

///|
/// Float add
pub fn IRBuilder::fadd(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Fadd, [a, b])
}

///|
/// Float subtract
pub fn IRBuilder::fsub(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Fsub, [a, b])
}

///|
/// Float multiply
pub fn IRBuilder::fmul(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Fmul, [a, b])
}

///|
/// Float divide
pub fn IRBuilder::fdiv(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Fdiv, [a, b])
}

///|
/// Float minimum
pub fn IRBuilder::fmin(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Fmin, [a, b])
}

///|
/// Float maximum
pub fn IRBuilder::fmax(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Fmax, [a, b])
}

// ============ Float Comparisons ============

///|
/// Float comparison (returns i32 0 or 1)
pub fn IRBuilder::fcmp(
  self : IRBuilder,
  cc : FloatCC,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(Type::I32, Opcode::Fcmp(cc), [a, b])
}

// ============ Float Unary Operations ============

///|
/// Float negate
pub fn IRBuilder::fneg(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Fneg, [a])
}

///|
/// Float absolute value
pub fn IRBuilder::fabs(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Fabs, [a])
}

///|
/// Float square root
pub fn IRBuilder::fsqrt(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Fsqrt, [a])
}

///|
/// Float ceiling
pub fn IRBuilder::fceil(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Fceil, [a])
}

///|
/// Float floor
pub fn IRBuilder::ffloor(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Ffloor, [a])
}

///|
/// Float truncate
pub fn IRBuilder::ftrunc(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Ftrunc, [a])
}

///|
/// Float nearest (round to nearest even)
pub fn IRBuilder::fnearest(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Fnearest, [a])
}

// ============ Conversions ============

///|
/// Reduce integer width (e.g., i64 -> i32)
pub fn IRBuilder::ireduce(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Opcode::Ireduce, [a])
}

///|
/// Sign extend (e.g., i32 -> i64)
pub fn IRBuilder::sextend(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Opcode::Sextend, [a])
}

///|
/// Zero extend (e.g., i32 -> i64)
pub fn IRBuilder::uextend(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Opcode::Uextend, [a])
}

///|
/// Promote float (f32 -> f64)
pub fn IRBuilder::fpromote(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(Type::F64, Opcode::Fpromote, [a])
}

///|
/// Demote float (f64 -> f32)
pub fn IRBuilder::fdemote(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(Type::F32, Opcode::Fdemote, [a])
}

///|
/// Float to signed int
pub fn IRBuilder::fcvt_to_sint(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Opcode::FcvtToSint, [a])
}

///|
/// Float to unsigned int
pub fn IRBuilder::fcvt_to_uint(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Opcode::FcvtToUint, [a])
}

///|
/// Signed int to float
pub fn IRBuilder::sint_to_fcvt(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Opcode::SintToFcvt, [a])
}

///|
/// Unsigned int to float
pub fn IRBuilder::uint_to_fcvt(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Opcode::UintToFcvt, [a])
}

///|
/// Bitcast (reinterpret bits)
pub fn IRBuilder::bitcast(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Opcode::Bitcast, [a])
}

// ============ Memory Operations ============

///|
/// Load from memory
pub fn IRBuilder::load(
  self : IRBuilder,
  ty : Type,
  addr : Value,
  offset : Int,
) -> Value {
  self.emit_inst(ty, Opcode::Load(ty, offset), [addr])
}

///|
/// Load 8-bit signed value and extend to target type
pub fn IRBuilder::load8_s(
  self : IRBuilder,
  ty : Type,
  addr : Value,
  offset : Int,
) -> Value {
  self.emit_inst(ty, Opcode::Load8S(ty, offset), [addr])
}

///|
/// Load 8-bit unsigned value and extend to target type
pub fn IRBuilder::load8_u(
  self : IRBuilder,
  ty : Type,
  addr : Value,
  offset : Int,
) -> Value {
  self.emit_inst(ty, Opcode::Load8U(ty, offset), [addr])
}

///|
/// Load 16-bit signed value and extend to target type
pub fn IRBuilder::load16_s(
  self : IRBuilder,
  ty : Type,
  addr : Value,
  offset : Int,
) -> Value {
  self.emit_inst(ty, Opcode::Load16S(ty, offset), [addr])
}

///|
/// Load 16-bit unsigned value and extend to target type
pub fn IRBuilder::load16_u(
  self : IRBuilder,
  ty : Type,
  addr : Value,
  offset : Int,
) -> Value {
  self.emit_inst(ty, Opcode::Load16U(ty, offset), [addr])
}

///|
/// Load 32-bit signed value and extend to i64
pub fn IRBuilder::load32_s(
  self : IRBuilder,
  addr : Value,
  offset : Int,
) -> Value {
  self.emit_inst(Type::I64, Opcode::Load32S(offset), [addr])
}

///|
/// Load 32-bit unsigned value and extend to i64
pub fn IRBuilder::load32_u(
  self : IRBuilder,
  addr : Value,
  offset : Int,
) -> Value {
  self.emit_inst(Type::I64, Opcode::Load32U(offset), [addr])
}

///|
/// Store to memory
pub fn IRBuilder::store(
  self : IRBuilder,
  ty : Type,
  addr : Value,
  value : Value,
  offset : Int,
) -> Unit {
  self.emit_void_inst(Opcode::Store(ty, offset), [addr, value])
}

///|
/// Store low 8 bits of value
pub fn IRBuilder::store8(
  self : IRBuilder,
  addr : Value,
  value : Value,
  offset : Int,
) -> Unit {
  self.emit_void_inst(Opcode::Store8(offset), [addr, value])
}

///|
/// Store low 16 bits of value
pub fn IRBuilder::store16(
  self : IRBuilder,
  addr : Value,
  value : Value,
  offset : Int,
) -> Unit {
  self.emit_void_inst(Opcode::Store16(offset), [addr, value])
}

///|
/// Store low 32 bits of i64 value
pub fn IRBuilder::store32(
  self : IRBuilder,
  addr : Value,
  value : Value,
  offset : Int,
) -> Unit {
  self.emit_void_inst(Opcode::Store32(offset), [addr, value])
}

// ============ Misc Operations ============

///|
/// Conditional select: cond ? a : b
pub fn IRBuilder::select(
  self : IRBuilder,
  cond : Value,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Opcode::Select, [cond, a, b])
}

///|
/// Copy value (for register allocation)
pub fn IRBuilder::copy(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Copy, [a])
}

// ============ Function Calls ============

///|
/// Direct function call
pub fn IRBuilder::call(
  self : IRBuilder,
  func_idx : Int,
  result_ty : Type?,
  args : Array[Value],
) -> Value? {
  match result_ty {
    Some(ty) => Some(self.emit_inst(ty, Opcode::Call(func_idx), args))
    None => {
      self.emit_void_inst(Opcode::Call(func_idx), args)
      None
    }
  }
}

///|
/// Indirect function call
pub fn IRBuilder::call_indirect(
  self : IRBuilder,
  type_idx : Int,
  result_ty : Type?,
  callee : Value,
  args : Array[Value],
) -> Value? {
  let all_args : Array[Value] = [callee]
  for arg in args {
    all_args.push(arg)
  }
  match result_ty {
    Some(ty) =>
      Some(self.emit_inst(ty, Opcode::CallIndirect(type_idx), all_args))
    None => {
      self.emit_void_inst(Opcode::CallIndirect(type_idx), all_args)
      None
    }
  }
}

// ============ Terminators ============

///|
/// Unconditional jump
pub fn IRBuilder::jump(
  self : IRBuilder,
  target : Block,
  args : Array[Value],
) -> Unit {
  match self.current_block {
    Some(block) => block.set_terminator(Terminator::Jump(target.id, args))
    None => ()
  }
}

///|
/// Conditional branch (branch if zero)
pub fn IRBuilder::brz(
  self : IRBuilder,
  cond : Value,
  then_block : Block,
  else_block : Block,
) -> Unit {
  match self.current_block {
    Some(block) =>
      block.set_terminator(Terminator::Brz(cond, then_block.id, else_block.id))
    None => ()
  }
}

///|
/// Conditional branch (branch if non-zero)
pub fn IRBuilder::brnz(
  self : IRBuilder,
  cond : Value,
  then_block : Block,
  else_block : Block,
) -> Unit {
  match self.current_block {
    Some(block) =>
      block.set_terminator(Terminator::Brnz(cond, then_block.id, else_block.id))
    None => ()
  }
}

///|
/// Branch table (switch)
pub fn IRBuilder::br_table(
  self : IRBuilder,
  index : Value,
  targets : Array[Block],
  default_target : Block,
) -> Unit {
  let target_ids = targets.map(fn(b) { b.id })
  match self.current_block {
    Some(block) =>
      block.set_terminator(
        Terminator::BrTable(index, target_ids, default_target.id),
      )
    None => ()
  }
}

///|
/// Return from function
pub fn IRBuilder::return_(self : IRBuilder, values : Array[Value]) -> Unit {
  match self.current_block {
    Some(block) => block.set_terminator(Terminator::Return(values))
    None => ()
  }
}

///|
/// Trap/unreachable
pub fn IRBuilder::trap(self : IRBuilder, reason : String) -> Unit {
  match self.current_block {
    Some(block) => block.set_terminator(Terminator::Trap(reason))
    None => ()
  }
}
