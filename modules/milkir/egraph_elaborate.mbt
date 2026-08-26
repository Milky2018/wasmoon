// Elaboration: materialize e-graph extraction results back into MilkIR.
//
// Saturation discovers better forms for an expression, but a form only
// reaches the emitted code if some IR instruction is rewritten into it.
// Constant folding and GVN-style operand aliasing cover the cases where the
// better form already exists as a value; everything else — strength
// reduction, De Morgan rewrites, narrowed extend/reduce chains — needs the
// chosen node to be built. That is what this file does.

///|
/// How many new instructions one rewrite may introduce.
///
/// The cost model already prefers cheaper trees, but it prices a child
/// subtree even when that child is an IR value already sitting in a
/// register, so it can favour rebuilding over reuse. This budget bounds that
/// error: a rewrite needing more than a handful of new instructions is
/// abandoned rather than trusted. It also bounds planning depth, which is
/// why the planner may recurse.
const ELABORATION_BUDGET : Int = 4

///|
/// Reverse of `opcode_to_eopcode` for the opcodes MilkIR can spell.
///
/// Rules may produce e-nodes with no IR encoding (`Smin`, `Bmask`,
/// `SpaceshipS`, floats, vectors); those cannot be elaborated, and returning
/// `None` here is how the planner learns that.
fn eopcode_to_opcode(eop : @egraph.EOpcode) -> Opcode? {
  match eop {
    Const(c) => Some(Scalar(IntConst(c)))
    Add => Some(Scalar(IntBinary(Add)))
    Sub => Some(Scalar(IntBinary(Sub)))
    Mul => Some(Scalar(IntBinary(Mul)))
    And => Some(Scalar(IntBinary(And)))
    Or => Some(Scalar(IntBinary(Or)))
    Xor => Some(Scalar(IntBinary(Xor)))
    Shl => Some(Scalar(IntBinary(ShiftLeft)))
    Sshr => Some(Scalar(IntBinary(SignedShiftRight)))
    Ushr => Some(Scalar(IntBinary(UnsignedShiftRight)))
    Rotl => Some(Scalar(IntBinary(RotateLeft)))
    Rotr => Some(Scalar(IntBinary(RotateRight)))
    Bnot => Some(Scalar(IntUnary(Not)))
    Clz => Some(Scalar(IntUnary(CountLeadingZeros)))
    Ctz => Some(Scalar(IntUnary(CountTrailingZeros)))
    Popcnt => Some(Scalar(IntUnary(PopulationCount)))
    Icmp(cc) =>
      match ordinal_to_intcc(cc) {
        Some(cc) => Some(Scalar(IntCompare(cc)))
        None => None
      }
    Eq => Some(Scalar(IntCompare(Eq)))
    Ne => Some(Scalar(IntCompare(Ne)))
    Select => Some(Scalar(Select))
    Ireduce(_, _) => Some(Scalar(Convert(IntReduce)))
    Uextend(_, _) => Some(Scalar(Convert(UnsignedExtend)))
    Sextend(_, _) => Some(Scalar(Convert(SignedExtend)))
    _ => None
  }
}

///|
/// Inverse of `intcc_to_ordinal`.
fn ordinal_to_intcc(cc : Int) -> IntCC? {
  match cc {
    0 => Some(Eq)
    1 => Some(Ne)
    2 => Some(Slt)
    3 => Some(Sle)
    4 => Some(Sgt)
    5 => Some(Sge)
    6 => Some(Ult)
    7 => Some(Ule)
    8 => Some(Ugt)
    9 => Some(Uge)
    _ => None
  }
}

///|
/// Integer IR type for a bit width, for the widths MilkIR admits into the
/// e-graph. Other widths cannot be materialized.
fn int_type_for_bits(bits : Int) -> Type? {
  match bits {
    32 => Some(I32)
    64 => Some(I64)
    _ => None
  }
}

///|
/// IR type of a node's `index`-th child, given the node's own result type.
///
/// The admitted e-graph opcodes are integer-only, so operand types either
/// match the result, are fixed by the opcode's width parameters, or must be
/// read back from the child's e-class.
fn child_type_of(
  egraph : @egraph.EGraph,
  node : @egraph.ENode,
  index : Int,
  result_ty : Type,
) -> Type? {
  match node.op {
    // Same-type operands.
    Add
    | Sub
    | Mul
    | And
    | Or
    | Xor
    | Shl
    | Sshr
    | Ushr
    | Rotl
    | Rotr
    | Bnot
    | Clz
    | Ctz
    | Popcnt => Some(result_ty)
    // Comparisons produce a boolean; their operands share a width that only
    // the child class knows.
    Icmp(_) | Eq | Ne =>
      match egraph.get_bits(node.children[index]) {
        Some(bits) => int_type_for_bits(bits)
        None => None
      }
    // select(cond, a, b): the arms match the result, the condition is I32.
    Select => if index == 0 { Some(I32) } else { Some(result_ty) }
    // Conversions carry their source width in the opcode.
    Ireduce(from_bits, _) | Uextend(from_bits, _) | Sextend(from_bits, _) =>
      int_type_for_bits(from_bits)
    _ => None
  }
}

///|
/// Where an operand's value comes from at commit time.
///
/// Planning decides this, so committing never has to look anything up and
/// so can never fail. `FromStep` indexes `steps`, and post-order guarantees
/// the referenced step is earlier than the one naming it.
priv enum ElaborationOperand {
  Existing(Value)
  FromStep(Int)
}

///|
/// One instruction elaboration intends to create, resolved down to what
/// building it needs: no e-node, no lookups, nothing left to re-derive.
priv struct ElaborationStep {
  class_id : Int
  ty : Type
  opcode : Opcode
  operands : Array[ElaborationOperand]
}

///|
/// Plan how to obtain a value for `class_id` at type `ty`, appending the
/// classes that must be built to `steps`, children before parents.
///
/// Returns how the caller should reference the result, or `None` when the
/// shape cannot be built: no IR encoding (which covers `Var`, whose class
/// has no dominating binding here), an unknown operand type, a cycle, or
/// more work than the budget allows.
///
/// Everything this proves is recorded in the step rather than discarded.
/// Committing used to re-derive the opcode, the operand types and the
/// operand values, which put failure points after the first `new_value`
/// call; recording them is what removes those.
fn EGraphBuilder::collect_elaboration_steps(
  self : EGraphBuilder,
  best_nodes : Map[Int, @egraph.ENode],
  class_id : @egraph.EClassId,
  ty : Type,
  steps : Array[ElaborationStep],
  planned : Map[RepKey, Int],
  in_progress : @hashset.HashSet[Int],
) -> ElaborationOperand? {
  let canonical = self.egraph.find(class_id).0
  // Already available as an IR value that dominates this point: free.
  let key : RepKey = { class_id: canonical, ty, }
  if self.class_to_value.get(key) is Some(value) {
    return Some(Existing(value))
  }
  // Keyed by `RepKey`, not by class alone: one class can be needed at two
  // widths in a single plan, because constants are interned by value and so
  // are shared across widths, and `ireduce(shl(x, k)) = shl(ireduce(x), k)`
  // carries the shift amount across a width change unchanged. Keying on the
  // class would report the I64 build as satisfying the I32 operand, and the
  // commit below would then use an I64 value where an I32 one belongs.
  if planned.get(key) is Some(index) {
    return Some(FromStep(index))
  }
  // A class reached again while still being planned is a cyclic expression.
  // Class-keyed on purpose: a node of class C taking C as an operand is a
  // cycle whatever widths the two mentions carry.
  if in_progress.contains(canonical) {
    return None
  }
  if steps.length() >= ELABORATION_BUDGET {
    return None
  }
  guard best_nodes.get(canonical) is Some(node) else { return None }
  guard eopcode_to_opcode(node.op) is Some(opcode) else { return None }
  in_progress.add(canonical)
  let operands : Array[ElaborationOperand] = []
  for index in 0..<node.children.length() {
    guard child_type_of(self.egraph, node, index, ty) is Some(child_ty) else {
      in_progress.remove(canonical)
      return None
    }
    guard self.collect_elaboration_steps(
        best_nodes,
        node.children[index],
        child_ty,
        steps,
        planned,
        in_progress,
      )
      is Some(operand) else {
      in_progress.remove(canonical)
      return None
    }
    operands.push(operand)
  }
  in_progress.remove(canonical)
  // Post-order: every operand of this node is already scheduled, so this
  // step's index is greater than every index it names.
  let index = steps.length()
  planned.set(key, index)
  steps.push({ class_id: canonical, ty, opcode, operands, })
  Some(FromStep(index))
}

///|
/// Rewrite `inst` into the form extraction chose for its e-class, appending
/// any instructions needed to build that form's operands to `emitted`.
///
/// Returns whether the instruction changed. An abandoned rewrite leaves no
/// trace at all: nothing appended, `inst` untouched, `value_map` unchanged,
/// and `func`'s value and instruction counters where they were.
///
/// That last part is why planning resolves the whole shape before building
/// starts. `new_value` and `new_inst` advance counters on `func`, so any
/// failure point reached after the first of them leaks IDs no matter what
/// the rewrite stages and discards. Planning records the opcode, the operand
/// types and the operand sources into each step, which leaves the build loop
/// below with nothing to check and therefore no way to fail partway.
fn EGraphBuilder::elaborate_inst(
  self : EGraphBuilder,
  func : Function,
  best_nodes : Map[Int, @egraph.ENode],
  inst : Inst,
  emitted : Array[Inst],
) -> Bool {
  guard inst.first_result() is Some(result) else { return false }
  guard self.lookup_value(result) is Some(class_id) else { return false }
  let canonical = class_id.0
  guard best_nodes.get(canonical) is Some(node) else { return false }
  // `Var` has no IR encoding, so the guard above already rejected it: the
  // class is best represented by an existing value, which operand rewriting
  // handles.
  guard eopcode_to_opcode(node.op) is Some(opcode) else { return false }
  // Nothing to do when the instruction already has the chosen shape.
  if opcode == inst.opcode && self.operands_match(node, inst) {
    return false
  }
  // Plan the whole shape first. Every way this rewrite can fail lives in
  // here, before anything is created.
  let steps : Array[ElaborationStep] = []
  let planned : Map[RepKey, Int] = Map([])
  let in_progress : @hashset.HashSet[Int] = HashSet([])
  in_progress.add(canonical)
  let root_operands : Array[ElaborationOperand] = []
  for index in 0..<node.children.length() {
    guard child_type_of(self.egraph, node, index, result.ty) is Some(child_ty) else {
      return false
    }
    guard self.collect_elaboration_steps(
        best_nodes,
        node.children[index],
        child_ty,
        steps,
        planned,
        in_progress,
      )
      is Some(operand) else {
      return false
    }
    root_operands.push(operand)
  }
  if steps.length() > ELABORATION_BUDGET {
    return false
  }
  // Past every point of failure. From here the work is total: each step
  // carries its own opcode and the source of each of its operands, and
  // post-order means a `FromStep` index is always one this loop has already
  // filled in. Nothing below can return, so nothing below can leave the
  // function half-changed.
  let built : Array[Value] = []
  for step in steps {
    let step_operands : Array[Value] = []
    for operand in step.operands {
      step_operands.push(
        match operand {
          Existing(value) => value
          FromStep(index) => built[index]
        },
      )
    }
    let value = func.new_value(step.ty)
    let materialized = func.new_inst(step.opcode, step_operands, [value])
    emitted.push(materialized)
    self.register_def(materialized)
    built.push(value)
    self.ensure_value_slot(value.id)
    self.value_map[value.id] = Some(EClassId(step.class_id))
  }
  let new_operands : Array[Value] = []
  for operand in root_operands {
    let value = match operand {
      Existing(value) => value
      FromStep(index) => built[index]
    }
    new_operands.push(value)
  }
  inst.opcode = opcode
  inst.operands.clear()
  for value in new_operands {
    inst.operands.push(value)
  }
  true
}

///|
/// Whether the e-graph treats this opcode's two operands as interchangeable.
/// Canonicalization sorts such operands by class id, so an instruction can
/// differ from its chosen node by operand order alone.
fn eopcode_is_commutative(eop : @egraph.EOpcode) -> Bool {
  match eop {
    Add | Mul | And | Or | Xor | Eq | Ne => true
    _ => false
  }
}

///|
/// Whether `inst`'s operands already denote the node's children.
///
/// Commutative operands match in either order: rewriting `iadd a, b` into
/// `iadd b, a` is pure churn, and it would report progress forever.
fn EGraphBuilder::operands_match(
  self : EGraphBuilder,
  node : @egraph.ENode,
  inst : Inst,
) -> Bool {
  if inst.operands.length() != node.children.length() {
    return false
  }
  let operand_classes : Array[@egraph.EClassId] = []
  for operand in inst.operands {
    guard self.lookup_value(operand) is Some(operand_class) else {
      return false
    }
    operand_classes.push(operand_class)
  }
  let child_classes : Array[@egraph.EClassId] = []
  for child in node.children {
    child_classes.push(self.egraph.find(child))
  }
  if operand_classes.length() == 2 && eopcode_is_commutative(node.op) {
    return (
        operand_classes[0] == child_classes[0] &&
        operand_classes[1] == child_classes[1]
      ) ||
      (
        operand_classes[0] == child_classes[1] &&
        operand_classes[1] == child_classes[0]
      )
  }
  for index in 0..<operand_classes.length() {
    if operand_classes[index] != child_classes[index] {
      return false
    }
  }
  true
}
