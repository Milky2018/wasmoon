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
fn record_terminator_uses(
  used : @hashmap.HashMap[Int, Bool],
  term : Terminator,
) -> Unit {
  fn record_values(
    used : @hashmap.HashMap[Int, Bool],
    values : Array[Value],
  ) -> Unit {
    for value in values {
      used.set(value.id, true)
    }
  }
  match term {
    Return(values) => record_values(used, values)
    Jump(_, args) => record_values(used, args)
    Branch(cond, _, true_args, _, false_args) => {
      used.set(cond.id, true)
      record_values(used, true_args)
      record_values(used, false_args)
    }
    Brz(cond, _, _) | Brnz(cond, _, _) => used.set(cond.id, true)
    BrTable(index, _, _) => used.set(index.id, true)
    TrapExit(_) => ()
  }
}

///|
fn inst_has_side_effects(inst : Inst) -> Bool {
  match inst.opcode {
    Store
    | StorePtr(_)
    | Call(_)
    | CallIndirect(_)
    | CallPtr(_, _)
    | Trap(_)
    | Custom(_)
    | Load
    | LoadPtr(_) => true
    // TODO(milkir): allow deleting loads once alias, trap, and volatility
    // metadata can prove that a load is speculatable and unused.
    _ => inst.results.length() == 0
  }
}

///|
fn inst_result_is_used(inst : Inst, used : @hashmap.HashMap[Int, Bool]) -> Bool {
  for result in inst.results {
    if used.get(result.id).unwrap_or(false) {
      return true
    }
  }
  false
}

///|
priv struct ExprKey {
  opcode : Opcode
  args : Array[Value]
  result_types : Array[Type]
} derive(Eq, Hash)

///|
fn expr_key(inst : Inst) -> ExprKey {
  {
    opcode: inst.opcode,
    args: inst.args.copy(),
    result_types: inst.results.map(fn(v) { v.ty }),
  }
}

///|
fn is_pure_cse_candidate(inst : Inst) -> Bool {
  guard inst.results.length() == 1 else { return false }
  match inst.opcode {
    Store
    | StorePtr(_)
    | Call(_)
    | CallIndirect(_)
    | CallPtr(_, _)
    | Trap(_)
    | Custom(_)
    | Load
    | LoadPtr(_)
    | Sdiv
    | Udiv
    | Srem
    | Urem
    | FcvtToSint
    | FcvtToUint => false
    // TODO(milkir): allow memory and trap-prone operations once MilkIR carries
    // alias, volatility, trapping, and overflow legality metadata.
    _ => true
  }
}

///|
fn build_block_index(func : Function) -> @hashmap.HashMap[Int, Int] {
  let block_index : @hashmap.HashMap[Int, Int] = HashMap([])
  for i, block in func.blocks {
    block_index.set(block.id, i)
  }
  block_index
}

///|
fn restore_expr_table(
  table : @hashmap.HashMap[ExprKey, Value],
  local_entries : Array[(ExprKey, Value?)],
) -> Unit {
  for entry in local_entries.rev_iter() {
    let (key, previous) = entry
    match previous {
      Some(value) => table.set(key, value)
      None => table.remove(key)
    }
  }
}

///|
pub fn eliminate_common_subexpressions(func : Function) -> OptResult {
  let result = OptResult::new()
  result.add_pass("cse")
  if func.blocks.length() == 0 {
    return result
  }
  let cfg = CFG::build(func)
  let idom = cfg.compute_dominators()
  let domtree = build_dominator_tree(idom)
  let block_index = build_block_index(func)
  let expressions : @hashmap.HashMap[ExprKey, Value] = HashMap([])
  fn visit(block_id : Int) {
    guard block_index.get(block_id) is Some(index) else { return }
    let block = func.blocks[index]
    let local_entries : Array[(ExprKey, Value?)] = []
    for inst in block.instructions {
      if !is_pure_cse_candidate(inst) {
        continue
      }
      let key = expr_key(inst)
      match expressions.get(key) {
        Some(existing) => {
          inst.opcode = Copy
          inst.args.clear()
          inst.args.push(existing)
          result.mark_changed()
        }
        None => {
          local_entries.push((key, expressions.get(key)))
          expressions.set(key, inst.results[0])
        }
      }
    }
    if block_id < domtree.length() {
      for child in domtree[block_id] {
        visit(child)
      }
    }
    restore_expr_table(expressions, local_entries)
  }
  visit(0)
  result
}

///|
pub fn eliminate_dead_code(func : Function) -> OptResult {
  let result = OptResult::new()
  result.add_pass("dce")
  let used : @hashmap.HashMap[Int, Bool] = HashMap([])
  for block in func.blocks {
    for inst in block.instructions {
      for arg in inst.args {
        used.set(arg.id, true)
      }
    }
    if block.terminator is Some(term) {
      record_terminator_uses(used, term)
    }
  }
  for block in func.blocks {
    let kept : Array[Inst] = []
    for inst in block.instructions {
      if inst_has_side_effects(inst) || inst_result_is_used(inst, used) {
        kept.push(inst)
      } else {
        result.mark_changed()
      }
    }
    if result.changed && kept.length() != block.instructions.length() {
      block.instructions.clear()
      for inst in kept {
        block.instructions.push(inst)
      }
    }
  }
  result
}

///|
fn keep_values_by_index(
  values : Array[Value],
  keep_indices : Array[Int],
) -> Array[Value] {
  let kept : Array[Value] = []
  for index in keep_indices {
    if index >= 0 && index < values.length() {
      kept.push(values[index])
    }
  }
  kept
}

///|
fn rewrite_target_args(
  target : Int,
  args : Array[Value],
  block_id : Int,
  keep_indices : Array[Int],
) -> Array[Value] {
  if target == block_id {
    keep_values_by_index(args, keep_indices)
  } else {
    args
  }
}

///|
fn rewrite_terminator_args_for_block(
  term : Terminator,
  block_id : Int,
  keep_indices : Array[Int],
) -> Terminator {
  match term {
    Jump(target, args) =>
      Jump(target, rewrite_target_args(target, args, block_id, keep_indices))
    Branch(cond, true_target, true_args, false_target, false_args) =>
      Branch(
        cond,
        true_target,
        rewrite_target_args(true_target, true_args, block_id, keep_indices),
        false_target,
        rewrite_target_args(false_target, false_args, block_id, keep_indices),
      )
    _ => term
  }
}

///|
/// Remove block parameters that are not used by any instruction or terminator,
/// and drop the corresponding incoming edge arguments.
///
/// TODO(milkir): add a dataflow variant that can remove parameters which are
/// only forwarded through other block parameters and never reach a real use.
pub fn eliminate_dead_block_params(func : Function) -> OptResult {
  let result = OptResult::new()
  result.add_pass("dead_block_param_elim")
  let used : @hashmap.HashMap[Int, Bool] = HashMap([])
  for block in func.blocks {
    for inst in block.instructions {
      for arg in inst.args {
        used.set(arg.id, true)
      }
    }
    if block.terminator is Some(term) {
      record_terminator_uses(used, term)
    }
  }
  for block in func.blocks {
    if block.params.length() == 0 {
      continue
    }
    let keep_indices : Array[Int] = []
    let kept_params : Array[Value] = []
    for i, param in block.params {
      if used.get(param.id).unwrap_or(false) {
        keep_indices.push(i)
        kept_params.push(param)
      }
    }
    if kept_params.length() == block.params.length() {
      continue
    }
    block.params.clear()
    for param in kept_params {
      block.params.push(param)
    }
    for pred in func.blocks {
      if pred.terminator is Some(term) {
        pred.terminator = Some(
          rewrite_terminator_args_for_block(term, block.id, keep_indices),
        )
      }
    }
    result.mark_changed()
  }
  result
}

///|
/// Remove blocks that cannot be reached from the entry block.
pub fn eliminate_unreachable_blocks(func : Function) -> OptResult {
  let result = OptResult::new()
  result.add_pass("eliminate_unreachable")
  if func.blocks.length() == 0 {
    return result
  }
  let cfg = CFG::build(func)
  let reachable = Array::make(cfg.size, false)
  let worklist : Array[Int] = [func.blocks[0].id]
  while worklist.length() > 0 {
    let block_id = worklist.pop().unwrap()
    if !cfg.is_valid(block_id) || reachable[block_id] {
      continue
    }
    reachable[block_id] = true
    for succ in cfg.get_successors(block_id) {
      if !reachable[succ] {
        worklist.push(succ)
      }
    }
  }
  let kept : Array[Block] = []
  for block in func.blocks {
    if block.id >= 0 && block.id < reachable.length() && reachable[block.id] {
      kept.push(block)
    } else {
      result.mark_changed()
    }
  }
  if result.changed {
    func.blocks.clear()
    for block in kept {
      func.blocks.push(block)
    }
  }
  result
}

///|
fn merge_opt_result(result : OptResult, pass_result : OptResult) -> Unit {
  if pass_result.changed {
    result.mark_changed()
  }
  for pass in pass_result.passes_run {
    result.add_pass(pass)
  }
}

///|
pub fn optimize_with_level(func : Function, level : OptLevel) -> OptResult {
  match level {
    O0 => OptResult::new()
    O1 => fold_constants(func)
    O2 | O3 => {
      let result = OptResult::new()
      merge_opt_result(result, fold_constants(func))
      merge_opt_result(result, eliminate_common_subexpressions(func))
      merge_opt_result(result, eliminate_dead_code(func))
      merge_opt_result(result, eliminate_dead_block_params(func))
      merge_opt_result(result, eliminate_unreachable_blocks(func))
      result
    }
  }
}
