///|
pub(all) struct IRBuilder {
  func : Function
  mut current_block : Block?
} derive(Debug)

///|
pub fn IRBuilder::new(name : String) -> IRBuilder {
  { func: Function::new_empty(name), current_block: None }
}

///|
pub fn IRBuilder::get_function(self : IRBuilder) -> Function {
  self.func
}

///|
pub fn IRBuilder::add_param(self : IRBuilder, ty : Type) -> Value {
  self.func.add_param(ty)
}

///|
pub fn IRBuilder::add_result(self : IRBuilder, ty : Type) -> Unit {
  self.func.add_result(ty)
}

///|
pub fn IRBuilder::create_block(self : IRBuilder) -> Block {
  self.func.new_block0()
}

///|
pub fn IRBuilder::switch_to_block(self : IRBuilder, block : Block) -> Unit {
  self.current_block = Some(block)
}

///|
pub fn IRBuilder::current_block(self : IRBuilder) -> Block? {
  self.current_block
}

///|
pub fn IRBuilder::add_block_param(
  self : IRBuilder,
  block : Block,
  ty : Type,
) -> Value {
  let value = self.func.new_value(ty)
  block.add_param(value)
  value
}

///|
fn IRBuilder::emit_inst(
  self : IRBuilder,
  ty : Type,
  opcode : Opcode,
  operands : Array[Value],
) -> Value {
  let result = self.func.new_value(ty)
  let inst = self.func.new_inst(opcode, operands, [result])
  if self.current_block is Some(block) {
    block.append_inst(inst)
  }
  result
}

///|
fn IRBuilder::emit_multi_inst(
  self : IRBuilder,
  result_types : Array[Type],
  opcode : Opcode,
  operands : Array[Value],
) -> Array[Value] {
  let results = result_types.map(fn(ty) { self.func.new_value(ty) })
  let inst = self.func.new_inst(opcode, operands, results)
  if self.current_block is Some(block) {
    block.append_inst(inst)
  }
  results
}

///|
fn IRBuilder::emit_void_inst(
  self : IRBuilder,
  opcode : Opcode,
  operands : Array[Value],
) -> Unit {
  let inst = self.func.new_inst(opcode, operands, [])
  if self.current_block is Some(block) {
    block.append_inst(inst)
  }
}

///|
pub fn IRBuilder::get_const_value(self : IRBuilder, value : Value) -> Int64? {
  for block in self.func.blocks {
    for inst in block.instructions {
      if inst.results.length() == 1 && inst.results[0].id == value.id {
        if inst.opcode is Iconst(n) {
          return Some(n)
        }
        return None
      }
    }
  }
  None
}

///|
pub fn IRBuilder::iconst(self : IRBuilder, ty : Type, value : Int64) -> Value {
  self.emit_inst(ty, Iconst(value), [])
}

///|
pub fn IRBuilder::iconst_i32(self : IRBuilder, value : Int) -> Value {
  self.iconst(I32, value.to_int64())
}

///|
pub fn IRBuilder::iconst_i64(self : IRBuilder, value : Int64) -> Value {
  self.iconst(I64, value)
}

///|
pub fn IRBuilder::fconst(self : IRBuilder, ty : Type, value : Double) -> Value {
  self.emit_inst(ty, Fconst(value), [])
}

///|
pub fn IRBuilder::fconst_f32(self : IRBuilder, value : Float) -> Value {
  let bits = value.reinterpret_as_int().to_int64()
  self.fconst(F32, bits.reinterpret_as_double())
}

///|
pub fn IRBuilder::fconst_f64(self : IRBuilder, value : Double) -> Value {
  self.fconst(F64, value)
}

///|
pub fn IRBuilder::iadd(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Iadd, [a, b])
}

///|
pub fn IRBuilder::isub(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Isub, [a, b])
}

///|
pub fn IRBuilder::imul(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Imul, [a, b])
}

///|
pub fn IRBuilder::icmp(
  self : IRBuilder,
  cc : IntCC,
  a : Value,
  b : Value,
) -> Value {
  self.emit_inst(I32, Icmp(cc), [a, b])
}

///|
pub fn IRBuilder::icmp_eq(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(Eq, a, b)
}

///|
pub fn IRBuilder::icmp_slt(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(Slt, a, b)
}

///|
pub fn IRBuilder::icmp_sgt(self : IRBuilder, a : Value, b : Value) -> Value {
  self.icmp(Sgt, a, b)
}

///|
pub fn IRBuilder::fadd(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Fadd, [a, b])
}

///|
pub fn IRBuilder::fsub(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Fsub, [a, b])
}

///|
pub fn IRBuilder::fmul(self : IRBuilder, a : Value, b : Value) -> Value {
  self.emit_inst(a.ty, Fmul, [a, b])
}

///|
pub fn IRBuilder::fneg(self : IRBuilder, a : Value) -> Value {
  self.emit_inst(a.ty, Fneg, [a])
}

///|
pub fn IRBuilder::load_ptr(
  self : IRBuilder,
  ty : Type,
  base : Value,
  offset : Value,
) -> Value {
  self.emit_inst(ty, LoadPtr(ty), [base, offset])
}

///|
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
pub fn IRBuilder::select(
  self : IRBuilder,
  cond : Value,
  true_value : Value,
  false_value : Value,
) -> Value {
  self.emit_inst(true_value.ty, Select, [cond, true_value, false_value])
}

///|
pub fn IRBuilder::copy(self : IRBuilder, value : Value) -> Value {
  self.emit_inst(value.ty, Copy, [value])
}

///|
pub fn IRBuilder::call(
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
pub fn IRBuilder::call_multi(
  self : IRBuilder,
  symbol : ExternalSymbol,
  result_types : Array[Type],
  args : Array[Value],
) -> Array[Value] {
  self.emit_multi_inst(result_types, Call(symbol), args)
}

///|
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
pub fn IRBuilder::br_table(
  self : IRBuilder,
  index : Value,
  targets : Array[Block],
  default_target : Block,
) -> Unit {
  if self.current_block is Some(block) {
    let target_ids = targets.map(fn(target) { target.id })
    block.set_terminator(BrTable(index, target_ids, default_target.id))
  }
}

///|
pub fn IRBuilder::return_(self : IRBuilder, values : Array[Value]) -> Unit {
  if self.current_block is Some(block) {
    block.set_terminator(Return(values))
  }
}

///|
pub fn IRBuilder::trap(self : IRBuilder, reason : String) -> Unit {
  if self.current_block is Some(block) {
    block.set_terminator(TrapExit(reason))
  }
}
