// IR Builder - Convenient API for constructing IR
// SSA function builder

///|
/// IRBuilder - helps construct IR functions
/// Tracks the current block and provides methods for emitting instructions
struct IRBuilder {
  func : Function
  mut current_block : Block?
}

///|
pub fn IRBuilder::new(name : String) -> IRBuilder {
  let func = Function::new_empty(name)
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
  let block = self.func.new_block0()
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
pub fn IRBuilder::emit_inst(
  self : IRBuilder,
  ty : Type,
  opcode : Opcode,
  operands : Array[Value],
) -> Value {
  let result = self.func.new_value(ty)
  let inst = Inst::new(Some(result), opcode, operands)
  if self.current_block is Some(block) {
    block.add_inst(inst)
  }
  result
}

///|
/// Emit an instruction without a result
pub fn IRBuilder::emit_void_inst(
  self : IRBuilder,
  opcode : Opcode,
  operands : Array[Value],
) -> Unit {
  let inst = Inst::new(None, opcode, operands)
  if self.current_block is Some(block) {
    block.add_inst(inst)
  }
}

///|
/// Emit an instruction with multiple results.
pub fn IRBuilder::emit_multi_inst(
  self : IRBuilder,
  result_types : Array[Type],
  opcode : Opcode,
  operands : Array[Value],
) -> Array[Value] {
  if result_types.length() == 0 {
    self.emit_void_inst(opcode, operands)
    return []
  }
  let results : Array[Value] = []
  for ty in result_types {
    results.push(self.func.new_value(ty))
  }
  let inst = Inst::new_multi(results, opcode, operands)
  if self.current_block is Some(block) {
    block.add_inst(inst)
  }
  results
}

///|
pub fn IRBuilder::emit_ext_inst(
  self : IRBuilder,
  ty : Type,
  opcode : ExtOp,
  operands : Array[Value],
) -> Value {
  self.emit_inst(ty, Ext(opcode), operands)
}

///|
pub fn IRBuilder::emit_void_ext_inst(
  self : IRBuilder,
  opcode : ExtOp,
  operands : Array[Value],
) -> Unit {
  self.emit_void_inst(Ext(opcode), operands)
}

///|
pub fn IRBuilder::emit_multi_ext_inst(
  self : IRBuilder,
  result_types : Array[Type],
  opcode : ExtOp,
  operands : Array[Value],
) -> Array[Value] {
  self.emit_multi_inst(result_types, Ext(opcode), operands)
}

// ============ Constants ============

///|
/// Get the constant value if a Value was defined by an Iconst instruction.
/// Searches all blocks in the function to find the defining instruction.
/// Returns None if the value is not a constant or not found.
pub fn IRBuilder::get_const_value(self : IRBuilder, v : Value) -> Int64? {
  for block in self.func.blocks {
    for inst in block.instructions {
      if inst.first_result() is Some(r) && r.id == v.id {
        if inst.opcode is Iconst(c) {
          return Some(c)
        }
        return None // Found defining instruction but not a constant
      }
    }
  }
  None
}

///|
/// Emit an integer constant
pub fn IRBuilder::iconst(self : IRBuilder, ty : Type, value : Int64) -> Value {
  self.emit_inst(ty, Iconst(value), [])
}

///|
/// Emit an i32 constant
pub fn IRBuilder::iconst_i32(self : IRBuilder, value : Int) -> Value {
  self.iconst(I32, value.to_int64())
}

///|
/// Emit an i64 constant
pub fn IRBuilder::iconst_i64(self : IRBuilder, value : Int64) -> Value {
  self.iconst(I64, value)
}

///|
/// Emit a float constant
pub fn IRBuilder::fconst(self : IRBuilder, ty : Type, value : Double) -> Value {
  self.emit_inst(ty, Fconst(value), [])
}

///|
/// Emit an f32 constant
/// Note: We pack the f32 bits into the Double's bit representation to preserve
/// NaN payloads. Using value.to_double() would go through the FPU and convert
/// signaling NaNs to quiet NaNs.
pub fn IRBuilder::fconst_f32(self : IRBuilder, value : Float) -> Value {
  let f32_bits = value.reinterpret_as_int().to_int64()
  self.fconst(F32, f32_bits.reinterpret_as_double())
}

///|
/// Emit an f64 constant
pub fn IRBuilder::fconst_f64(self : IRBuilder, value : Double) -> Value {
  self.fconst(F64, value)
}

// ============ Integer Arithmetic ============

///|
/// Integer add
pub fn IRBuilder::iadd(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Iadd, [a, b])
}

///|
/// Integer subtract
pub fn IRBuilder::isub(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Isub, [a, b])
}

///|
/// Integer multiply
pub fn IRBuilder::imul(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Imul, [a, b])
}

///|
/// Unsigned multiply high (i64 only)
pub fn IRBuilder::umulh(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Umulh, [a, b])
}

///|
/// Signed multiply high (i64 only)
pub fn IRBuilder::smulh(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Smulh, [a, b])
}

///|
/// Signed integer divide
pub fn IRBuilder::sdiv(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Sdiv, [a, b])
}

///|
/// Unsigned integer divide
pub fn IRBuilder::udiv(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Udiv, [a, b])
}

///|
/// Signed integer remainder
pub fn IRBuilder::srem(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Srem, [a, b])
}

///|
/// Unsigned integer remainder
pub fn IRBuilder::urem(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Urem, [a, b])
}

// ============ Bitwise Operations ============

///|
/// Bitwise and
pub fn IRBuilder::band(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Band, [a, b])
}

///|
/// Bitwise or
pub fn IRBuilder::bor(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Bor, [a, b])
}

///|
/// Bitwise xor
pub fn IRBuilder::bxor(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Bxor, [a, b])
}

///|
/// Bitwise not
pub fn IRBuilder::bnot(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Bnot, [a])
}

///|
/// Shift left
pub fn IRBuilder::ishl(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Ishl, [a, b])
}

///|
/// Signed shift right
pub fn IRBuilder::sshr(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Sshr, [a, b])
}

///|
/// Unsigned shift right
pub fn IRBuilder::ushr(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Ushr, [a, b])
}

///|
/// Rotate left
pub fn IRBuilder::rotl(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Rotl, [a, b])
}

///|
/// Rotate right
pub fn IRBuilder::rotr(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Rotr, [a, b])
}

///|
/// Count leading zeros
pub fn IRBuilder::clz(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Clz, [a])
}

///|
/// Count trailing zeros
pub fn IRBuilder::ctz(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Ctz, [a])
}

///|
/// Population count (count number of 1 bits)
pub fn IRBuilder::popcnt(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Popcnt, [a])
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
  self.emit_inst(I32, Icmp(cc), [a, b])
}

///|
/// Integer equal
pub fn IRBuilder::icmp_eq(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(Eq, a, b)
}

///|
/// Integer not equal
pub fn IRBuilder::icmp_ne(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(Ne, a, b)
}

///|
/// Signed less than
pub fn IRBuilder::icmp_slt(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(Slt, a, b)
}

///|
/// Signed less than or equal
pub fn IRBuilder::icmp_sle(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(Sle, a, b)
}

///|
/// Signed greater than
pub fn IRBuilder::icmp_sgt(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(Sgt, a, b)
}

///|
/// Signed greater than or equal
pub fn IRBuilder::icmp_sge(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(Sge, a, b)
}

///|
/// Unsigned less than
pub fn IRBuilder::icmp_ult(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(Ult, a, b)
}

///|
/// Unsigned less than or equal
pub fn IRBuilder::icmp_ule(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(Ule, a, b)
}

///|
/// Unsigned greater than
pub fn IRBuilder::icmp_ugt(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(Ugt, a, b)
}

///|
/// Unsigned greater than or equal
pub fn IRBuilder::icmp_uge(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(Uge, a, b)
}

// ============ Floating Point Arithmetic ============

///|
/// Float add
pub fn IRBuilder::fadd(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Fadd, [a, b])
}

///|
/// Float subtract
pub fn IRBuilder::fsub(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Fsub, [a, b])
}

///|
/// Float multiply
pub fn IRBuilder::fmul(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Fmul, [a, b])
}

///|
/// Float divide
pub fn IRBuilder::fdiv(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Fdiv, [a, b])
}

///|
/// Float minimum
pub fn IRBuilder::fmin(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Fmin, [a, b])
}

///|
/// Float maximum
pub fn IRBuilder::fmax(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Fmax, [a, b])
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
  self.emit_inst(I32, Fcmp(cc), [a, b])
}

// ============ Float Unary Operations ============

///|
/// Float negate
pub fn IRBuilder::fneg(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Fneg, [a])
}

///|
/// Float absolute value
pub fn IRBuilder::fabs(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Fabs, [a])
}

///|
/// Float square root
pub fn IRBuilder::fsqrt(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Fsqrt, [a])
}

///|
/// Float ceiling
pub fn IRBuilder::fceil(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Fceil, [a])
}

///|
/// Float floor
pub fn IRBuilder::ffloor(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Ffloor, [a])
}

///|
/// Float truncate
pub fn IRBuilder::ftrunc(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Ftrunc, [a])
}

///|
/// Float nearest (round to nearest even)
pub fn IRBuilder::fnearest(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Fnearest, [a])
}

// ============ Conversions ============

///|
/// Reduce integer width (e.g., i64 -> i32)
pub fn IRBuilder::ireduce(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Ireduce, [a])
}

///|
/// Sign extend (e.g., i32 -> i64)
pub fn IRBuilder::sextend(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Sextend, [a])
}

///|
/// Zero extend (e.g., i32 -> i64)
pub fn IRBuilder::uextend(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Uextend, [a])
}

///|
/// Sign extend from 8 bits (in-place, keeps the same type)
/// Similar to ireduce(I8) + sextend(ty)
pub fn IRBuilder::sextend8(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Sextend8, [a])
}

///|
/// Sign extend from 16 bits (in-place, keeps the same type)
/// Similar to ireduce(I16) + sextend(ty)
pub fn IRBuilder::sextend16(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Sextend16, [a])
}

///|
/// Sign extend from 32 bits to 64 bits
/// Similar to ireduce(I32) + sextend(I64)
pub fn IRBuilder::sextend32(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(I64, Sextend32, [a])
}

///|
/// Promote float (f32 -> f64)
pub fn IRBuilder::fpromote(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(F64, Fpromote, [a])
}

///|
/// Demote float (f64 -> f32)
pub fn IRBuilder::fdemote(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(F32, Fdemote, [a])
}

///|
/// Float to signed int
pub fn IRBuilder::fcvt_to_sint(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, FcvtToSint, [a])
}

///|
/// Float to unsigned int
pub fn IRBuilder::fcvt_to_uint(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, FcvtToUint, [a])
}

///|
/// Float to signed int (saturating - NaN->0, overflow->max/min)
pub fn IRBuilder::fcvt_to_sint_sat(
  self : IRBuilder,
  ty : Type,
  a : Value,
) -> Value {
  self.emit_inst(ty, FcvtToSintSat, [a])
}

///|
/// Float to unsigned int (saturating - NaN->0, overflow->max, negative->0)
pub fn IRBuilder::fcvt_to_uint_sat(
  self : IRBuilder,
  ty : Type,
  a : Value,
) -> Value {
  self.emit_inst(ty, FcvtToUintSat, [a])
}

///|
/// Signed int to float
pub fn IRBuilder::sint_to_fcvt(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, SintToFcvt, [a])
}

///|
/// Unsigned int to float
pub fn IRBuilder::uint_to_fcvt(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, UintToFcvt, [a])
}

///|
/// Bitcast (reinterpret bits)
pub fn IRBuilder::bitcast(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Bitcast, [a])
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
  self.emit_inst(a.ty, Select, [cond, a, b])
}

///|
/// Copy value (for register allocation)
pub fn IRBuilder::copy(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Copy, [a])
}

// ============ Function Calls ============

///|
pub fn IRBuilder::call_symbol(
  self : IRBuilder,
  symbol : ExternalSymbol,
  result_ty : Type?,
  args : Array[Value],
) -> Value? {
  match result_ty {
    Some(ty) => Some(self.emit_inst(ty, Call(symbol), args))
    None => {
      self.emit_void_inst(Call(symbol), args)
      None
    }
  }
}

///|
pub fn IRBuilder::call_symbol_multi(
  self : IRBuilder,
  symbol : ExternalSymbol,
  result_types : Array[Type],
  args : Array[Value],
) -> Array[Value] {
  self.emit_multi_inst(result_types, Call(symbol), args)
}

// ============ Terminators ============

///|
/// Unconditional jump
pub fn IRBuilder::jump(
  self : IRBuilder,
  target : Block,
  args : Array[Value],
) -> Unit {
  if self.current_block is Some(block) {
    block.set_terminator(Jump(target.id, args))
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
  if self.current_block is Some(block) {
    block.set_terminator(Brz(cond, then_block.id, else_block.id))
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
  if self.current_block is Some(block) {
    block.set_terminator(Brnz(cond, then_block.id, else_block.id))
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
  if self.current_block is Some(block) {
    block.set_terminator(BrTable(index, target_ids, default_target.id))
  }
}

///|
/// Return from function
pub fn IRBuilder::return_(self : IRBuilder, values : Array[Value]) -> Unit {
  if self.current_block is Some(block) {
    block.set_terminator(Return(values))
  }
}

///|
/// Trap/unreachable
pub fn IRBuilder::trap(self : IRBuilder, reason : String) -> Unit {
  if self.current_block is Some(block) {
    block.set_terminator(Trap(reason))
  }
}

// ============ Raw Pointer Operations (for trampolines) ============

///|
/// Load from raw pointer (no bounds checking)
/// For trampoline code that operates on host memory
pub fn IRBuilder::load_ptr(
  self : IRBuilder,
  ty : Type,
  base : Value,
  offset : Value,
) -> Value {
  self.emit_inst(ty, LoadPtr(ty), [base, offset])
}

///|
/// Store to raw pointer (no bounds checking)
/// For trampoline code that operates on host memory
pub fn IRBuilder::store_ptr(
  self : IRBuilder,
  ty : Type,
  base : Value,
  value : Value,
  offset : Value,
) -> Unit {
  self.emit_void_inst(StorePtr(ty), [base, value, offset])
}

///|
/// Load narrow value from raw pointer (no bounds checking)
/// Loads 'bits' bits from memory and extends to result_ty
pub fn IRBuilder::load_ptr_narrow(
  self : IRBuilder,
  result_ty : Type,
  bits : Int,
  signed : Bool,
  base : Value,
  offset : Value,
) -> Value {
  self.emit_inst(result_ty, LoadPtrNarrow(result_ty, bits, signed), [
    base, offset,
  ])
}

///|
/// Store narrow value to raw pointer (no bounds checking)
/// Stores the low 'bits' bits of value to memory
pub fn IRBuilder::store_ptr_narrow(
  self : IRBuilder,
  bits : Int,
  base : Value,
  value : Value,
  offset : Value,
) -> Unit {
  self.emit_void_inst(StorePtrNarrow(bits), [base, value, offset])
}

///|
/// Call via function pointer with multiple return values
/// For calls through an indirect callee address.
///
/// Design: a callee environment operand is passed explicitly before user
/// arguments; callers can provide a null/sentinel value when their convention
/// does not use an environment.
///
/// Operand layout: [func_ptr, callee_env, user_args...]
pub fn IRBuilder::call_ptr(
  self : IRBuilder,
  func_ptr : Value,
  callee_env : Value,
  args : Array[Value],
  result_types : Array[Type],
) -> Array[Value] {
  let all_args : Array[Value] = [func_ptr, callee_env]
  for arg in args {
    all_args.push(arg)
  }
  let num_args = args.length()
  let num_results = result_types.length()
  self.emit_multi_inst(result_types, CallPtr(num_args, num_results), all_args)
}

// ============ SIMD Operations ============

///|
/// v128_const - emit a V128 constant
pub fn IRBuilder::v128_const(self : IRBuilder, bytes : Bytes) -> Value {
  self.emit_inst(V128, V128Const(bytes), [])
}

///|
/// v128_splat - broadcast a scalar to all lanes
pub fn IRBuilder::v128_splat8(self : IRBuilder, val : Value) -> Value {
  self.emit_inst(V128, V128Splat8, [val])
}

///|
pub fn IRBuilder::v128_splat16(self : IRBuilder, val : Value) -> Value {
  self.emit_inst(V128, V128Splat16, [val])
}

///|
pub fn IRBuilder::v128_splat32(self : IRBuilder, val : Value) -> Value {
  self.emit_inst(V128, V128Splat32, [val])
}

///|
pub fn IRBuilder::v128_splat64(self : IRBuilder, val : Value) -> Value {
  self.emit_inst(V128, V128Splat64, [val])
}

///|
pub fn IRBuilder::v128_splat_f32(self : IRBuilder, val : Value) -> Value {
  self.emit_inst(V128, V128SplatF32, [val])
}

///|
pub fn IRBuilder::v128_splat_f64(self : IRBuilder, val : Value) -> Value {
  self.emit_inst(V128, V128SplatF64, [val])
}

///|
/// Extract a lane from a v128 value
pub fn IRBuilder::v128_extract8s(
  self : IRBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(I32, V128ExtractLane8S(lane), [vec])
}

///|
pub fn IRBuilder::v128_extract8u(
  self : IRBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(I32, V128ExtractLane8U(lane), [vec])
}

///|
pub fn IRBuilder::v128_extract16s(
  self : IRBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(I32, V128ExtractLane16S(lane), [vec])
}

///|
pub fn IRBuilder::v128_extract16u(
  self : IRBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(I32, V128ExtractLane16U(lane), [vec])
}

///|
pub fn IRBuilder::v128_extract32(
  self : IRBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(I32, V128ExtractLane32(lane), [vec])
}

///|
pub fn IRBuilder::v128_extract64(
  self : IRBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(I64, V128ExtractLane64(lane), [vec])
}

///|
pub fn IRBuilder::v128_extract_f32(
  self : IRBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(F32, V128ExtractLaneF32(lane), [vec])
}

///|
pub fn IRBuilder::v128_extract_f64(
  self : IRBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(F64, V128ExtractLaneF64(lane), [vec])
}

///|
/// Replace a lane in a v128 value
pub fn IRBuilder::v128_replace8(
  self : IRBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(V128, V128ReplaceLane8(lane), [vec, val])
}

///|
pub fn IRBuilder::v128_replace16(
  self : IRBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(V128, V128ReplaceLane16(lane), [vec, val])
}

///|
pub fn IRBuilder::v128_replace32(
  self : IRBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(V128, V128ReplaceLane32(lane), [vec, val])
}

///|
pub fn IRBuilder::v128_replace64(
  self : IRBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(V128, V128ReplaceLane64(lane), [vec, val])
}

///|
pub fn IRBuilder::v128_replace_f32(
  self : IRBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(V128, V128ReplaceLaneF32(lane), [vec, val])
}

///|
pub fn IRBuilder::v128_replace_f64(
  self : IRBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(V128, V128ReplaceLaneF64(lane), [vec, val])
}

///|
/// Shuffle lanes from two v128 values
pub fn IRBuilder::v128_shuffle(
  self : IRBuilder,
  a : Value,
  b : Value,
  lanes : FixedArray[Int],
) -> Value {
  self.emit_inst(V128, V128Shuffle(lanes), [a, b])
}

///|
/// Swizzle lanes using indices from another v128
pub fn IRBuilder::v128_swizzle(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(V128, V128Swizzle, [a, b])
}

///|
/// Bitwise operations on v128
pub fn IRBuilder::v128_not(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(V128, V128Not, [a])
}

///|
pub fn IRBuilder::v128_and(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(V128, V128And, [a, b])
}

///|
pub fn IRBuilder::v128_andnot(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(V128, V128AndNot, [a, b])
}

///|
pub fn IRBuilder::v128_or(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(V128, V128Or, [a, b])
}

///|
pub fn IRBuilder::v128_xor(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(V128, V128Xor, [a, b])
}

///|
pub fn IRBuilder::v128_bitselect(
  self : IRBuilder,
  a : Value,
  b : Value,
  c : Value,
) -> Value {
  self.emit_inst(V128, V128Bitselect, [a, b, c])
}

///|
pub fn IRBuilder::v128_anytrue(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(I32, V128AnyTrue, [a])
}

///|
/// Generic SIMD instruction emitter
/// Use this for operations that follow the pattern: opcode, operands -> V128/I32
pub fn IRBuilder::v128_unary(
  self : IRBuilder,
  opcode : Opcode,
  a : Value,
) -> Value {
  self.emit_inst(V128, opcode, [a])
}

///|
pub fn IRBuilder::v128_binary(
  self : IRBuilder,
  opcode : Opcode,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(V128, opcode, [a, b])
}

///|
pub fn IRBuilder::v128_to_i32(
  self : IRBuilder,
  opcode : Opcode,
  a : Value,
) -> Value {
  self.emit_inst(I32, opcode, [a])
}

///|
pub fn IRBuilder::v128_shift(
  self : IRBuilder,
  opcode : Opcode,
  vec : Value,
  shift : Value,
) -> Value {
  self.emit_inst(V128, opcode, [vec, shift])
}

///|
/// SIMD load with effective address (for complex SIMD loads)
pub fn IRBuilder::v128_load_with_addr(
  self : IRBuilder,
  opcode : Opcode,
  effective_addr : Value,
) -> Value {
  self.emit_inst(V128, opcode, [effective_addr])
}

///|
/// SIMD load lane with effective address and existing vector
pub fn IRBuilder::v128_load_lane_with_addr(
  self : IRBuilder,
  opcode : Opcode,
  effective_addr : Value,
  vec : Value,
) -> Value {
  self.emit_inst(V128, opcode, [effective_addr, vec])
}

///|
/// SIMD store lane with effective address and vector (void)
pub fn IRBuilder::v128_store_lane_with_addr(
  self : IRBuilder,
  opcode : Opcode,
  effective_addr : Value,
  vec : Value,
) -> Unit {
  self.emit_void_inst(opcode, [effective_addr, vec])
}
