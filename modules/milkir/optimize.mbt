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
fn resolve_copy(value : Value, copies : @hashmap.HashMap[Int, Value]) -> Value {
  let mut current = value
  let visited : @hashmap.HashMap[Int, Bool] = HashMap([])
  while true {
    if visited.get(current.id).unwrap_or(false) {
      break
    }
    visited.set(current.id, true)
    match copies.get(current.id) {
      Some(source) =>
        if source.id != current.id {
          current = source
        } else {
          break
        }
      None => break
    }
  }
  current
}

///|
fn rewrite_values_with_copies(
  values : Array[Value],
  copies : @hashmap.HashMap[Int, Value],
) -> Array[Value]? {
  let mut updated : Array[Value]? = None
  for i, value in values {
    let resolved = resolve_copy(value, copies)
    if resolved.id != value.id {
      if updated is None {
        updated = Some(values.copy())
      }
      if updated is Some(items) {
        items[i] = resolved
      }
    }
  }
  updated
}

///|
fn rewrite_terminator_with_copies(
  term : Terminator,
  copies : @hashmap.HashMap[Int, Value],
) -> Terminator? {
  match term {
    Return(values) =>
      match rewrite_values_with_copies(values, copies) {
        Some(updated) => Some(Return(updated))
        None => None
      }
    Jump(target, args) =>
      match rewrite_values_with_copies(args, copies) {
        Some(updated) => Some(Jump(target, updated))
        None => None
      }
    Branch(cond, true_target, true_args, false_target, false_args) => {
      let new_cond = resolve_copy(cond, copies)
      let new_true_args = rewrite_values_with_copies(true_args, copies).unwrap_or(
        true_args,
      )
      let new_false_args = rewrite_values_with_copies(false_args, copies).unwrap_or(
        false_args,
      )
      if new_cond.id != cond.id ||
        !value_arrays_equal(new_true_args, true_args) ||
        !value_arrays_equal(new_false_args, false_args) {
        Some(
          Branch(
            new_cond, true_target, new_true_args, false_target, new_false_args,
          ),
        )
      } else {
        None
      }
    }
    Brz(cond, true_target, false_target) => {
      let resolved = resolve_copy(cond, copies)
      if resolved.id != cond.id {
        Some(Brz(resolved, true_target, false_target))
      } else {
        None
      }
    }
    Brnz(cond, true_target, false_target) => {
      let resolved = resolve_copy(cond, copies)
      if resolved.id != cond.id {
        Some(Brnz(resolved, true_target, false_target))
      } else {
        None
      }
    }
    BrTable(index, targets, default_target) => {
      let resolved = resolve_copy(index, copies)
      if resolved.id != index.id {
        Some(BrTable(resolved, targets, default_target))
      } else {
        None
      }
    }
    TrapExit(_) => None
  }
}

///|
/// Replace local uses of `copy` results with their source values.
///
/// This pass is intentionally block-local; use `canonicalize_aliases` when
/// dominance information is required to propagate copies across blocks.
pub fn propagate_copies(func : Function) -> OptResult {
  let result = OptResult::new()
  result.add_pass("copy_prop")
  for block in func.blocks {
    let copies : @hashmap.HashMap[Int, Value] = HashMap([])
    for inst in block.instructions {
      if inst.opcode is Copy &&
        inst.results.length() == 1 &&
        inst.args.length() > 0 {
        copies.set(inst.results[0].id, inst.args[0])
      }
    }
    for inst in block.instructions {
      if rewrite_values_with_copies(inst.args, copies) is Some(updated_args) {
        inst.args.clear()
        for arg in updated_args {
          inst.args.push(arg)
        }
        result.mark_changed()
      }
    }
    if block.terminator is Some(term) {
      if rewrite_terminator_with_copies(term, copies) is Some(updated) {
        block.terminator = Some(updated)
        result.mark_changed()
      }
    }
  }
  result
}

///|
/// Resolve visible copy chains along the dominator tree.
pub fn canonicalize_aliases(func : Function) -> OptResult {
  let result = OptResult::new()
  result.add_pass("alias_canon")
  if func.blocks.length() == 0 {
    return result
  }
  let cfg = CFG::build(func)
  let idom = cfg.compute_dominators()
  let domtree = build_dominator_tree(idom)
  let block_index = build_block_index(func)
  let aliases : @hashmap.HashMap[Int, Value] = HashMap([])
  fn visit(block_id : Int) {
    guard block_index.get(block_id) is Some(index) else { return }
    let block = func.blocks[index]
    let local_aliases : Array[Int] = []
    for inst in block.instructions {
      if rewrite_values_with_copies(inst.args, aliases) is Some(updated_args) {
        inst.args.clear()
        for arg in updated_args {
          inst.args.push(arg)
        }
        result.mark_changed()
      }
      if inst.opcode is Copy &&
        inst.results.length() == 1 &&
        inst.args.length() > 0 {
        aliases.set(inst.results[0].id, inst.args[0])
        local_aliases.push(inst.results[0].id)
      }
    }
    if block.terminator is Some(term) {
      if rewrite_terminator_with_copies(term, aliases) is Some(updated) {
        block.terminator = Some(updated)
        result.mark_changed()
      }
    }
    if block_id >= 0 && block_id < domtree.length() {
      for child in domtree[block_id] {
        visit(child)
      }
    }
    for value_id in local_aliases {
      aliases.remove(value_id)
    }
  }
  let entry_id = func.blocks[0].id
  if cfg.is_valid(entry_id) {
    visit(entry_id)
  }
  result
}

///|
pub fn propagate_copies_global(func : Function) -> OptResult {
  canonicalize_aliases(func)
}

///|
fn collect_definition_blocks(
  func : Function,
) -> (@hashmap.HashMap[Int, Int], @hashmap.HashMap[Int, Inst]) {
  let def_block : @hashmap.HashMap[Int, Int] = HashMap([])
  let def_inst : @hashmap.HashMap[Int, Inst] = HashMap([])
  if func.blocks.length() > 0 {
    let entry_id = func.blocks[0].id
    for i, ty in func.signature.params {
      def_block.set(i, entry_id)
      ignore(ty)
    }
  }
  for block in func.blocks {
    for param in block.params {
      def_block.set(param.id, block.id)
    }
    for inst in block.instructions {
      if inst.results.length() == 1 {
        let value = inst.results[0]
        def_block.set(value.id, block.id)
        def_inst.set(value.id, inst)
      }
    }
  }
  (def_block, def_inst)
}

///|
fn collect_iconst_ids(func : Function) -> @hashmap.HashMap[Int, Unit] {
  let values : @hashmap.HashMap[Int, Unit] = HashMap([])
  for block in func.blocks {
    for inst in block.instructions {
      if inst.opcode is Iconst(_) && inst.results.length() == 1 {
        values.set(inst.results[0].id, ())
      }
    }
  }
  values
}

///|
fn is_remat_candidate(
  inst : Inst,
  iconst_values : @hashmap.HashMap[Int, Unit],
) -> Bool {
  guard inst.results.length() == 1 else { return false }
  match inst.opcode {
    Iconst(_) | Fconst(_) | Bnot => true
    Iadd | Isub | Band | Bor | Bxor =>
      if inst.args.length() == 2 {
        iconst_values.get(inst.args[0].id) is Some(_) ||
        iconst_values.get(inst.args[1].id) is Some(_)
      } else {
        false
      }
    _ => false
  }
}

///|
fn collect_remat_values(
  func : Function,
  iconst_values : @hashmap.HashMap[Int, Unit],
) -> @hashmap.HashMap[Int, Unit] {
  let values : @hashmap.HashMap[Int, Unit] = HashMap([])
  for block in func.blocks {
    for inst in block.instructions {
      if is_remat_candidate(inst, iconst_values) {
        values.set(inst.results[0].id, ())
      }
    }
  }
  values
}

///|
fn clone_remat_inst(func : Function, inst : Inst, result : Value) -> Inst {
  let cloned = func.new_inst(inst.opcode, inst.args.copy(), [result])
  for metadata in inst.metadata {
    cloned.metadata.push(metadata)
  }
  cloned
}

///|
fn rematerialize_value(
  func : Function,
  use_block_id : Int,
  value : Value,
  remat_values : @hashmap.HashMap[Int, Unit],
  def_block : @hashmap.HashMap[Int, Int],
  def_inst : @hashmap.HashMap[Int, Inst],
  cache : @hashmap.HashMap[Int, Value],
  insertion_point : Array[Inst],
  result : OptResult,
) -> Value {
  if remat_values.get(value.id) is None {
    return value
  }
  match def_block.get(value.id) {
    Some(block_id) => if block_id == use_block_id { return value }
    None => return value
  }
  match cache.get(value.id) {
    Some(existing) => existing
    None => {
      let inst = match def_inst.get(value.id) {
        Some(inst) => inst
        None => return value
      }
      if inst.results.length() != 1 {
        return value
      }
      let new_value = func.new_value(value.ty)
      insertion_point.push(clone_remat_inst(func, inst, new_value))
      cache.set(value.id, new_value)
      result.mark_changed()
      new_value
    }
  }
}

///|
fn rematerialize_values(
  func : Function,
  use_block_id : Int,
  values : Array[Value],
  remat_values : @hashmap.HashMap[Int, Unit],
  def_block : @hashmap.HashMap[Int, Int],
  def_inst : @hashmap.HashMap[Int, Inst],
  cache : @hashmap.HashMap[Int, Value],
  insertion_point : Array[Inst],
  result : OptResult,
) -> Array[Value]? {
  let mut updated : Array[Value]? = None
  for i, value in values {
    let remat = rematerialize_value(
      func, use_block_id, value, remat_values, def_block, def_inst, cache, insertion_point,
      result,
    )
    if remat.id != value.id {
      if updated is None {
        updated = Some(values.copy())
      }
      if updated is Some(items) {
        items[i] = remat
      }
    }
  }
  updated
}

///|
fn rematerialize_terminator_values(
  func : Function,
  use_block_id : Int,
  term : Terminator,
  remat_values : @hashmap.HashMap[Int, Unit],
  def_block : @hashmap.HashMap[Int, Int],
  def_inst : @hashmap.HashMap[Int, Inst],
  cache : @hashmap.HashMap[Int, Value],
  insertion_point : Array[Inst],
  result : OptResult,
) -> Terminator? {
  match term {
    Return(values) =>
      match
        rematerialize_values(
          func, use_block_id, values, remat_values, def_block, def_inst, cache, insertion_point,
          result,
        ) {
        Some(updated) => Some(Return(updated))
        None => None
      }
    Jump(target, args) =>
      match
        rematerialize_values(
          func, use_block_id, args, remat_values, def_block, def_inst, cache, insertion_point,
          result,
        ) {
        Some(updated) => Some(Jump(target, updated))
        None => None
      }
    Branch(cond, true_target, true_args, false_target, false_args) => {
      let new_cond = rematerialize_value(
        func, use_block_id, cond, remat_values, def_block, def_inst, cache, insertion_point,
        result,
      )
      let new_true_args = rematerialize_values(
        func, use_block_id, true_args, remat_values, def_block, def_inst, cache,
        insertion_point, result,
      ).unwrap_or(true_args)
      let new_false_args = rematerialize_values(
        func, use_block_id, false_args, remat_values, def_block, def_inst, cache,
        insertion_point, result,
      ).unwrap_or(false_args)
      if new_cond.id != cond.id ||
        !value_arrays_equal(new_true_args, true_args) ||
        !value_arrays_equal(new_false_args, false_args) {
        Some(
          Branch(
            new_cond, true_target, new_true_args, false_target, new_false_args,
          ),
        )
      } else {
        None
      }
    }
    Brz(cond, true_target, false_target) => {
      let remat = rematerialize_value(
        func, use_block_id, cond, remat_values, def_block, def_inst, cache, insertion_point,
        result,
      )
      if remat.id != cond.id {
        Some(Brz(remat, true_target, false_target))
      } else {
        None
      }
    }
    Brnz(cond, true_target, false_target) => {
      let remat = rematerialize_value(
        func, use_block_id, cond, remat_values, def_block, def_inst, cache, insertion_point,
        result,
      )
      if remat.id != cond.id {
        Some(Brnz(remat, true_target, false_target))
      } else {
        None
      }
    }
    BrTable(index, targets, default_target) => {
      let remat = rematerialize_value(
        func, use_block_id, index, remat_values, def_block, def_inst, cache, insertion_point,
        result,
      )
      if remat.id != index.id {
        Some(BrTable(remat, targets, default_target))
      } else {
        None
      }
    }
    TrapExit(_) => None
  }
}

///|
/// Rematerialize cheap, pure SSA definitions into each cross-block use.
///
/// This mirrors Cranelift's non-recursive rematerialization shape: constants,
/// bit-not, and integer ALU-with-constant definitions are cloned in the use
/// block once, immediately before their first use in that block.
pub fn rematerialize_across_blocks(func : Function) -> OptResult {
  let result = OptResult::new()
  result.add_pass("remat")
  let (def_block, def_inst) = collect_definition_blocks(func)
  let iconst_values = collect_iconst_ids(func)
  let remat_values = collect_remat_values(func, iconst_values)
  if remat_values.length() == 0 {
    return result
  }
  for block in func.blocks {
    let cache : @hashmap.HashMap[Int, Value] = HashMap([])
    let new_insts : Array[Inst] = []
    let old_len = block.instructions.length()
    for inst in block.instructions {
      if rematerialize_values(
          func,
          block.id,
          inst.args,
          remat_values,
          def_block,
          def_inst,
          cache,
          new_insts,
          result,
        )
        is Some(updated_args) {
        inst.args.clear()
        for arg in updated_args {
          inst.args.push(arg)
        }
      }
      new_insts.push(inst)
    }
    if block.terminator is Some(term) {
      if rematerialize_terminator_values(
          func,
          block.id,
          term,
          remat_values,
          def_block,
          def_inst,
          cache,
          new_insts,
          result,
        )
        is Some(updated) {
        block.terminator = Some(updated)
      }
    }
    if new_insts.length() != old_len {
      block.instructions.clear()
      for inst in new_insts {
        block.instructions.push(inst)
      }
    }
  }
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
fn collect_constants(func : Function) -> @hashmap.HashMap[Int, ConstValue] {
  let constants : @hashmap.HashMap[Int, ConstValue] = HashMap([])
  for block in func.blocks {
    for inst in block.instructions {
      record_const(inst, constants)
    }
  }
  constants
}

///|
fn int_const_is_zero(value : ConstValue) -> Bool? {
  match value {
    CI32(v) => Some(v == 0)
    CI64(v) => Some(v == 0L)
    _ => None
  }
}

///|
fn int_const_to_table_index(value : ConstValue) -> Int? {
  match value {
    CI32(v) => Some(v)
    // TODO(milkir): decide whether large i64 br_table indices should be
    // truncated or rejected by frontend-specific legality before simplifying.
    CI64(v) => Some(v.to_int())
    _ => None
  }
}

///|
/// Simplify conditional branches whose condition is a known integer constant.
pub fn simplify_branches(func : Function) -> OptResult {
  let result = OptResult::new()
  result.add_pass("simplify_branches")
  let constants = collect_constants(func)
  for block in func.blocks {
    match block.terminator {
      Some(Brz(cond, true_target, false_target)) =>
        if constants.get(cond.id) is Some(value) &&
          int_const_is_zero(value) is Some(is_zero) {
          block.terminator = Some(
            Jump(if is_zero { true_target } else { false_target }, []),
          )
          result.mark_changed()
        }
      Some(Brnz(cond, true_target, false_target)) =>
        if constants.get(cond.id) is Some(value) &&
          int_const_is_zero(value) is Some(is_zero) {
          block.terminator = Some(
            Jump(if !is_zero { true_target } else { false_target }, []),
          )
          result.mark_changed()
        }
      Some(BrTable(index, targets, default_target)) =>
        if constants.get(index.id) is Some(value) &&
          int_const_to_table_index(value) is Some(target_index) {
          let target = if target_index >= 0 && target_index < targets.length() {
            targets[target_index]
          } else {
            default_target
          }
          block.terminator = Some(Jump(target, []))
          result.mark_changed()
        }
      _ => ()
    }
  }
  result
}

///|
priv enum PhiAbstractValue {
  None
  One(Int)
  Many
} derive(Eq)

///|
fn PhiAbstractValue::join(
  self : PhiAbstractValue,
  other : PhiAbstractValue,
) -> PhiAbstractValue {
  match (self, other) {
    (None, v) => v
    (v, None) => v
    (Many, _) | (_, Many) => Many
    (One(a), One(b)) => if a == b { One(a) } else { Many }
  }
}

///|
fn build_value_array(func : Function, value_count : Int) -> Array[Value?] {
  let values : Array[Value?] = Array::make(value_count, None)
  for i, ty in func.signature.params {
    if i >= 0 && i < value_count {
      values[i] = Some({ id: i, ty })
    }
  }
  for block in func.blocks {
    for param in block.params {
      if param.id >= 0 && param.id < value_count {
        values[param.id] = Some(param)
      }
    }
    for inst in block.instructions {
      for result in inst.results {
        if result.id >= 0 && result.id < value_count {
          values[result.id] = Some(result)
        }
      }
    }
  }
  values
}

///|
fn build_block_index_array(func : Function) -> Array[Int] {
  let block_index = Array::make(func.next_block_id, -1)
  for i, block in func.blocks {
    if block.id >= 0 && block.id < block_index.length() {
      block_index[block.id] = i
    }
  }
  block_index
}

///|
fn compress_replace_array(replace_ids : Array[Int]) -> Unit {
  let count = replace_ids.length()
  for key in 0..<count {
    if replace_ids[key] < 0 {
      continue
    }
    let path : Array[Int] = []
    let mut current = key
    let mut steps = 0
    while steps < 1024 {
      path.push(current)
      if current < 0 || current >= count {
        break
      }
      let next = replace_ids[current]
      if next < 0 || next == current {
        break
      }
      current = next
      steps = steps + 1
    }
    for visited in path {
      if visited >= 0 && visited < count {
        replace_ids[visited] = current
      }
    }
  }
}

///|
fn collect_param_pairs(
  func : Function,
  block_index : Array[Int],
  state : Array[PhiAbstractValue?],
  target : Int,
  args : Array[Value],
  pairs : Array[(Int, Int)],
) -> Unit {
  if args.length() == 0 ||
    target < 0 ||
    target >= block_index.length() ||
    block_index[target] < 0 {
    return
  }
  let target_block = func.blocks[block_index[target]]
  let count = if target_block.params.length() < args.length() {
    target_block.params.length()
  } else {
    args.length()
  }
  for i in 0..<count {
    let formal = target_block.params[i]
    if formal.id >= 0 &&
      formal.id < state.length() &&
      state[formal.id] is Some(_) {
      pairs.push((formal.id, args[i].id))
    }
  }
}

///|
fn collect_propagation_pairs(
  func : Function,
  block_index : Array[Int],
  state : Array[PhiAbstractValue?],
) -> Array[(Int, Int)] {
  let pairs : Array[(Int, Int)] = []
  for block in func.blocks {
    match block.terminator {
      Some(Jump(target, args)) =>
        collect_param_pairs(func, block_index, state, target, args, pairs)
      Some(Branch(_, true_target, true_args, false_target, false_args)) => {
        collect_param_pairs(
          func, block_index, state, true_target, true_args, pairs,
        )
        collect_param_pairs(
          func, block_index, state, false_target, false_args, pairs,
        )
      }
      _ => ()
    }
  }
  pairs
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
fn keep_indices_for_target(
  target : Int,
  block_index : Array[Int],
  params_to_keep : Array[Array[Int]],
) -> Array[Int]? {
  if target >= 0 &&
    target < block_index.length() &&
    block_index[target] >= 0 &&
    block_index[target] < params_to_keep.length() {
    Some(params_to_keep[block_index[target]])
  } else {
    None
  }
}

///|
fn trim_terminator_args(
  term : Terminator,
  block_index : Array[Int],
  params_to_keep : Array[Array[Int]],
) -> Terminator? {
  match term {
    Jump(target, args) =>
      match keep_indices_for_target(target, block_index, params_to_keep) {
        Some(keep) =>
          if keep.length() != args.length() {
            Some(Jump(target, keep_values_by_index(args, keep)))
          } else {
            None
          }
        None => None
      }
    Branch(cond, true_target, true_args, false_target, false_args) => {
      let mut changed = false
      let new_true_args = match
        keep_indices_for_target(true_target, block_index, params_to_keep) {
        Some(keep) =>
          if keep.length() != true_args.length() {
            changed = true
            keep_values_by_index(true_args, keep)
          } else {
            true_args
          }
        None => true_args
      }
      let new_false_args = match
        keep_indices_for_target(false_target, block_index, params_to_keep) {
        Some(keep) =>
          if keep.length() != false_args.length() {
            changed = true
            keep_values_by_index(false_args, keep)
          } else {
            false_args
          }
        None => false_args
      }
      if changed {
        Some(
          Branch(cond, true_target, new_true_args, false_target, new_false_args),
        )
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn replacement_for(value : Value, replace_values : Array[Value?]) -> Value? {
  if value.id >= 0 && value.id < replace_values.length() {
    match replace_values[value.id] {
      Some(replacement) =>
        if replacement.id != value.id {
          Some(replacement)
        } else {
          None
        }
      None => None
    }
  } else {
    None
  }
}

///|
fn replace_value_array(
  values : Array[Value],
  replace_values : Array[Value?],
) -> Array[Value]? {
  let mut updated : Array[Value]? = None
  for i, value in values {
    if replacement_for(value, replace_values) is Some(replacement) {
      if updated is None {
        updated = Some(values.copy())
      }
      if updated is Some(items) {
        items[i] = replacement
      }
    }
  }
  updated
}

///|
fn replace_terminator_values(
  term : Terminator,
  replace_values : Array[Value?],
) -> Terminator? {
  match term {
    Return(values) =>
      match replace_value_array(values, replace_values) {
        Some(updated) => Some(Return(updated))
        None => None
      }
    Jump(target, args) =>
      match replace_value_array(args, replace_values) {
        Some(updated) => Some(Jump(target, updated))
        None => None
      }
    Branch(cond, true_target, true_args, false_target, false_args) => {
      let new_cond = replacement_for(cond, replace_values).unwrap_or(cond)
      let new_true_args = replace_value_array(true_args, replace_values).unwrap_or(
        true_args,
      )
      let new_false_args = replace_value_array(false_args, replace_values).unwrap_or(
        false_args,
      )
      if new_cond.id != cond.id ||
        !value_arrays_equal(new_true_args, true_args) ||
        !value_arrays_equal(new_false_args, false_args) {
        Some(
          Branch(
            new_cond, true_target, new_true_args, false_target, new_false_args,
          ),
        )
      } else {
        None
      }
    }
    Brz(cond, true_target, false_target) =>
      match replacement_for(cond, replace_values) {
        Some(replacement) => Some(Brz(replacement, true_target, false_target))
        None => None
      }
    Brnz(cond, true_target, false_target) =>
      match replacement_for(cond, replace_values) {
        Some(replacement) => Some(Brnz(replacement, true_target, false_target))
        None => None
      }
    BrTable(index, targets, default_target) =>
      match replacement_for(index, replace_values) {
        Some(replacement) => Some(BrTable(replacement, targets, default_target))
        None => None
      }
    TrapExit(_) => None
  }
}

///|
/// Remove block parameters that always receive the same SSA value.
///
/// This mirrors Cranelift-style constant-phi elimination at the generic MilkIR
/// level. It uses value identity only; frontend-specific numeric equivalence
/// belongs in separate legality-aware passes.
pub fn eliminate_constant_block_params(func : Function) -> OptResult {
  let result = OptResult::new()
  result.add_pass("const_block_param_elim")
  if func.blocks.length() == 0 || func.next_value_id <= 0 {
    return result
  }
  let entry_id = func.blocks[0].id
  let block_index = build_block_index_array(func)
  let state : Array[PhiAbstractValue?] = Array::make(func.next_value_id, None)
  let mut has_params = false
  for block in func.blocks {
    if block.id == entry_id {
      continue
    }
    for param in block.params {
      if param.id >= 0 && param.id < state.length() {
        state[param.id] = Some(None)
        has_params = true
      }
    }
  }
  if !has_params {
    return result
  }
  let pairs = collect_propagation_pairs(func, block_index, state)
  if pairs.length() == 0 {
    return result
  }
  let dependent_pairs : Array[Array[Int]?] = Array::make(
    func.next_value_id,
    None,
  )
  for pair_index, pair in pairs {
    let (_, actual_id) = pair
    if actual_id >= 0 &&
      actual_id < state.length() &&
      state[actual_id] is Some(_) {
      let deps = dependent_pairs[actual_id].unwrap_or([])
      deps.push(pair_index)
      dependent_pairs[actual_id] = Some(deps)
    }
  }
  let queue : Array[Int] = []
  let in_queue = Array::make(pairs.length(), false)
  for pair_index, _ in pairs {
    queue.push(pair_index)
    in_queue[pair_index] = true
  }
  let mut queue_head = 0
  let mut steps = 0
  let max_steps = pairs.length() * 16 + 1024
  while queue_head < queue.length() && steps < max_steps {
    let pair_index = queue[queue_head]
    queue_head = queue_head + 1
    in_queue[pair_index] = false
    steps = steps + 1
    let (formal_id, actual_id) = pairs[pair_index]
    if formal_id < 0 || formal_id >= state.length() {
      continue
    }
    let old_value = state[formal_id].unwrap_or(None)
    if old_value is Many {
      continue
    }
    let actual_value = if actual_id >= 0 && actual_id < state.length() {
      match state[actual_id] {
        Some(absval) => absval
        None => One(actual_id)
      }
    } else {
      One(actual_id)
    }
    let new_value = old_value.join(actual_value)
    if new_value != old_value {
      state[formal_id] = Some(new_value)
      if dependent_pairs[formal_id] is Some(deps) {
        for dep_index in deps {
          if dep_index >= 0 &&
            dep_index < in_queue.length() &&
            !in_queue[dep_index] {
            queue.push(dep_index)
            in_queue[dep_index] = true
          }
        }
      }
    }
  }

  let params_to_keep : Array[Array[Int]] = []
  let replace_ids = Array::make(func.next_value_id, -1)
  let mut will_change = false
  for block in func.blocks {
    let keep : Array[Int] = []
    for i, param in block.params {
      if param.id >= 0 && param.id < state.length() {
        match state[param.id] {
          Some(One(replacement_id)) => {
            replace_ids[param.id] = replacement_id
            will_change = true
          }
          _ => keep.push(i)
        }
      } else {
        keep.push(i)
      }
    }
    params_to_keep.push(keep)
  }
  if !will_change {
    return result
  }
  compress_replace_array(replace_ids)
  for block in func.blocks {
    if block.id >= 0 &&
      block.id < block_index.length() &&
      block_index[block.id] >= 0 &&
      block_index[block.id] < params_to_keep.length() {
      let keep = params_to_keep[block_index[block.id]]
      if keep.length() != block.params.length() {
        let old_params = block.params.copy()
        block.params.clear()
        for index in keep {
          block.params.push(old_params[index])
        }
        result.mark_changed()
      }
    }
  }
  for block in func.blocks {
    if block.terminator is Some(term) {
      if trim_terminator_args(term, block_index, params_to_keep)
        is Some(updated) {
        block.terminator = Some(updated)
        result.mark_changed()
      }
    }
  }
  let all_values = build_value_array(func, func.next_value_id)
  let replace_values : Array[Value?] = Array::make(func.next_value_id, None)
  for from_id, to_id in replace_ids {
    if to_id >= 0 && to_id < all_values.length() {
      replace_values[from_id] = all_values[to_id]
    }
  }
  for block in func.blocks {
    for inst in block.instructions {
      if replace_value_array(inst.args, replace_values) is Some(updated_args) {
        inst.args.clear()
        for arg in updated_args {
          inst.args.push(arg)
        }
        result.mark_changed()
      }
    }
    if block.terminator is Some(term) {
      if replace_terminator_values(term, replace_values) is Some(updated) {
        block.terminator = Some(updated)
        result.mark_changed()
      }
    }
  }
  result
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
fn value_arrays_equal(lhs : Array[Value], rhs : Array[Value]) -> Bool {
  if lhs.length() != rhs.length() {
    return false
  }
  for i in 0..<lhs.length() {
    if lhs[i].id != rhs[i].id {
      return false
    }
  }
  true
}

///|
fn rewrite_jump_args_through_block(
  block_params : Array[Value],
  incoming_args : Array[Value],
  outgoing_args : Array[Value],
) -> Array[Value]? {
  if block_params.length() != incoming_args.length() {
    return None
  }
  let param_to_arg : @hashmap.HashMap[Int, Value] = HashMap([])
  for i in 0..<block_params.length() {
    param_to_arg.set(block_params[i].id, incoming_args[i])
  }
  let rewritten : Array[Value] = []
  for arg in outgoing_args {
    rewritten.push(param_to_arg.get(arg.id).unwrap_or(arg))
  }
  Some(rewritten)
}

///|
fn resolve_jump_target_with_args(
  target : Int,
  args : Array[Value],
  func : Function,
  block_index : @hashmap.HashMap[Int, Int],
) -> (Int, Array[Value]) {
  let visited : @hashmap.HashMap[Int, Bool] = HashMap([])
  let mut current_target = target
  let mut current_args = args
  let mut done = false
  while !done {
    if visited.get(current_target).unwrap_or(false) {
      break
    }
    visited.set(current_target, true)
    let block = match block_index.get(current_target) {
      Some(index) => func.blocks[index]
      None => break
    }
    if block.instructions.length() != 0 {
      break
    }
    match block.terminator {
      Some(Jump(next_target, next_args)) =>
        match
          rewrite_jump_args_through_block(block.params, current_args, next_args) {
          Some(rewritten_args) => {
            current_target = next_target
            current_args = rewritten_args
          }
          None => done = true
        }
      _ => done = true
    }
  }
  (current_target, current_args)
}

///|
/// Bypass blocks that contain no instructions and only forward to another jump.
pub fn thread_jumps(func : Function) -> OptResult {
  let result = OptResult::new()
  result.add_pass("thread_jumps")
  let block_index = build_block_index(func)
  for block in func.blocks {
    match block.terminator {
      Some(Jump(target, args)) => {
        let (final_target, final_args) = resolve_jump_target_with_args(
          target, args, func, block_index,
        )
        if final_target != target || !value_arrays_equal(final_args, args) {
          block.terminator = Some(Jump(final_target, final_args))
          result.mark_changed()
        }
      }
      Some(Branch(cond, true_target, true_args, false_target, false_args)) => {
        let (new_true_target, new_true_args) = resolve_jump_target_with_args(
          true_target, true_args, func, block_index,
        )
        let (new_false_target, new_false_args) = resolve_jump_target_with_args(
          false_target, false_args, func, block_index,
        )
        if new_true_target != true_target ||
          new_false_target != false_target ||
          !value_arrays_equal(new_true_args, true_args) ||
          !value_arrays_equal(new_false_args, false_args) {
          block.terminator = Some(
            Branch(
              cond, new_true_target, new_true_args, new_false_target, new_false_args,
            ),
          )
          result.mark_changed()
        }
      }
      Some(Brz(cond, true_target, false_target)) => {
        let (resolved_true, true_args) = resolve_jump_target_with_args(
          true_target,
          [],
          func,
          block_index,
        )
        let (resolved_false, false_args) = resolve_jump_target_with_args(
          false_target,
          [],
          func,
          block_index,
        )
        let new_true = if true_args.length() == 0 {
          resolved_true
        } else {
          true_target
        }
        let new_false = if false_args.length() == 0 {
          resolved_false
        } else {
          false_target
        }
        if new_true != true_target || new_false != false_target {
          block.terminator = Some(Brz(cond, new_true, new_false))
          result.mark_changed()
        }
      }
      Some(Brnz(cond, true_target, false_target)) => {
        let (resolved_true, true_args) = resolve_jump_target_with_args(
          true_target,
          [],
          func,
          block_index,
        )
        let (resolved_false, false_args) = resolve_jump_target_with_args(
          false_target,
          [],
          func,
          block_index,
        )
        let new_true = if true_args.length() == 0 {
          resolved_true
        } else {
          true_target
        }
        let new_false = if false_args.length() == 0 {
          resolved_false
        } else {
          false_target
        }
        if new_true != true_target || new_false != false_target {
          block.terminator = Some(Brnz(cond, new_true, new_false))
          result.mark_changed()
        }
      }
      Some(BrTable(index, targets, default_target)) => {
        let new_targets : Array[Int] = []
        let mut any_changed = false
        for target in targets {
          let (resolved, args) = resolve_jump_target_with_args(
            target,
            [],
            func,
            block_index,
          )
          let new_target = if args.length() == 0 { resolved } else { target }
          new_targets.push(new_target)
          if new_target != target {
            any_changed = true
          }
        }
        let (resolved_default, default_args) = resolve_jump_target_with_args(
          default_target,
          [],
          func,
          block_index,
        )
        let new_default = if default_args.length() == 0 {
          resolved_default
        } else {
          default_target
        }
        if new_default != default_target {
          any_changed = true
        }
        if any_changed {
          block.terminator = Some(BrTable(index, new_targets, new_default))
          result.mark_changed()
        }
      }
      _ => ()
    }
  }
  result
}

///|
/// Merge straight-line blocks when a predecessor jumps directly to its only
/// successor, and that successor has only that predecessor.
pub fn merge_blocks(func : Function) -> OptResult {
  let result = OptResult::new()
  result.add_pass("merge_blocks")
  if func.blocks.length() <= 1 {
    return result
  }
  let pred_count : @hashmap.HashMap[Int, Int] = HashMap([])
  let succ_count : @hashmap.HashMap[Int, Int] = HashMap([])
  let single_pred : @hashmap.HashMap[Int, Int] = HashMap([])
  for block in func.blocks {
    pred_count.set(block.id, 0)
    succ_count.set(block.id, 0)
  }
  for block in func.blocks {
    if block.terminator is Some(term) {
      let targets = terminator_targets(term)
      succ_count.set(block.id, targets.length())
      for target in targets {
        let count = pred_count.get(target).unwrap_or(0)
        pred_count.set(target, count + 1)
        if count == 0 {
          single_pred.set(target, block.id)
        } else {
          single_pred.remove(target)
        }
      }
    }
  }
  let to_merge : Array[(Int, Int)] = []
  for block in func.blocks {
    if block.id == func.blocks[0].id || block.params.length() != 0 {
      continue
    }
    if pred_count.get(block.id).unwrap_or(0) == 1 &&
      single_pred.get(block.id) is Some(pred_id) &&
      succ_count.get(pred_id).unwrap_or(0) == 1 {
      for pred_block in func.blocks {
        if pred_block.id == pred_id {
          if pred_block.terminator is Some(Jump(_, args)) && args.length() == 0 {
            to_merge.push((pred_id, block.id))
          }
          break
        }
      }
    }
  }
  for pair in to_merge {
    let (pred_id, succ_id) = pair
    let mut pred_block : Block? = None
    let mut succ_block : Block? = None
    let mut succ_index = -1
    for i, block in func.blocks {
      if block.id == pred_id {
        pred_block = Some(block)
      }
      if block.id == succ_id {
        succ_block = Some(block)
        succ_index = i
      }
    }
    if (pred_block, succ_block) is (Some(pred), Some(succ)) && succ_index >= 0 {
      for inst in succ.instructions {
        pred.instructions.push(inst)
      }
      pred.terminator = succ.terminator
      func.blocks.remove(succ_index) |> ignore
      result.mark_changed()
    }
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
      merge_opt_result(result, canonicalize_aliases(func))
      merge_opt_result(result, eliminate_dead_code(func))
      merge_opt_result(result, simplify_branches(func))
      merge_opt_result(result, eliminate_constant_block_params(func))
      merge_opt_result(result, eliminate_dead_block_params(func))
      merge_opt_result(result, merge_blocks(func))
      merge_opt_result(result, thread_jumps(func))
      merge_opt_result(result, eliminate_unreachable_blocks(func))
      result
    }
  }
}
