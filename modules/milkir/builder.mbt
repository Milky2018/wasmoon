// Function Builder - Convenient API for constructing IR
// SSA function builder

///|
/// FunctionBuilder - helps construct IR functions
/// Tracks the current block and provides methods for emitting instructions
struct FunctionBuilder {
  func : Function
  mut current_block : Block
}

///|
pub fn FunctionBuilder::FunctionBuilder(name : String) -> FunctionBuilder {
  let func = Function::new_empty(name)
  let entry = func.new_block0()
  { func, current_block: entry }
}

///|
/// Get the function being built
pub fn FunctionBuilder::get_function(self : FunctionBuilder) -> Function {
  self.func
}

///|
/// Finish building and return the constructed function.
pub fn FunctionBuilder::finalize(
  self : FunctionBuilder,
) -> Function raise VerifyError {
  self.func.verify()
  self.func
}

///|
/// Add a parameter to the function
pub fn FunctionBuilder::add_param(self : FunctionBuilder, ty : Type) -> Value {
  self.func.add_param(ty)
}

///|
/// Add a result type to the function
pub fn FunctionBuilder::add_result(self : FunctionBuilder, ty : Type) -> Unit {
  self.func.add_result(ty)
}

///|
/// Create a new block.
pub fn FunctionBuilder::create_block(self : FunctionBuilder) -> Block {
  let block = self.func.new_block0()
  block
}

///|
/// Switch to a different block for emitting instructions
pub fn FunctionBuilder::switch_to_block(
  self : FunctionBuilder,
  block : Block,
) -> Unit {
  self.current_block = block
}

///|
/// Get the current block
pub fn FunctionBuilder::current_block(self : FunctionBuilder) -> Block {
  self.current_block
}

///|
/// Add a block parameter (for SSA phi nodes)
pub fn FunctionBuilder::add_block_param(
  self : FunctionBuilder,
  block : Block,
  ty : Type,
) -> Value {
  let v = self.func.new_value(ty)
  block.add_param(v, ty)
  v
}

///|
/// Append block parameters matching the function parameter types.
pub fn FunctionBuilder::append_block_params_for_function_params(
  self : FunctionBuilder,
  block : Block,
) -> Unit {
  for item in self.func.params {
    let (_, ty) = item
    self.add_block_param(block, ty) |> ignore
  }
}

///|
/// Append block parameters matching the function result types.
pub fn FunctionBuilder::append_block_params_for_function_returns(
  self : FunctionBuilder,
  block : Block,
) -> Unit {
  for ty in self.func.results {
    self.add_block_param(block, ty) |> ignore
  }
}

///|
/// Return the SSA values used as block parameters.
pub fn FunctionBuilder::block_params(
  _self : FunctionBuilder,
  block : Block,
) -> Array[Value] {
  block.params.map(fn(item) {
    let (value, _) = item
    value
  })
}

///|
/// Emit an instruction that produces a result
pub fn FunctionBuilder::emit_inst(
  self : FunctionBuilder,
  ty : Type,
  opcode : Opcode,
  operands : Array[Value],
) -> Value {
  let block = self.current_block
  let result = self.func.new_value(ty)
  let inst = self.func.new_inst(opcode, operands, [result])
  block.add_inst(inst)
  result
}

///|
/// Emit an instruction without a result
pub fn FunctionBuilder::emit_void_inst(
  self : FunctionBuilder,
  opcode : Opcode,
  operands : Array[Value],
) -> Unit {
  let block = self.current_block
  let inst = self.func.new_inst(opcode, operands, [])
  block.add_inst(inst)
}

///|
/// Emit an instruction with multiple results.
pub fn FunctionBuilder::emit_multi_inst(
  self : FunctionBuilder,
  result_types : Array[Type],
  opcode : Opcode,
  operands : Array[Value],
) -> Array[Value] {
  if result_types.length() == 0 {
    self.emit_void_inst(opcode, operands)
    return []
  }
  let block = self.current_block
  let results : Array[Value] = []
  for ty in result_types {
    results.push(self.func.new_value(ty))
  }
  let inst = self.func.new_inst(opcode, operands, results)
  block.add_inst(inst)
  results
}

///|
pub fn FunctionBuilder::emit_ext_inst(
  self : FunctionBuilder,
  ty : Type,
  opcode : ExtOp,
  operands : Array[Value],
) -> Value {
  self.emit_inst(
    ty,
    Ext(opcode, Signature(operands.map(value => value.ty), [ty])),
    operands,
  )
}

///|
pub fn FunctionBuilder::emit_void_ext_inst(
  self : FunctionBuilder,
  opcode : ExtOp,
  operands : Array[Value],
) -> Unit {
  self.emit_void_inst(
    Ext(opcode, Signature(operands.map(value => value.ty), [])),
    operands,
  )
}

///|
pub fn FunctionBuilder::emit_multi_ext_inst(
  self : FunctionBuilder,
  result_types : Array[Type],
  opcode : ExtOp,
  operands : Array[Value],
) -> Array[Value] {
  self.emit_multi_inst(
    result_types,
    Ext(opcode, Signature(operands.map(value => value.ty), result_types.copy())),
    operands,
  )
}

// ============ Constants ============

///|
/// Get the constant value if a Value was defined by an Iconst instruction.
/// Searches all blocks in the function to find the defining instruction.
/// Returns None if the value is not a constant or not found.
pub fn FunctionBuilder::get_const_value(
  self : FunctionBuilder,
  v : Value,
) -> Int64? {
  for block in self.func.blocks {
    for inst in block.instructions {
      if inst.first_result() is Some(r) && r.id == v.id {
        if inst.opcode is Scalar(ScalarOp::IntConst(c)) {
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
pub fn FunctionBuilder::iconst(
  self : FunctionBuilder,
  ty : Type,
  value : Int64,
) -> Value {
  self.emit_inst(ty, Scalar(ScalarOp::IntConst(value)), [])
}

///|
/// Emit an i32 constant
pub fn FunctionBuilder::iconst_i32(
  self : FunctionBuilder,
  value : Int,
) -> Value {
  self.iconst(I32, value.to_int64())
}

///|
/// Emit an i64 constant
pub fn FunctionBuilder::iconst_i64(
  self : FunctionBuilder,
  value : Int64,
) -> Value {
  self.iconst(I64, value)
}

///|
/// Emit a float constant
pub fn FunctionBuilder::fconst(
  self : FunctionBuilder,
  ty : Type,
  value : Double,
) -> Value {
  self.emit_inst(ty, Scalar(ScalarOp::FloatConst(value)), [])
}

///|
/// Emit an f32 constant
/// Note: We pack the f32 bits into the Double's bit representation to preserve
/// NaN payloads. Using value.to_double() would go through the FPU and convert
/// signaling NaNs to quiet NaNs.
pub fn FunctionBuilder::fconst_f32(
  self : FunctionBuilder,
  value : Float,
) -> Value {
  let f32_bits = value.reinterpret_as_int().to_int64()
  self.fconst(F32, f32_bits.reinterpret_as_double())
}

///|
/// Emit an f64 constant
pub fn FunctionBuilder::fconst_f64(
  self : FunctionBuilder,
  value : Double,
) -> Value {
  self.fconst(F64, value)
}

// ============ Integer Arithmetic ============

///|
/// Integer add
pub fn FunctionBuilder::iadd(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::IntBinary(IntBinaryOp::Add)), [a, b])
}

///|
/// Integer subtract
pub fn FunctionBuilder::isub(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::IntBinary(IntBinaryOp::Sub)), [a, b])
}

///|
/// Integer multiply
pub fn FunctionBuilder::imul(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::IntBinary(IntBinaryOp::Mul)), [a, b])
}

///|
/// Unsigned multiply high (i64 only)
pub fn FunctionBuilder::umulh(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(
    a.ty,
    Scalar(ScalarOp::IntBinary(IntBinaryOp::UnsignedMulHigh)),
    [a, b],
  )
}

///|
/// Signed multiply high (i64 only)
pub fn FunctionBuilder::smulh(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(
    a.ty,
    Scalar(ScalarOp::IntBinary(IntBinaryOp::SignedMulHigh)),
    [a, b],
  )
}

///|
/// Signed integer divide
pub fn FunctionBuilder::sdiv(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::IntBinary(IntBinaryOp::SignedDiv)), [
    a, b,
  ])
}

///|
/// Unsigned integer divide
pub fn FunctionBuilder::udiv(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::IntBinary(IntBinaryOp::UnsignedDiv)), [
    a, b,
  ])
}

///|
/// Signed integer remainder
pub fn FunctionBuilder::srem(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::IntBinary(IntBinaryOp::SignedRem)), [
    a, b,
  ])
}

///|
/// Unsigned integer remainder
pub fn FunctionBuilder::urem(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::IntBinary(IntBinaryOp::UnsignedRem)), [
    a, b,
  ])
}

// ============ Bitwise Operations ============

///|
/// Bitwise and
pub fn FunctionBuilder::band(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::IntBinary(IntBinaryOp::And)), [a, b])
}

///|
/// Bitwise or
pub fn FunctionBuilder::bor(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::IntBinary(IntBinaryOp::Or)), [a, b])
}

///|
/// Bitwise xor
pub fn FunctionBuilder::bxor(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::IntBinary(IntBinaryOp::Xor)), [a, b])
}

///|
/// Bitwise not
pub fn FunctionBuilder::bnot(self : FunctionBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::IntUnary(IntUnaryOp::Not)), [a])
}

///|
/// Shift left
pub fn FunctionBuilder::ishl(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::IntBinary(IntBinaryOp::ShiftLeft)), [
    a, b,
  ])
}

///|
/// Signed shift right
pub fn FunctionBuilder::sshr(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(
    a.ty,
    Scalar(ScalarOp::IntBinary(IntBinaryOp::SignedShiftRight)),
    [a, b],
  )
}

///|
/// Unsigned shift right
pub fn FunctionBuilder::ushr(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(
    a.ty,
    Scalar(ScalarOp::IntBinary(IntBinaryOp::UnsignedShiftRight)),
    [a, b],
  )
}

///|
/// Rotate left
pub fn FunctionBuilder::rotl(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::IntBinary(IntBinaryOp::RotateLeft)), [
    a, b,
  ])
}

///|
/// Rotate right
pub fn FunctionBuilder::rotr(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::IntBinary(IntBinaryOp::RotateRight)), [
    a, b,
  ])
}

///|
/// Count leading zeros
pub fn FunctionBuilder::clz(self : FunctionBuilder, a : Value) -> Value {
  self.emit_inst(
    a.ty,
    Scalar(ScalarOp::IntUnary(IntUnaryOp::CountLeadingZeros)),
    [a],
  )
}

///|
/// Count trailing zeros
pub fn FunctionBuilder::ctz(self : FunctionBuilder, a : Value) -> Value {
  self.emit_inst(
    a.ty,
    Scalar(ScalarOp::IntUnary(IntUnaryOp::CountTrailingZeros)),
    [a],
  )
}

///|
/// Population count (count number of 1 bits)
pub fn FunctionBuilder::popcnt(self : FunctionBuilder, a : Value) -> Value {
  self.emit_inst(
    a.ty,
    Scalar(ScalarOp::IntUnary(IntUnaryOp::PopulationCount)),
    [a],
  )
}

// ============ Integer Comparisons ============

///|
/// Integer comparison (returns i32 0 or 1)
pub fn FunctionBuilder::icmp(
  self : FunctionBuilder,
  cc : IntCC,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(I32, Scalar(ScalarOp::IntCompare(cc)), [a, b])
}

///|
/// Integer equal
pub fn FunctionBuilder::icmp_eq(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.icmp(Eq, a, b)
}

///|
/// Integer not equal
pub fn FunctionBuilder::icmp_ne(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.icmp(Ne, a, b)
}

///|
/// Signed less than
pub fn FunctionBuilder::icmp_slt(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.icmp(Slt, a, b)
}

///|
/// Signed less than or equal
pub fn FunctionBuilder::icmp_sle(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.icmp(Sle, a, b)
}

///|
/// Signed greater than
pub fn FunctionBuilder::icmp_sgt(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.icmp(Sgt, a, b)
}

///|
/// Signed greater than or equal
pub fn FunctionBuilder::icmp_sge(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.icmp(Sge, a, b)
}

///|
/// Unsigned less than
pub fn FunctionBuilder::icmp_ult(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.icmp(Ult, a, b)
}

///|
/// Unsigned less than or equal
pub fn FunctionBuilder::icmp_ule(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.icmp(Ule, a, b)
}

///|
/// Unsigned greater than
pub fn FunctionBuilder::icmp_ugt(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.icmp(Ugt, a, b)
}

///|
/// Unsigned greater than or equal
pub fn FunctionBuilder::icmp_uge(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.icmp(Uge, a, b)
}

// ============ Floating Point Arithmetic ============

///|
/// Float add
pub fn FunctionBuilder::fadd(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::FloatBinary(FloatBinaryOp::Add)), [a, b])
}

///|
/// Float subtract
pub fn FunctionBuilder::fsub(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::FloatBinary(FloatBinaryOp::Sub)), [a, b])
}

///|
/// Float multiply
pub fn FunctionBuilder::fmul(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::FloatBinary(FloatBinaryOp::Mul)), [a, b])
}

///|
/// Float divide
pub fn FunctionBuilder::fdiv(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::FloatBinary(FloatBinaryOp::Div)), [a, b])
}

///|
/// Float minimum
pub fn FunctionBuilder::fmin(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::FloatBinary(FloatBinaryOp::Min)), [a, b])
}

///|
/// Float maximum
pub fn FunctionBuilder::fmax(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::FloatBinary(FloatBinaryOp::Max)), [a, b])
}

// ============ Float Comparisons ============

///|
/// Float comparison (returns i32 0 or 1)
pub fn FunctionBuilder::fcmp(
  self : FunctionBuilder,
  cc : FloatCC,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(I32, Scalar(ScalarOp::FloatCompare(cc)), [a, b])
}

// ============ Float Unary Operations ============

///|
/// Float negate
pub fn FunctionBuilder::fneg(self : FunctionBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::FloatUnary(FloatUnaryOp::Neg)), [a])
}

///|
/// Float absolute value
pub fn FunctionBuilder::fabs(self : FunctionBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::FloatUnary(FloatUnaryOp::Abs)), [a])
}

///|
/// Float square root
pub fn FunctionBuilder::fsqrt(self : FunctionBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::FloatUnary(FloatUnaryOp::Sqrt)), [a])
}

///|
/// Float ceiling
pub fn FunctionBuilder::fceil(self : FunctionBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::FloatUnary(FloatUnaryOp::Ceil)), [a])
}

///|
/// Float floor
pub fn FunctionBuilder::ffloor(self : FunctionBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::FloatUnary(FloatUnaryOp::Floor)), [a])
}

///|
/// Float truncate
pub fn FunctionBuilder::ftrunc(self : FunctionBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::FloatUnary(FloatUnaryOp::Trunc)), [a])
}

///|
/// Float nearest (round to nearest even)
pub fn FunctionBuilder::fnearest(self : FunctionBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::FloatUnary(FloatUnaryOp::Nearest)), [a])
}

// ============ Conversions ============

///|
/// Reduce integer width (e.g., i64 -> i32)
pub fn FunctionBuilder::ireduce(
  self : FunctionBuilder,
  ty : Type,
  a : Value,
) -> Value {
  self.emit_inst(ty, Scalar(ScalarOp::Convert(ConversionOp::IntReduce)), [a])
}

///|
/// Sign extend (e.g., i32 -> i64)
pub fn FunctionBuilder::sextend(
  self : FunctionBuilder,
  ty : Type,
  a : Value,
) -> Value {
  self.emit_inst(ty, Scalar(ScalarOp::Convert(ConversionOp::SignedExtend)), [a])
}

///|
/// Zero extend (e.g., i32 -> i64)
pub fn FunctionBuilder::uextend(
  self : FunctionBuilder,
  ty : Type,
  a : Value,
) -> Value {
  self.emit_inst(ty, Scalar(ScalarOp::Convert(ConversionOp::UnsignedExtend)), [
    a,
  ])
}

///|
/// Sign extend from 8 bits (in-place, keeps the same type)
/// Similar to ireduce(I8) + sextend(ty)
pub fn FunctionBuilder::sextend8(
  self : FunctionBuilder,
  ty : Type,
  a : Value,
) -> Value {
  self.emit_inst(ty, Scalar(ScalarOp::SignExtendFrom(8)), [a])
}

///|
/// Sign extend from 16 bits (in-place, keeps the same type)
/// Similar to ireduce(I16) + sextend(ty)
pub fn FunctionBuilder::sextend16(
  self : FunctionBuilder,
  ty : Type,
  a : Value,
) -> Value {
  self.emit_inst(ty, Scalar(ScalarOp::SignExtendFrom(16)), [a])
}

///|
/// Sign extend from 32 bits to 64 bits
/// Similar to ireduce(I32) + sextend(I64)
pub fn FunctionBuilder::sextend32(self : FunctionBuilder, a : Value) -> Value {
  self.emit_inst(I64, Scalar(ScalarOp::SignExtendFrom(32)), [a])
}

///|
/// Promote float (f32 -> f64)
pub fn FunctionBuilder::fpromote(self : FunctionBuilder, a : Value) -> Value {
  self.emit_inst(F64, Scalar(ScalarOp::Convert(ConversionOp::FloatPromote)), [a])
}

///|
/// Demote float (f64 -> f32)
pub fn FunctionBuilder::fdemote(self : FunctionBuilder, a : Value) -> Value {
  self.emit_inst(F32, Scalar(ScalarOp::Convert(ConversionOp::FloatDemote)), [a])
}

///|
/// Float to signed int
pub fn FunctionBuilder::fcvt_to_sint(
  self : FunctionBuilder,
  ty : Type,
  a : Value,
) -> Value {
  self.emit_inst(
    ty,
    Scalar(ScalarOp::Convert(ConversionOp::FloatToSignedInt)),
    [a],
  )
}

///|
/// Float to unsigned int
pub fn FunctionBuilder::fcvt_to_uint(
  self : FunctionBuilder,
  ty : Type,
  a : Value,
) -> Value {
  self.emit_inst(
    ty,
    Scalar(ScalarOp::Convert(ConversionOp::FloatToUnsignedInt)),
    [a],
  )
}

///|
/// Float to signed int (saturating - NaN->0, overflow->max/min)
pub fn FunctionBuilder::fcvt_to_sint_sat(
  self : FunctionBuilder,
  ty : Type,
  a : Value,
) -> Value {
  self.emit_inst(
    ty,
    Scalar(ScalarOp::Convert(ConversionOp::FloatToSignedIntSaturating)),
    [a],
  )
}

///|
/// Float to unsigned int (saturating - NaN->0, overflow->max, negative->0)
pub fn FunctionBuilder::fcvt_to_uint_sat(
  self : FunctionBuilder,
  ty : Type,
  a : Value,
) -> Value {
  self.emit_inst(
    ty,
    Scalar(ScalarOp::Convert(ConversionOp::FloatToUnsignedIntSaturating)),
    [a],
  )
}

///|
/// Signed int to float
pub fn FunctionBuilder::sint_to_fcvt(
  self : FunctionBuilder,
  ty : Type,
  a : Value,
) -> Value {
  self.emit_inst(
    ty,
    Scalar(ScalarOp::Convert(ConversionOp::SignedIntToFloat)),
    [a],
  )
}

///|
/// Unsigned int to float
pub fn FunctionBuilder::uint_to_fcvt(
  self : FunctionBuilder,
  ty : Type,
  a : Value,
) -> Value {
  self.emit_inst(
    ty,
    Scalar(ScalarOp::Convert(ConversionOp::UnsignedIntToFloat)),
    [a],
  )
}

///|
/// Bitcast (reinterpret bits)
pub fn FunctionBuilder::bitcast(
  self : FunctionBuilder,
  ty : Type,
  a : Value,
) -> Value {
  self.emit_inst(ty, Scalar(ScalarOp::Convert(ConversionOp::Bitcast)), [a])
}

// ============ Misc Operations ============

///|
/// Conditional select: cond ? a : b
pub fn FunctionBuilder::select(
  self : FunctionBuilder,
  cond : Value,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::Select), [cond, a, b])
}

///|
/// Copy value (for register allocation)
pub fn FunctionBuilder::copy(self : FunctionBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Scalar(ScalarOp::Copy), [a])
}

// ============ Function Calls ============

///|
pub fn FunctionBuilder::call_symbol(
  self : FunctionBuilder,
  symbol : ExternalSymbol,
  result_ty : Type?,
  args : Array[Value],
) -> Value? {
  let param_types = args.map(value => value.ty)
  match result_ty {
    Some(ty) =>
      Some(
        self.emit_inst(
          ty,
          Call(CallOp::Direct(symbol, Signature(param_types, [ty]))),
          args,
        ),
      )
    None => {
      self.emit_void_inst(
        Call(CallOp::Direct(symbol, Signature(param_types, []))),
        args,
      )
      None
    }
  }
}

///|
pub fn FunctionBuilder::call_symbol_multi(
  self : FunctionBuilder,
  symbol : ExternalSymbol,
  result_types : Array[Type],
  args : Array[Value],
) -> Array[Value] {
  self.emit_multi_inst(
    result_types,
    Call(
      CallOp::Direct(
        symbol,
        Signature(args.map(value => value.ty), result_types.copy()),
      ),
    ),
    args,
  )
}

// ============ Terminators ============

///|
/// Unconditional jump
pub fn FunctionBuilder::jump(
  self : FunctionBuilder,
  target : Block,
  args : Array[Value],
) -> Unit {
  let block = self.current_block
  block.set_terminator(Jump(target.id, args))
}

///|
/// Conditional branch (branch if zero)
pub fn FunctionBuilder::brz(
  self : FunctionBuilder,
  cond : Value,
  then_block : Block,
  else_block : Block,
) -> Unit {
  let block = self.current_block
  block.set_terminator(Brz(cond, then_block.id, else_block.id))
}

///|
/// Conditional branch (branch if non-zero)
pub fn FunctionBuilder::brnz(
  self : FunctionBuilder,
  cond : Value,
  then_block : Block,
  else_block : Block,
) -> Unit {
  let block = self.current_block
  block.set_terminator(Brnz(cond, then_block.id, else_block.id))
}

///|
/// Branch table (switch)
pub fn FunctionBuilder::br_table(
  self : FunctionBuilder,
  index : Value,
  targets : Array[Block],
  default_target : Block,
) -> Unit {
  let target_ids = targets.map(fn(b) { b.id })
  let block = self.current_block
  block.set_terminator(BrTable(index, target_ids, default_target.id))
}

///|
/// Return from function
pub fn FunctionBuilder::return_(
  self : FunctionBuilder,
  values : Array[Value],
) -> Unit {
  let block = self.current_block
  block.set_terminator(Return(values))
}

///|
/// Trap/unreachable
pub fn FunctionBuilder::trap(self : FunctionBuilder, reason : String) -> Unit {
  let block = self.current_block
  block.set_terminator(Trap(reason))
}

// ============ Raw Pointer Operations (for trampolines) ============

///|
/// Load from raw pointer (no bounds checking)
/// For trampoline code that operates on host memory
pub fn FunctionBuilder::load_ptr(
  self : FunctionBuilder,
  ty : Type,
  base : Value,
  offset : Value,
) -> Value {
  self.emit_inst(ty, Memory(MemoryOp::Load(ty)), [base, offset])
}

///|
/// Store to raw pointer (no bounds checking)
/// For trampoline code that operates on host memory
pub fn FunctionBuilder::store_ptr(
  self : FunctionBuilder,
  ty : Type,
  base : Value,
  value : Value,
  offset : Value,
) -> Unit {
  self.emit_void_inst(Memory(MemoryOp::Store(ty)), [base, value, offset])
}

///|
/// Load narrow value from raw pointer (no bounds checking)
/// Loads 'bits' bits from memory and extends to result_ty
pub fn FunctionBuilder::load_ptr_narrow(
  self : FunctionBuilder,
  result_ty : Type,
  bits : Int,
  signed : Bool,
  base : Value,
  offset : Value,
) -> Value {
  self.emit_inst(
    result_ty,
    Memory(MemoryOp::LoadNarrow(result_ty, bits, signed)),
    [base, offset],
  )
}

///|
/// Store narrow value to raw pointer (no bounds checking)
/// Stores the low 'bits' bits of value to memory
pub fn FunctionBuilder::store_ptr_narrow(
  self : FunctionBuilder,
  bits : Int,
  base : Value,
  value : Value,
  offset : Value,
) -> Unit {
  self.emit_void_inst(Memory(MemoryOp::StoreNarrow(bits)), [base, value, offset])
}

///|
/// Embedding convenience wrapper for a pointer call whose first argument is a
/// callee environment.
pub fn FunctionBuilder::call_ptr(
  self : FunctionBuilder,
  func_ptr : Value,
  callee_env : Value,
  args : Array[Value],
  result_types : Array[Type],
) -> Array[Value] {
  let args_with_env : Array[Value] = [callee_env]
  for arg in args {
    args_with_env.push(arg)
  }
  self.call_pointer(func_ptr, args_with_env, result_types)
}

///|
/// Call a function pointer with ordinary arguments.
pub fn FunctionBuilder::call_pointer(
  self : FunctionBuilder,
  func_ptr : Value,
  args : Array[Value],
  result_types : Array[Type],
) -> Array[Value] {
  let operands : Array[Value] = [func_ptr]
  for arg in args {
    operands.push(arg)
  }
  let num_args = args.length()
  let num_results = result_types.length()
  self.emit_multi_inst(
    result_types,
    Call(CallOp::Pointer(num_args, num_results)),
    operands,
  )
}

// ============ SIMD Operations ============

///|
/// v128_const - emit a V128 constant
pub fn FunctionBuilder::v128_const(
  self : FunctionBuilder,
  bytes : Bytes,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::V128Const(bytes)), [])
}

///|
/// v128_splat - broadcast a scalar to all lanes
pub fn FunctionBuilder::v128_splat8(
  self : FunctionBuilder,
  val : Value,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::Splat(VectorLane::I8)), [val])
}

///|
pub fn FunctionBuilder::v128_splat16(
  self : FunctionBuilder,
  val : Value,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::Splat(VectorLane::I16)), [val])
}

///|
pub fn FunctionBuilder::v128_splat32(
  self : FunctionBuilder,
  val : Value,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::Splat(VectorLane::I32)), [val])
}

///|
pub fn FunctionBuilder::v128_splat64(
  self : FunctionBuilder,
  val : Value,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::Splat(VectorLane::I64)), [val])
}

///|
pub fn FunctionBuilder::v128_splat_f32(
  self : FunctionBuilder,
  val : Value,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::Splat(VectorLane::F32)), [val])
}

///|
pub fn FunctionBuilder::v128_splat_f64(
  self : FunctionBuilder,
  val : Value,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::Splat(VectorLane::F64)), [val])
}

///|
/// Extract a lane from a v128 value
pub fn FunctionBuilder::v128_extract8s(
  self : FunctionBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(
    I32,
    Vector(VectorOp::ExtractLane(VectorLane::I8, VectorExtension::Signed, lane)),
    [vec],
  )
}

///|
pub fn FunctionBuilder::v128_extract8u(
  self : FunctionBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(
    I32,
    Vector(
      VectorOp::ExtractLane(VectorLane::I8, VectorExtension::Unsigned, lane),
    ),
    [vec],
  )
}

///|
pub fn FunctionBuilder::v128_extract16s(
  self : FunctionBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(
    I32,
    Vector(
      VectorOp::ExtractLane(VectorLane::I16, VectorExtension::Signed, lane),
    ),
    [vec],
  )
}

///|
pub fn FunctionBuilder::v128_extract16u(
  self : FunctionBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(
    I32,
    Vector(
      VectorOp::ExtractLane(VectorLane::I16, VectorExtension::Unsigned, lane),
    ),
    [vec],
  )
}

///|
pub fn FunctionBuilder::v128_extract32(
  self : FunctionBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(
    I32,
    Vector(VectorOp::ExtractLane(VectorLane::I32, VectorExtension::None, lane)),
    [vec],
  )
}

///|
pub fn FunctionBuilder::v128_extract64(
  self : FunctionBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(
    I64,
    Vector(VectorOp::ExtractLane(VectorLane::I64, VectorExtension::None, lane)),
    [vec],
  )
}

///|
pub fn FunctionBuilder::v128_extract_f32(
  self : FunctionBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(
    F32,
    Vector(VectorOp::ExtractLane(VectorLane::F32, VectorExtension::None, lane)),
    [vec],
  )
}

///|
pub fn FunctionBuilder::v128_extract_f64(
  self : FunctionBuilder,
  vec : Value,
  lane : Int,
) -> Value {
  self.emit_inst(
    F64,
    Vector(VectorOp::ExtractLane(VectorLane::F64, VectorExtension::None, lane)),
    [vec],
  )
}

///|
/// Replace a lane in a v128 value
pub fn FunctionBuilder::v128_replace8(
  self : FunctionBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::ReplaceLane(VectorLane::I8, lane)), [
    vec, val,
  ])
}

///|
pub fn FunctionBuilder::v128_replace16(
  self : FunctionBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::ReplaceLane(VectorLane::I16, lane)), [
    vec, val,
  ])
}

///|
pub fn FunctionBuilder::v128_replace32(
  self : FunctionBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::ReplaceLane(VectorLane::I32, lane)), [
    vec, val,
  ])
}

///|
pub fn FunctionBuilder::v128_replace64(
  self : FunctionBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::ReplaceLane(VectorLane::I64, lane)), [
    vec, val,
  ])
}

///|
pub fn FunctionBuilder::v128_replace_f32(
  self : FunctionBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::ReplaceLane(VectorLane::F32, lane)), [
    vec, val,
  ])
}

///|
pub fn FunctionBuilder::v128_replace_f64(
  self : FunctionBuilder,
  vec : Value,
  val : Value,
  lane : Int,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::ReplaceLane(VectorLane::F64, lane)), [
    vec, val,
  ])
}

///|
/// Shuffle lanes from two v128 values
pub fn FunctionBuilder::v128_shuffle(
  self : FunctionBuilder,
  a : Value,
  b : Value,
  lanes : FixedArray[Int],
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::V128Shuffle(lanes)), [a, b])
}

///|
/// Swizzle lanes using indices from another v128
pub fn FunctionBuilder::v128_swizzle(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::V128Swizzle), [a, b])
}

///|
/// Bitwise operations on v128
pub fn FunctionBuilder::v128_not(self : FunctionBuilder, a : Value) -> Value {
  self.emit_inst(V128, Vector(VectorOp::V128Not), [a])
}

///|
pub fn FunctionBuilder::v128_and(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::V128And), [a, b])
}

///|
pub fn FunctionBuilder::v128_andnot(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::V128AndNot), [a, b])
}

///|
pub fn FunctionBuilder::v128_or(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::V128Or), [a, b])
}

///|
pub fn FunctionBuilder::v128_xor(
  self : FunctionBuilder,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::V128Xor), [a, b])
}

///|
pub fn FunctionBuilder::v128_bitselect(
  self : FunctionBuilder,
  a : Value,
  b : Value,
  c : Value,
) -> Value {
  self.emit_inst(V128, Vector(VectorOp::V128Bitselect), [a, b, c])
}

///|
pub fn FunctionBuilder::v128_anytrue(
  self : FunctionBuilder,
  a : Value,
) -> Value {
  self.emit_inst(I32, Vector(VectorOp::V128AnyTrue), [a])
}

///|
/// Generic SIMD instruction emitter
/// Use this for operations that follow the pattern: opcode, operands -> V128/I32
pub fn FunctionBuilder::v128_unary(
  self : FunctionBuilder,
  opcode : VectorOp,
  a : Value,
) -> Value {
  self.emit_inst(V128, Vector(opcode), [a])
}

///|
pub fn FunctionBuilder::v128_binary(
  self : FunctionBuilder,
  opcode : VectorOp,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(V128, Vector(opcode), [a, b])
}

///|
pub fn FunctionBuilder::v128_to_i32(
  self : FunctionBuilder,
  opcode : VectorOp,
  a : Value,
) -> Value {
  self.emit_inst(I32, Vector(opcode), [a])
}

///|
pub fn FunctionBuilder::v128_shift(
  self : FunctionBuilder,
  opcode : VectorOp,
  vec : Value,
  shift : Value,
) -> Value {
  self.emit_inst(V128, Vector(opcode), [vec, shift])
}

///|
/// SIMD load with effective address (for complex SIMD loads)
pub fn FunctionBuilder::v128_load_with_addr(
  self : FunctionBuilder,
  opcode : VectorOp,
  effective_addr : Value,
) -> Value {
  self.emit_inst(V128, Vector(opcode), [effective_addr])
}

///|
/// SIMD load lane with effective address and existing vector
pub fn FunctionBuilder::v128_load_lane_with_addr(
  self : FunctionBuilder,
  opcode : VectorOp,
  effective_addr : Value,
  vec : Value,
) -> Value {
  self.emit_inst(V128, Vector(opcode), [effective_addr, vec])
}

///|
/// SIMD store lane with effective address and vector (void)
pub fn FunctionBuilder::v128_store_lane_with_addr(
  self : FunctionBuilder,
  opcode : VectorOp,
  effective_addr : Value,
  vec : Value,
) -> Unit {
  self.emit_void_inst(Vector(opcode), [effective_addr, vec])
}
