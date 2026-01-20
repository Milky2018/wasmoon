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
/// Unsigned multiply high (i64 only)
pub fn IRBuilder::umulh(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Umulh, [a, b])
}

///|
/// Signed multiply high (i64 only)
pub fn IRBuilder::smulh(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Opcode::Smulh, [a, b])
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
/// Similar to ireduce(I8) + sextend(ty)
pub fn IRBuilder::sextend8(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Opcode::Sextend8, [a])
}

///|
/// Sign extend from 16 bits (in-place, keeps the same type)
/// Similar to ireduce(I16) + sextend(ty)
pub fn IRBuilder::sextend16(self : IRBuilder, ty : Type, a : Value) -> Value {
  self.emit_inst(ty, Opcode::Sextend16, [a])
}

///|
/// Sign extend from 32 bits to 64 bits
/// Similar to ireduce(I32) + sextend(I64)
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

// Note: Load/Store memory methods removed - now use FuncEnvironment.translate_memory_load/store
// which generate LoadPtr/StorePtr with explicit bounds checks

///|
/// Load linear memory base pointer from vmctx for a given memory index.
/// Operand: vmctx (i64 pointer)
/// Result: i64 base pointer
pub fn IRBuilder::load_mem_base(
  self : IRBuilder,
  vmctx : Value,
  memidx : Int,
) -> Value {
  self.emit_inst(Type::I64, Opcode::LoadMemBase(memidx), [vmctx])
}

///|
/// Grow memory by delta pages, returns previous size in pages or -1 on failure
/// memidx: memory index
/// max_pages: maximum allowed pages (None = no limit)
/// is_memory64: true if memory uses 64-bit addresses (returns i64)
pub fn IRBuilder::memory_grow(
  self : IRBuilder,
  memidx : Int,
  delta : Value,
  max_pages? : Int,
  is_memory64? : Bool = false,
) -> Value {
  let result_type = if is_memory64 { Type::I64 } else { Type::I32 }
  self.emit_inst(result_type, Opcode::MemoryGrow(memidx, max_pages), [delta])
}

///|
/// Get current memory size in pages
/// is_memory64: true if memory uses 64-bit addresses (returns i64)
pub fn IRBuilder::memory_size(
  self : IRBuilder,
  memidx : Int,
  is_memory64? : Bool = false,
) -> Value {
  let result_type = if is_memory64 { Type::I64 } else { Type::I32 }
  self.emit_inst(result_type, Opcode::MemorySize(memidx), [])
}

///|
/// Fill memory region with a byte value
/// Operands: dst (i32), val (i32), size (i32)
/// No return value
pub fn IRBuilder::memory_fill(
  self : IRBuilder,
  memidx : Int,
  dst : Value,
  val : Value,
  size : Value,
) -> Unit {
  self.emit_void_inst(Opcode::MemoryFill(memidx), [dst, val, size])
}

///|
/// Copy memory region
/// dst_memidx, src_memidx: destination and source memory indices
/// Operands: dst (i32), src (i32), size (i32)
/// No return value
pub fn IRBuilder::memory_copy(
  self : IRBuilder,
  dst_memidx : Int,
  src_memidx : Int,
  dst : Value,
  src : Value,
  size : Value,
) -> Unit {
  self.emit_void_inst(Opcode::MemoryCopy(dst_memidx, src_memidx), [
    dst, src, size,
  ])
}

///|
/// Initialize memory from data segment
/// memidx: memory index, data_idx: data segment index
/// Operands: dst (memory offset), src (data offset), size
/// No return value
pub fn IRBuilder::memory_init(
  self : IRBuilder,
  memidx : Int,
  data_idx : Int,
  dst : Value,
  src : Value,
  size : Value,
) -> Unit {
  self.emit_void_inst(Opcode::MemoryInit(memidx, data_idx), [dst, src, size])
}

///|
/// Drop data segment (mark as dropped)
/// data_idx: data segment index
/// No operands, no return value
pub fn IRBuilder::data_drop(self : IRBuilder, data_idx : Int) -> Unit {
  self.emit_void_inst(Opcode::DataDrop(data_idx), [])
}

// ============ Table Operations ============
// NOTE: table_get, table_set, table_size are desugared at IR translation phase via FuncEnvironment
// Use FuncEnvironment::translate_table_get/set/size instead

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
/// Fill table region with a value
/// table_idx: table index
/// Operands: dst (table offset), val (ref value), size
/// No return value
pub fn IRBuilder::table_fill(
  self : IRBuilder,
  table_idx : Int,
  dst : Value,
  val : Value,
  size : Value,
) -> Unit {
  self.emit_void_inst(Opcode::TableFill(table_idx), [dst, val, size])
}

///|
/// Copy table region
/// dst_table_idx, src_table_idx: destination and source table indices
/// Operands: dst (table offset), src (table offset), size
/// No return value
pub fn IRBuilder::table_copy(
  self : IRBuilder,
  dst_table_idx : Int,
  src_table_idx : Int,
  dst : Value,
  src : Value,
  size : Value,
) -> Unit {
  self.emit_void_inst(Opcode::TableCopy(dst_table_idx, src_table_idx), [
    dst, src, size,
  ])
}

///|
/// Initialize table from element segment
/// table_idx: table index, elem_idx: element segment index
/// Operands: dst (table offset), src (elem offset), size
/// No return value
pub fn IRBuilder::table_init(
  self : IRBuilder,
  table_idx : Int,
  elem_idx : Int,
  dst : Value,
  src : Value,
  size : Value,
) -> Unit {
  self.emit_void_inst(Opcode::TableInit(table_idx, elem_idx), [dst, src, size])
}

///|
/// Drop element segment (mark as dropped)
/// elem_idx: element segment index
/// No operands, no return value
pub fn IRBuilder::elem_drop(self : IRBuilder, elem_idx : Int) -> Unit {
  self.emit_void_inst(Opcode::ElemDrop(elem_idx), [])
}

///|
/// Get function reference (tagged function pointer) for storing in tables
/// The pointer is tagged with FUNCREF_TAG (bit 61) for ref.test detection
pub fn IRBuilder::get_func_ref(self : IRBuilder, func_idx : Int) -> Value {
  self.emit_inst(Type::FuncRef, Opcode::GetFuncRef(func_idx), [])
}

// NOTE: global_get, global_set are desugared at IR translation phase via FuncEnvironment
// Use FuncEnvironment::translate_global_get/set instead

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
  self.emit_inst(result_ty, Opcode::LoadPtrNarrow(result_ty, bits, signed), [
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
  self.emit_void_inst(Opcode::StorePtrNarrow(bits), [base, value, offset])
}

///|
/// Call via function pointer with multiple return values
/// For trampolines calling WASM functions
///
/// Design: VMContext is an explicit special parameter (Cranelift-style).
///
/// Operand layout: [func_ptr, vmctx, user_args...]
pub fn IRBuilder::call_ptr(
  self : IRBuilder,
  func_ptr : Value,
  vmctx : Value,
  args : Array[Value],
  result_types : Array[Type],
) -> Array[Value] {
  let all_args : Array[Value] = [func_ptr, vmctx]
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
  field_type : Type,
) -> Value {
  self.emit_inst(field_type, Opcode::StructGet(type_idx, field_idx), [
    struct_ref,
  ])
}

///|
/// Get a field from a struct (signed extension)
/// byte_width: 1 for i8, 2 for i16
pub fn IRBuilder::struct_get_s(
  self : IRBuilder,
  type_idx : Int,
  field_idx : Int,
  struct_ref : Value,
  field_type : Type,
  byte_width : Int,
) -> Value {
  self.emit_inst(
    field_type,
    Opcode::StructGetS(type_idx, field_idx, byte_width),
    [struct_ref],
  )
}

///|
/// Get a field from a struct (unsigned extension)
/// byte_width: 1 for i8, 2 for i16
pub fn IRBuilder::struct_get_u(
  self : IRBuilder,
  type_idx : Int,
  field_idx : Int,
  struct_ref : Value,
  field_type : Type,
  byte_width : Int,
) -> Value {
  self.emit_inst(
    field_type,
    Opcode::StructGetU(type_idx, field_idx, byte_width),
    [struct_ref],
  )
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
  element_type : Type,
) -> Value {
  self.emit_inst(element_type, Opcode::ArrayGet(type_idx), [array_ref, index])
}

///|
/// Get an element from an array (signed extension)
/// byte_width: 1 for i8, 2 for i16
pub fn IRBuilder::array_get_s(
  self : IRBuilder,
  type_idx : Int,
  array_ref : Value,
  index : Value,
  element_type : Type,
  byte_width : Int,
) -> Value {
  self.emit_inst(element_type, Opcode::ArrayGetS(type_idx, byte_width), [
    array_ref, index,
  ])
}

///|
/// Get an element from an array (unsigned extension)
/// byte_width: 1 for i8, 2 for i16
pub fn IRBuilder::array_get_u(
  self : IRBuilder,
  type_idx : Int,
  array_ref : Value,
  index : Value,
  element_type : Type,
  byte_width : Int,
) -> Value {
  self.emit_inst(element_type, Opcode::ArrayGetU(type_idx, byte_width), [
    array_ref, index,
  ])
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
/// Create array from data segment
/// type_idx: array type index, data_idx: data segment index
/// Operands: data_offset, length
/// Returns: array reference (i64)
pub fn IRBuilder::array_new_data(
  self : IRBuilder,
  type_idx : Int,
  data_idx : Int,
  data_offset : Value,
  length : Value,
) -> Value {
  self.emit_inst(Type::I64, Opcode::ArrayNewData(type_idx, data_idx), [
    data_offset, length,
  ])
}

///|
/// Create array from element segment
/// type_idx: array type index, elem_idx: element segment index
/// Operands: elem_offset, length
/// Returns: array reference (i64)
pub fn IRBuilder::array_new_elem(
  self : IRBuilder,
  type_idx : Int,
  elem_idx : Int,
  elem_offset : Value,
  length : Value,
) -> Value {
  self.emit_inst(Type::I64, Opcode::ArrayNewElem(type_idx, elem_idx), [
    elem_offset, length,
  ])
}

///|
/// Initialize array from data segment
/// type_idx: array type index, data_idx: data segment index
/// Operands: arrayref, arr_offset, data_offset, length
/// No return value
pub fn IRBuilder::array_init_data(
  self : IRBuilder,
  type_idx : Int,
  data_idx : Int,
  array_ref : Value,
  arr_offset : Value,
  data_offset : Value,
  length : Value,
) -> Unit {
  self.emit_void_inst(Opcode::ArrayInitData(type_idx, data_idx), [
    array_ref, arr_offset, data_offset, length,
  ])
}

///|
/// Initialize array from element segment
/// type_idx: array type index, elem_idx: element segment index
/// Operands: arrayref, arr_offset, elem_offset, length
/// No return value
pub fn IRBuilder::array_init_elem(
  self : IRBuilder,
  type_idx : Int,
  elem_idx : Int,
  array_ref : Value,
  arr_offset : Value,
  elem_offset : Value,
  length : Value,
) -> Unit {
  self.emit_void_inst(Opcode::ArrayInitElem(type_idx, elem_idx), [
    array_ref, arr_offset, elem_offset, length,
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

// ============ Exception Handling ============

///|
/// emit_throw - throw an exception with the given tag
pub fn IRBuilder::emit_throw(
  self : IRBuilder,
  tag_idx : Int,
  values : Array[Value],
) -> Unit {
  self.emit_void_inst(Opcode::Throw(tag_idx), values)
}

///|
/// emit_throw_ref - re-throw an exception from an exnref
pub fn IRBuilder::emit_throw_ref(self : IRBuilder, exnref : Value) -> Unit {
  self.emit_void_inst(Opcode::ThrowRef, [exnref])
}

///|
/// try_table_begin - setup exception handler, returns setjmp result
/// Returns 0 on normal entry, handler_id on exception catch
pub fn IRBuilder::try_table_begin(self : IRBuilder, handler_id : Int) -> Value {
  self.emit_inst(Type::I32, Opcode::TryTableBegin(handler_id), [])
}

///|
/// try_table_end - pop exception handler
pub fn IRBuilder::try_table_end(self : IRBuilder, handler_id : Int) -> Unit {
  self.emit_void_inst(Opcode::TryTableEnd(handler_id), [])
}

///|
/// get_exception_tag - get tag of caught exception
pub fn IRBuilder::get_exception_tag(self : IRBuilder) -> Value {
  self.emit_inst(Type::I32, Opcode::GetExceptionTag, [])
}

///|
/// get_exception_value - get exception value at index
pub fn IRBuilder::get_exception_value(self : IRBuilder, idx : Int) -> Value {
  self.emit_inst(Type::I64, Opcode::GetExceptionValue(idx), [])
}

///|
/// get_exception_value_count - get number of exception values
pub fn IRBuilder::get_exception_value_count(self : IRBuilder) -> Value {
  self.emit_inst(Type::I32, Opcode::GetExceptionValueCount, [])
}

///|
/// delegate - delegate exception to outer handler at depth
pub fn IRBuilder::delegate(self : IRBuilder, depth : Int) -> Unit {
  self.emit_void_inst(Opcode::Delegate(depth), [])
}

///|
/// spill_locals_for_throw - save all locals before throw so catch handlers see throw-time values
pub fn IRBuilder::spill_locals_for_throw(
  self : IRBuilder,
  locals : Array[Value],
) -> Unit {
  self.emit_void_inst(Opcode::SpillLocalsForThrow(locals.length()), locals)
}

///|
/// get_spilled_local - load a spilled local value at index (for catch handlers)
pub fn IRBuilder::get_spilled_local(self : IRBuilder, idx : Int) -> Value {
  self.emit_inst(Type::I64, Opcode::GetSpilledLocal(idx), [])
}

// ============ SIMD Operations ============

///|
/// v128_const - emit a V128 constant
pub fn IRBuilder::v128_const(self : IRBuilder, bytes : Bytes) -> Value {
  self.emit_inst(Type::V128, Opcode::V128Const(bytes), [])
}

///|
/// v128_splat - broadcast a scalar to all lanes
pub fn IRBuilder::v128_splat8(self : IRBuilder, val : Value) -> Value {
  self.emit_inst(Type::V128, Opcode::V128Splat8, [val])
}

///|
pub fn IRBuilder::v128_splat16(self : IRBuilder, val : Value) -> Value {
  self.emit_inst(Type::V128, Opcode::V128Splat16, [val])
}

///|
pub fn IRBuilder::v128_splat32(self : IRBuilder, val : Value) -> Value {
  self.emit_inst(Type::V128, Opcode::V128Splat32, [val])
}

///|
pub fn IRBuilder::v128_splat64(self : IRBuilder, val : Value) -> Value {
  self.emit_inst(Type::V128, Opcode::V128Splat64, [val])
}

///|
pub fn IRBuilder::v128_splat_f32(self : IRBuilder, val : Value) -> Value {
  self.emit_inst(Type::V128, Opcode::V128SplatF32, [val])
}

///|
pub fn IRBuilder::v128_splat_f64(self : IRBuilder, val : Value) -> Value {
  self.emit_inst(Type::V128, Opcode::V128SplatF64, [val])
}

///|
/// Extract a lane from a v128 value
pub fn IRBuilder::v128_extract8s(
  self : IRBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(Type::I32, Opcode::V128ExtractLane8S(lane), [vec])
}

///|
pub fn IRBuilder::v128_extract8u(
  self : IRBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(Type::I32, Opcode::V128ExtractLane8U(lane), [vec])
}

///|
pub fn IRBuilder::v128_extract16s(
  self : IRBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(Type::I32, Opcode::V128ExtractLane16S(lane), [vec])
}

///|
pub fn IRBuilder::v128_extract16u(
  self : IRBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(Type::I32, Opcode::V128ExtractLane16U(lane), [vec])
}

///|
pub fn IRBuilder::v128_extract32(
  self : IRBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(Type::I32, Opcode::V128ExtractLane32(lane), [vec])
}

///|
pub fn IRBuilder::v128_extract64(
  self : IRBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(Type::I64, Opcode::V128ExtractLane64(lane), [vec])
}

///|
pub fn IRBuilder::v128_extract_f32(
  self : IRBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(Type::F32, Opcode::V128ExtractLaneF32(lane), [vec])
}

///|
pub fn IRBuilder::v128_extract_f64(
  self : IRBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(Type::F64, Opcode::V128ExtractLaneF64(lane), [vec])
}

///|
/// Replace a lane in a v128 value
pub fn IRBuilder::v128_replace8(
  self : IRBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(Type::V128, Opcode::V128ReplaceLane8(lane), [vec, val])
}

///|
pub fn IRBuilder::v128_replace16(
  self : IRBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(Type::V128, Opcode::V128ReplaceLane16(lane), [vec, val])
}

///|
pub fn IRBuilder::v128_replace32(
  self : IRBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(Type::V128, Opcode::V128ReplaceLane32(lane), [vec, val])
}

///|
pub fn IRBuilder::v128_replace64(
  self : IRBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(Type::V128, Opcode::V128ReplaceLane64(lane), [vec, val])
}

///|
pub fn IRBuilder::v128_replace_f32(
  self : IRBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(Type::V128, Opcode::V128ReplaceLaneF32(lane), [vec, val])
}

///|
pub fn IRBuilder::v128_replace_f64(
  self : IRBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(Type::V128, Opcode::V128ReplaceLaneF64(lane), [vec, val])
}

///|
/// Shuffle lanes from two v128 values
pub fn IRBuilder::v128_shuffle(
  self : IRBuilder,
  a : Value,
  b : Value,
  lanes : FixedArray[Int],
) -> Value {
  self.emit_inst(Type::V128, Opcode::V128Shuffle(lanes), [a, b])
}

///|
/// Swizzle lanes using indices from another v128
pub fn IRBuilder::v128_swizzle(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(Type::V128, Opcode::V128Swizzle, [a, b])
}

///|
/// Bitwise operations on v128
pub fn IRBuilder::v128_not(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(Type::V128, Opcode::V128Not, [a])
}

///|
pub fn IRBuilder::v128_and(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(Type::V128, Opcode::V128And, [a, b])
}

///|
pub fn IRBuilder::v128_andnot(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(Type::V128, Opcode::V128AndNot, [a, b])
}

///|
pub fn IRBuilder::v128_or(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(Type::V128, Opcode::V128Or, [a, b])
}

///|
pub fn IRBuilder::v128_xor(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(Type::V128, Opcode::V128Xor, [a, b])
}

///|
pub fn IRBuilder::v128_bitselect(
  self : IRBuilder,
  a : Value,
  b : Value,
  c : Value,
) -> Value {
  self.emit_inst(Type::V128, Opcode::V128Bitselect, [a, b, c])
}

///|
pub fn IRBuilder::v128_anytrue(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(Type::I32, Opcode::V128AnyTrue, [a])
}

///|
/// Generic SIMD instruction emitter
/// Use this for operations that follow the pattern: opcode, operands -> V128/I32
pub fn IRBuilder::v128_unary(
  self : IRBuilder,
  opcode : Opcode,
  a : Value,
) -> Value {
  self.emit_inst(Type::V128, opcode, [a])
}

///|
pub fn IRBuilder::v128_binary(
  self : IRBuilder,
  opcode : Opcode,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(Type::V128, opcode, [a, b])
}

///|
pub fn IRBuilder::v128_to_i32(
  self : IRBuilder,
  opcode : Opcode,
  a : Value,
) -> Value {
  self.emit_inst(Type::I32, opcode, [a])
}

///|
pub fn IRBuilder::v128_shift(
  self : IRBuilder,
  opcode : Opcode,
  vec : Value,
  shift : Value,
) -> Value {
  self.emit_inst(Type::V128, opcode, [vec, shift])
}

///|
/// SIMD load with effective address (for complex SIMD loads)
pub fn IRBuilder::v128_load_with_addr(
  self : IRBuilder,
  opcode : Opcode,
  effective_addr : Value,
) -> Value {
  self.emit_inst(Type::V128, opcode, [effective_addr])
}

///|
/// SIMD load lane with effective address and existing vector
pub fn IRBuilder::v128_load_lane_with_addr(
  self : IRBuilder,
  opcode : Opcode,
  effective_addr : Value,
  vec : Value,
) -> Value {
  self.emit_inst(Type::V128, opcode, [effective_addr, vec])
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
