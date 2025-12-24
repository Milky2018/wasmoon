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
  if self.current_block is Some(block) {
    block.add_inst(inst)
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
  if self.current_block is Some(block) {
    block.add_inst(inst)
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
/// Note: We pack the f32 bits into the Double's bit representation to preserve
/// NaN payloads. Using value.to_double() would go through the FPU and convert
/// signaling NaNs to quiet NaNs.
pub fn IRBuilder::fconst_f32(self : IRBuilder, value : Float) -> Value {
  let f32_bits = value.reinterpret_as_int().to_int64()
  self.fconst(Type::F32, f32_bits.reinterpret_as_double())
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

///|
/// Count leading zeros
pub fn IRBuilder::clz(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Clz, [a])
}

///|
/// Count trailing zeros
pub fn IRBuilder::ctz(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Ctz, [a])
}

///|
/// Population count (count number of 1 bits)
pub fn IRBuilder::popcnt(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Popcnt, [a])
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
/// Sign extend from 8 bits (in-place, keeps the same type)
/// Like Cranelift's ireduce(I8) + sextend(ty)
pub fn IRBuilder::sextend8(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Opcode::Sextend8, [a])
}

///|
/// Sign extend from 16 bits (in-place, keeps the same type)
/// Like Cranelift's ireduce(I16) + sextend(ty)
pub fn IRBuilder::sextend16(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Opcode::Sextend16, [a])
}

///|
/// Sign extend from 32 bits to 64 bits
/// Like Cranelift's ireduce(I32) + sextend(I64)
pub fn IRBuilder::sextend32(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(Type::I64, Opcode::Sextend32, [a])
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
/// Float to signed int (saturating - NaN->0, overflow->max/min)
pub fn IRBuilder::fcvt_to_sint_sat(
  self : IRBuilder,
  ty : Type,
  a : Value,
) -> Value {
  self.emit_inst(ty, Opcode::FcvtToSintSat, [a])
}

///|
/// Float to unsigned int (saturating - NaN->0, overflow->max, negative->0)
pub fn IRBuilder::fcvt_to_uint_sat(
  self : IRBuilder,
  ty : Type,
  a : Value,
) -> Value {
  self.emit_inst(ty, Opcode::FcvtToUintSat, [a])
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

///|
/// Grow memory by delta pages, returns previous size in pages or -1 on failure
/// max_pages: maximum allowed pages (None = no limit)
pub fn IRBuilder::memory_grow(
  self : IRBuilder,
  delta : Value,
  max_pages? : Int,
) -> Value {
  self.emit_inst(Type::I32, Opcode::MemoryGrow(max_pages), [delta])
}

///|
/// Get current memory size in pages
pub fn IRBuilder::memory_size(self : IRBuilder) -> Value {
  self.emit_inst(Type::I32, Opcode::MemorySize, [])
}

///|
/// Fill memory region with a byte value
/// Operands: dst (i32), val (i32), size (i32)
/// No return value
pub fn IRBuilder::memory_fill(
  self : IRBuilder,
  dst : Value,
  val : Value,
  size : Value,
) -> Unit {
  self.emit_void_inst(Opcode::MemoryFill, [dst, val, size])
}

///|
/// Copy memory region
/// Operands: dst (i32), src (i32), size (i32)
/// No return value
pub fn IRBuilder::memory_copy(
  self : IRBuilder,
  dst : Value,
  src : Value,
  size : Value,
) -> Unit {
  self.emit_void_inst(Opcode::MemoryCopy, [dst, src, size])
}

// ============ Table Operations ============

///|
/// Get element from table (for reference types)
/// Returns i64 (function reference/pointer)
pub fn IRBuilder::table_get(
  self : IRBuilder,
  table_idx : Int,
  elem_idx : Value,
) -> Value {
  self.emit_inst(Type::I64, Opcode::TableGet(table_idx), [elem_idx])
}

///|
/// Set element in table (for reference types)
pub fn IRBuilder::table_set(
  self : IRBuilder,
  table_idx : Int,
  elem_idx : Value,
  value : Value,
) -> Unit {
  self.emit_void_inst(Opcode::TableSet(table_idx), [elem_idx, value])
}

///|
/// Get current size of table (number of elements)
pub fn IRBuilder::table_size(self : IRBuilder, table_idx : Int) -> Value {
  self.emit_inst(Type::I32, Opcode::TableSize(table_idx), [])
}

///|
/// Grow table by delta elements, initializing new elements with init_value
/// Returns previous size (as i32), or -1 if grow failed
pub fn IRBuilder::table_grow(
  self : IRBuilder,
  table_idx : Int,
  delta : Value,
  init_value : Value,
) -> Value {
  self.emit_inst(Type::I32, Opcode::TableGrow(table_idx), [delta, init_value])
}

///|
/// Get function reference (tagged function pointer) for storing in tables
/// The pointer is tagged with FUNCREF_TAG (bit 61) for ref.test detection
pub fn IRBuilder::get_func_ref(self : IRBuilder, func_idx : Int) -> Value {
  self.emit_inst(Type::I64, Opcode::GetFuncRef(func_idx), [])
}

///|
/// Get global variable value
pub fn IRBuilder::global_get(
  self : IRBuilder,
  global_idx : Int,
  ty : Type,
) -> Value {
  self.emit_inst(ty, Opcode::GlobalGet(global_idx), [])
}

///|
/// Set global variable value
pub fn IRBuilder::global_set(
  self : IRBuilder,
  global_idx : Int,
  value : Value,
) -> Unit {
  self.emit_void_inst(Opcode::GlobalSet(global_idx), [value])
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
/// Direct function call (single return value)
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
/// Direct function call with multiple return values
pub fn IRBuilder::call_multi(
  self : IRBuilder,
  func_idx : Int,
  result_types : Array[Type],
  args : Array[Value],
) -> Array[Value] {
  if result_types.length() == 0 {
    self.emit_void_inst(Opcode::Call(func_idx), args)
    return []
  }
  // Create result values for each return type
  let results : Array[Value] = []
  for ty in result_types {
    results.push(self.func.new_value(ty))
  }
  // Create instruction with multiple results
  let inst = Inst::new_multi(results, Opcode::Call(func_idx), args)
  if self.current_block is Some(block) {
    block.add_inst(inst)
  }
  results
}

///|
/// Tail call with multiple return values
/// Emits a return_call instruction (does not return to caller)
pub fn IRBuilder::return_call_multi(
  self : IRBuilder,
  func_idx : Int,
  args : Array[Value],
) -> Unit {
  self.emit_void_inst(Opcode::ReturnCall(func_idx), args)
}

///|
/// Tail call indirect with multiple return values
/// Emits a return_call_indirect instruction (does not return to caller)
pub fn IRBuilder::return_call_indirect_multi(
  self : IRBuilder,
  type_idx : Int,
  table_idx : Int,
  callee : Value,
  args : Array[Value],
) -> Unit {
  let all_args : Array[Value] = [callee]
  for arg in args {
    all_args.push(arg)
  }
  self.emit_void_inst(Opcode::ReturnCallIndirect(type_idx, table_idx), all_args)
}

///|
/// Tail call through function reference
/// Emits a return_call_ref instruction (does not return to caller)
pub fn IRBuilder::return_call_ref_multi(
  self : IRBuilder,
  type_idx : Int,
  func_ref : Value,
  args : Array[Value],
) -> Unit {
  let all_args : Array[Value] = [func_ref]
  for arg in args {
    all_args.push(arg)
  }
  self.emit_void_inst(Opcode::ReturnCallRef(type_idx), all_args)
}

///|
/// Indirect function call (single return value)
pub fn IRBuilder::call_indirect(
  self : IRBuilder,
  type_idx : Int,
  table_idx : Int,
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
      Some(
        self.emit_inst(ty, Opcode::CallIndirect(type_idx, table_idx), all_args),
      )
    None => {
      self.emit_void_inst(Opcode::CallIndirect(type_idx, table_idx), all_args)
      None
    }
  }
}

///|
/// Indirect function call with multiple return values
pub fn IRBuilder::call_indirect_multi(
  self : IRBuilder,
  type_idx : Int,
  table_idx : Int,
  result_types : Array[Type],
  callee : Value,
  args : Array[Value],
) -> Array[Value] {
  let all_args : Array[Value] = [callee]
  for arg in args {
    all_args.push(arg)
  }
  if result_types.length() == 0 {
    self.emit_void_inst(Opcode::CallIndirect(type_idx, table_idx), all_args)
    return []
  }
  // Create result values for each return type
  let results : Array[Value] = []
  for ty in result_types {
    results.push(self.func.new_value(ty))
  }
  // Create instruction with multiple results
  let inst = Inst::new_multi(
    results,
    Opcode::CallIndirect(type_idx, table_idx),
    all_args,
  )
  if self.current_block is Some(block) {
    block.add_inst(inst)
  }
  results
}

///|
/// Call through function reference with multiple return values
pub fn IRBuilder::call_ref_multi(
  self : IRBuilder,
  type_idx : Int,
  result_types : Array[Type],
  func_ref : Value,
  args : Array[Value],
) -> Array[Value] {
  let all_args : Array[Value] = [func_ref]
  for arg in args {
    all_args.push(arg)
  }
  if result_types.length() == 0 {
    self.emit_void_inst(Opcode::CallRef(type_idx), all_args)
    return []
  }
  // Create result values for each return type
  let results : Array[Value] = []
  for ty in result_types {
    results.push(self.func.new_value(ty))
  }
  // Create instruction with multiple results
  let inst = Inst::new_multi(results, Opcode::CallRef(type_idx), all_args)
  if self.current_block is Some(block) {
    block.add_inst(inst)
  }
  results
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
    block.set_terminator(Terminator::Jump(target.id, args))
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
    block.set_terminator(Terminator::Brz(cond, then_block.id, else_block.id))
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
    block.set_terminator(Terminator::Brnz(cond, then_block.id, else_block.id))
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
    block.set_terminator(
      Terminator::BrTable(index, target_ids, default_target.id),
    )
  }
}

///|
/// Return from function
pub fn IRBuilder::return_(self : IRBuilder, values : Array[Value]) -> Unit {
  if self.current_block is Some(block) {
    block.set_terminator(Terminator::Return(values))
  }
}

///|
/// Trap/unreachable
pub fn IRBuilder::trap(self : IRBuilder, reason : String) -> Unit {
  if self.current_block is Some(block) {
    block.set_terminator(Terminator::Trap(reason))
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
  self.emit_inst(ty, Opcode::LoadPtr(ty), [base, offset])
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
  self.emit_void_inst(Opcode::StorePtr(ty), [base, value, offset])
}

///|
/// Call via function pointer with multiple return values
/// For trampolines calling WASM functions
///
/// Following Cranelift's design: callee_vmctx and caller_vmctx are explicit
/// arguments, allowing the register allocator to properly handle values that
/// need to survive across the call (like values_vec in trampolines).
///
/// Operand layout: [func_ptr, callee_vmctx, caller_vmctx, user_args...]
pub fn IRBuilder::call_ptr(
  self : IRBuilder,
  func_ptr : Value,
  callee_vmctx : Value,
  caller_vmctx : Value,
  args : Array[Value],
  result_types : Array[Type],
) -> Array[Value] {
  let all_args : Array[Value] = [func_ptr, callee_vmctx, caller_vmctx]
  for arg in args {
    all_args.push(arg)
  }
  let num_args = args.length()
  let num_results = result_types.length()
  if num_results == 0 {
    self.emit_void_inst(Opcode::CallPtr(num_args, 0), all_args)
    return []
  }
  // Create result values for each return type
  let results : Array[Value] = []
  for ty in result_types {
    results.push(self.func.new_value(ty))
  }
  // Create instruction with multiple results
  let inst = Inst::new_multi(
    results,
    Opcode::CallPtr(num_args, num_results),
    all_args,
  )
  if self.current_block is Some(block) {
    block.add_inst(inst)
  }
  results
}

// ============ GC Operations ============

///|
/// Allocate a new struct with given field values
pub fn IRBuilder::struct_new(
  self : IRBuilder,
  type_idx : Int,
  fields : Array[Value],
) -> Value {
  self.emit_inst(Type::I64, Opcode::StructNew(type_idx), fields)
}

///|
/// Allocate a new struct with default values
pub fn IRBuilder::struct_new_default(self : IRBuilder, type_idx : Int) -> Value {
  self.emit_inst(Type::I64, Opcode::StructNewDefault(type_idx), [])
}

///|
/// Get a field from a struct
pub fn IRBuilder::struct_get(
  self : IRBuilder,
  type_idx : Int,
  field_idx : Int,
  struct_ref : Value,
) -> Value {
  // Result type depends on field type, but we use I64 as a generic reference
  self.emit_inst(Type::I64, Opcode::StructGet(type_idx, field_idx), [struct_ref])
}

///|
/// Get a field from a struct (signed extension)
pub fn IRBuilder::struct_get_s(
  self : IRBuilder,
  type_idx : Int,
  field_idx : Int,
  struct_ref : Value,
) -> Value {
  self.emit_inst(Type::I64, Opcode::StructGetS(type_idx, field_idx), [
    struct_ref,
  ])
}

///|
/// Get a field from a struct (unsigned extension)
pub fn IRBuilder::struct_get_u(
  self : IRBuilder,
  type_idx : Int,
  field_idx : Int,
  struct_ref : Value,
) -> Value {
  self.emit_inst(Type::I64, Opcode::StructGetU(type_idx, field_idx), [
    struct_ref,
  ])
}

///|
/// Set a field in a struct
pub fn IRBuilder::struct_set(
  self : IRBuilder,
  type_idx : Int,
  field_idx : Int,
  struct_ref : Value,
  value : Value,
) -> Unit {
  self.emit_void_inst(Opcode::StructSet(type_idx, field_idx), [
    struct_ref, value,
  ])
}

///|
/// Allocate a new array with init value and length
pub fn IRBuilder::array_new(
  self : IRBuilder,
  type_idx : Int,
  init_value : Value,
  length : Value,
) -> Value {
  self.emit_inst(Type::I64, Opcode::ArrayNew(type_idx), [init_value, length])
}

///|
/// Allocate a new array with default values
pub fn IRBuilder::array_new_default(
  self : IRBuilder,
  type_idx : Int,
  length : Value,
) -> Value {
  self.emit_inst(Type::I64, Opcode::ArrayNewDefault(type_idx), [length])
}

///|
/// Allocate a fixed-size array with given elements
pub fn IRBuilder::array_new_fixed(
  self : IRBuilder,
  type_idx : Int,
  count : Int,
  elements : Array[Value],
) -> Value {
  self.emit_inst(Type::I64, Opcode::ArrayNewFixed(type_idx, count), elements)
}

///|
/// Get an element from an array
pub fn IRBuilder::array_get(
  self : IRBuilder,
  type_idx : Int,
  array_ref : Value,
  index : Value,
) -> Value {
  self.emit_inst(Type::I64, Opcode::ArrayGet(type_idx), [array_ref, index])
}

///|
/// Get an element from an array (signed extension)
pub fn IRBuilder::array_get_s(
  self : IRBuilder,
  type_idx : Int,
  array_ref : Value,
  index : Value,
) -> Value {
  self.emit_inst(Type::I64, Opcode::ArrayGetS(type_idx), [array_ref, index])
}

///|
/// Get an element from an array (unsigned extension)
pub fn IRBuilder::array_get_u(
  self : IRBuilder,
  type_idx : Int,
  array_ref : Value,
  index : Value,
) -> Value {
  self.emit_inst(Type::I64, Opcode::ArrayGetU(type_idx), [array_ref, index])
}

///|
/// Set an element in an array
pub fn IRBuilder::array_set(
  self : IRBuilder,
  type_idx : Int,
  array_ref : Value,
  index : Value,
  value : Value,
) -> Unit {
  self.emit_void_inst(Opcode::ArraySet(type_idx), [array_ref, index, value])
}

///|
/// Get array length
pub fn IRBuilder::array_len(self : IRBuilder, array_ref : Value) -> Value {
  self.emit_inst(Type::I32, Opcode::ArrayLen, [array_ref])
}

///|
/// Fill array elements with a value
pub fn IRBuilder::array_fill(
  self : IRBuilder,
  type_idx : Int,
  array_ref : Value,
  offset : Value,
  value : Value,
  count : Value,
) -> Unit {
  self.emit_void_inst(Opcode::ArrayFill(type_idx), [
    array_ref, offset, value, count,
  ])
}

///|
/// Copy elements between arrays
pub fn IRBuilder::array_copy(
  self : IRBuilder,
  dst_type_idx : Int,
  src_type_idx : Int,
  dst : Value,
  dst_offset : Value,
  src : Value,
  src_offset : Value,
  count : Value,
) -> Unit {
  self.emit_void_inst(Opcode::ArrayCopy(dst_type_idx, src_type_idx), [
    dst, dst_offset, src, src_offset, count,
  ])
}

///|
/// Create i31 reference from i32
pub fn IRBuilder::i31_new(self : IRBuilder, value : Value) -> Value {
  self.emit_inst(Type::I64, Opcode::I31New, [value])
}

///|
/// Get signed i32 from i31 reference
pub fn IRBuilder::i31_get_s(self : IRBuilder, i31_ref : Value) -> Value {
  self.emit_inst(Type::I32, Opcode::I31GetS, [i31_ref])
}

///|
/// Get unsigned i32 from i31 reference
pub fn IRBuilder::i31_get_u(self : IRBuilder, i31_ref : Value) -> Value {
  self.emit_inst(Type::I32, Opcode::I31GetU, [i31_ref])
}

///|
/// Test if reference is of type (returns i32 0 or 1)
pub fn IRBuilder::ref_test(
  self : IRBuilder,
  type_idx : Int,
  nullable : Bool,
  ref_val : Value,
) -> Value {
  self.emit_inst(Type::I32, Opcode::RefTest(type_idx, nullable), [ref_val])
}

///|
/// Cast reference to type (traps on failure)
pub fn IRBuilder::ref_cast(
  self : IRBuilder,
  type_idx : Int,
  nullable : Bool,
  ref_val : Value,
) -> Value {
  self.emit_inst(Type::I64, Opcode::RefCast(type_idx, nullable), [ref_val])
}

///|
/// Convert externref to anyref
pub fn IRBuilder::any_convert_extern(
  self : IRBuilder,
  extern_ref : Value,
) -> Value {
  self.emit_inst(Type::I64, Opcode::AnyConvertExtern, [extern_ref])
}

///|
/// Convert anyref to externref
pub fn IRBuilder::extern_convert_any(
  self : IRBuilder,
  any_ref : Value,
) -> Value {
  self.emit_inst(Type::I64, Opcode::ExternConvertAny, [any_ref])
}

///|
/// ref.eq - compare two references for equality
pub fn IRBuilder::ref_eq(self : IRBuilder, ref1 : Value, ref2 : Value) -> Value {
  self.emit_inst(Type::I32, Opcode::RefEq, [ref1, ref2])
}
