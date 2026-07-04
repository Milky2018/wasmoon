///|
/// Optimization level for MilkIR passes.
pub(all) enum OptLevel {
  O0
  O1
  O2
  O3
} derive(Eq, Debug)

///|
pub fn OptLevel::from_int(n : Int) -> OptLevel {
  match n {
    0 => O0
    1 => O1
    3 => O3
    _ => O2
  }
}

///|
pub(all) struct OptResult {
  mut changed : Bool
  passes_run : Array[String]
} derive(Debug)

///|
pub fn OptResult::new() -> OptResult {
  { changed: false, passes_run: [] }
}

///|
pub fn OptResult::mark_changed(self : OptResult) -> Unit {
  self.changed = true
}

///|
pub fn OptResult::add_pass(self : OptResult, name : String) -> Unit {
  self.passes_run.push(name)
}

///|
pub fn instruction_count(func : Function) -> Int {
  let mut count = 0
  for block in func.blocks {
    count = count + block.instructions.length()
  }
  count
}

///|
priv enum ConstValue {
  CI32(Int)
  CI64(Int64)
  CF32(Float)
  CF64(Double)
}

///|
fn ConstValue::to_opcode(self : ConstValue) -> Opcode {
  match self {
    CI32(v) => Iconst(v.to_int64())
    CI64(v) => Iconst(v)
    CF32(v) => Fconst(v.reinterpret_as_int().to_int64().reinterpret_as_double())
    CF64(v) => Fconst(v)
  }
}

///|
fn record_const(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> Unit {
  guard inst.results.length() == 1 else { return }
  let result = inst.results[0]
  match inst.opcode {
    Iconst(value) =>
      match result.ty {
        I32 => constants.set(result.id, CI32(value.to_int()))
        I64 => constants.set(result.id, CI64(value))
        _ => ()
      }
    Fconst(value) =>
      match result.ty {
        F32 => {
          let bits = value.reinterpret_as_int64().to_int()
          constants.set(result.id, CF32(Float::reinterpret_from_int(bits)))
        }
        F64 => constants.set(result.id, CF64(value))
        _ => ()
      }
    _ => ()
  }
}

///|
fn get_const(
  value : Value,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  constants.get(value.id)
}

///|
fn fold_binary_int(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
  op : (Int64, Int64) -> Int64,
) -> ConstValue? {
  guard inst.args.length() == 2 else { return None }
  match
    (get_const(inst.args[0], constants), get_const(inst.args[1], constants)) {
    (Some(CI32(a)), Some(CI32(b))) =>
      Some(CI32(op(a.to_int64(), b.to_int64()).to_int()))
    (Some(CI64(a)), Some(CI64(b))) => Some(CI64(op(a, b)))
    _ => None
  }
}

///|
fn fold_binary_float(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
  op : (Double, Double) -> Double,
) -> ConstValue? {
  guard inst.args.length() == 2 else { return None }
  match
    (get_const(inst.args[0], constants), get_const(inst.args[1], constants)) {
    (Some(CF32(a)), Some(CF32(b))) =>
      Some(CF32(Float::from_double(op(a.to_double(), b.to_double()))))
    (Some(CF64(a)), Some(CF64(b))) => Some(CF64(op(a, b)))
    _ => None
  }
}

///|
fn eval_intcc_i64(cc : IntCC, a : Int64, b : Int64) -> Bool {
  match cc {
    Eq => a == b
    Ne => a != b
    Slt => a < b
    Sle => a <= b
    Sgt => a > b
    Sge => a >= b
    Ult => a.reinterpret_as_uint64() < b.reinterpret_as_uint64()
    Ule => a.reinterpret_as_uint64() <= b.reinterpret_as_uint64()
    Ugt => a.reinterpret_as_uint64() > b.reinterpret_as_uint64()
    Uge => a.reinterpret_as_uint64() >= b.reinterpret_as_uint64()
  }
}

///|
fn fold_icmp(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
  cc : IntCC,
) -> ConstValue? {
  guard inst.args.length() == 2 else { return None }
  match
    (get_const(inst.args[0], constants), get_const(inst.args[1], constants)) {
    (Some(CI32(a)), Some(CI32(b))) =>
      Some(
        CI32(if eval_intcc_i64(cc, a.to_int64(), b.to_int64()) { 1 } else { 0 }),
      )
    (Some(CI64(a)), Some(CI64(b))) =>
      Some(CI32(if eval_intcc_i64(cc, a, b) { 1 } else { 0 }))
    _ => None
  }
}

///|
fn fold_shift(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
  signed? : Bool = true,
  left? : Bool = true,
) -> ConstValue? {
  guard inst.args.length() == 2 else { return None }
  match
    (get_const(inst.args[0], constants), get_const(inst.args[1], constants)) {
    (Some(CI32(a)), Some(CI32(b))) => {
      let shift = b % 32
      if left {
        Some(CI32(a << shift))
      } else if signed {
        Some(CI32(a >> shift))
      } else {
        Some(CI32((a.reinterpret_as_uint() >> shift).reinterpret_as_int()))
      }
    }
    (Some(CI64(a)), Some(CI64(b))) => {
      let shift = b.to_int() % 64
      if left {
        Some(CI64(a << shift))
      } else if signed {
        Some(CI64(a >> shift))
      } else {
        Some(CI64((a.reinterpret_as_uint64() >> shift).reinterpret_as_int64()))
      }
    }
    _ => None
  }
}

///|
fn try_fold_constant(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  match inst.opcode {
    Iconst(_) | Fconst(_) => None
    Iadd => fold_binary_int(inst, constants, fn(a, b) { a + b })
    Isub => fold_binary_int(inst, constants, fn(a, b) { a - b })
    Imul => fold_binary_int(inst, constants, fn(a, b) { a * b })
    Band => fold_binary_int(inst, constants, fn(a, b) { a & b })
    Bor => fold_binary_int(inst, constants, fn(a, b) { a | b })
    Bxor => fold_binary_int(inst, constants, fn(a, b) { a ^ b })
    Ishl => fold_shift(inst, constants, left=true)
    Sshr => fold_shift(inst, constants, signed=true, left=false)
    Ushr => fold_shift(inst, constants, signed=false, left=false)
    Fadd => fold_binary_float(inst, constants, fn(a, b) { a + b })
    Fsub => fold_binary_float(inst, constants, fn(a, b) { a - b })
    Fmul => fold_binary_float(inst, constants, fn(a, b) { a * b })
    Fdiv => fold_binary_float(inst, constants, fn(a, b) { a / b })
    Icmp(cc) => fold_icmp(inst, constants, cc)
    IcmpEq => fold_icmp(inst, constants, Eq)
    // TODO(milkir): add trap-aware folding for div/rem and conversion opcodes
    // once MilkIR carries explicit trapping/overflow legality metadata.
    _ => None
  }
}

///|
pub fn fold_constants(func : Function) -> OptResult {
  let result = OptResult::new()
  let constants : @hashmap.HashMap[Int, ConstValue] = HashMap([])
  result.add_pass("const_fold")
  for block in func.blocks {
    for inst in block.instructions {
      record_const(inst, constants)
      if try_fold_constant(inst, constants) is Some(constant) &&
        inst.results.length() == 1 {
        constants.set(inst.results[0].id, constant)
        inst.opcode = constant.to_opcode()
        inst.args.clear()
        result.mark_changed()
      }
    }
  }
  result
}

///|
pub fn optimize_with_level(func : Function, level : OptLevel) -> OptResult {
  match level {
    O0 => OptResult::new()
    O1 | O2 | O3 => fold_constants(func)
  }
}
