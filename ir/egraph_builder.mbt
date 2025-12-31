// EGraph IR Integration - converts IR to/from EGraph
// ============================================================================
// IR Integration - Convert IR instructions to/from EGraph
// ============================================================================

///|
/// Builder for constructing an EGraph from IR instructions
pub(all) struct EGraphBuilder {
  egraph : @egraph.EGraph
  // Map from IR Value id to EClassId
  value_map : Map[Int, @egraph.EClassId]
  // Map from IR Value id to its defining instruction
  def_map : Map[Int, Inst]
  // Ruleset for eager optimization
  ruleset : @egraph.IndexedRuleSet
}

///|
pub fn EGraphBuilder::new() -> EGraphBuilder {
  {
    egraph: @egraph.EGraph::new(),
    value_map: {},
    def_map: {},
    ruleset: @egraph.standard_rules_indexed(),
  }
}

///|
/// Register an instruction's definition
pub fn EGraphBuilder::register_def(self : EGraphBuilder, inst : Inst) -> Unit {
  match inst.result {
    Some(v) => self.def_map.set(v.id, inst)
    None => ()
  }
}

///|
/// Convert IntCC to an ordinal value
fn intcc_to_ordinal(cc : IntCC) -> Int {
  match cc {
    Eq => 0
    Ne => 1
    Slt => 2
    Sle => 3
    Sgt => 4
    Sge => 5
    Ult => 6
    Ule => 7
    Ugt => 8
    Uge => 9
  }
}

///|
/// Get bit width from IR Type
fn type_bits(ty : Type) -> Int {
  match ty {
    I32 => 32
    I64 => 64
    F32 => 32
    F64 => 64
    V128 => 128
    FuncRef | ExternRef => 64 // Pointer-sized
  }
}

///|
/// Convert an IR Opcode to an EOpcode (if optimizable)
/// Takes the instruction to extract type information for extend/reduce ops
fn opcode_to_eopcode(inst : Inst) -> @egraph.EOpcode? {
  match inst.opcode {
    Iconst(c) => Some(@egraph.EOpcode::Const(c))
    Iadd => Some(@egraph.EOpcode::Add)
    Isub => Some(@egraph.EOpcode::Sub)
    Imul => Some(@egraph.EOpcode::Mul)
    Sdiv => Some(@egraph.EOpcode::Sdiv)
    Udiv => Some(@egraph.EOpcode::Udiv)
    Srem => Some(@egraph.EOpcode::Srem)
    Urem => Some(@egraph.EOpcode::Urem)
    Band => Some(@egraph.EOpcode::And)
    Bor => Some(@egraph.EOpcode::Or)
    Bxor => Some(@egraph.EOpcode::Xor)
    Bnot => Some(@egraph.EOpcode::Bnot)
    Ishl => Some(@egraph.EOpcode::Shl)
    Sshr => Some(@egraph.EOpcode::Sshr)
    Ushr => Some(@egraph.EOpcode::Ushr)
    Rotl => Some(@egraph.EOpcode::Rotl)
    Rotr => Some(@egraph.EOpcode::Rotr)
    Clz => Some(@egraph.EOpcode::Clz)
    Ctz => Some(@egraph.EOpcode::Ctz)
    Popcnt => Some(@egraph.EOpcode::Popcnt)
    Icmp(cc) => Some(@egraph.EOpcode::Icmp(intcc_to_ordinal(cc)))
    Select => Some(@egraph.EOpcode::Select)
    Ireduce => {
      // ireduce: from_bits = operand type, to_bits = result type
      let from_bits = if inst.operands.length() > 0 {
        type_bits(inst.operands[0].ty)
      } else {
        64 // default
      }
      let to_bits = match inst.result {
        Some(v) => type_bits(v.ty)
        None => 32 // default
      }
      Some(@egraph.EOpcode::Ireduce(from_bits, to_bits))
    }
    Uextend => {
      // uextend: from_bits = operand type, to_bits = result type
      let from_bits = if inst.operands.length() > 0 {
        type_bits(inst.operands[0].ty)
      } else {
        32 // default
      }
      let to_bits = match inst.result {
        Some(v) => type_bits(v.ty)
        None => 64 // default
      }
      Some(@egraph.EOpcode::Uextend(from_bits, to_bits))
    }
    Sextend => {
      // sextend: from_bits = operand type, to_bits = result type
      let from_bits = if inst.operands.length() > 0 {
        type_bits(inst.operands[0].ty)
      } else {
        32 // default
      }
      let to_bits = match inst.result {
        Some(v) => type_bits(v.ty)
        None => 64 // default
      }
      Some(@egraph.EOpcode::Sextend(from_bits, to_bits))
    }
    _ => None // Not optimizable via e-graph
  }
}

///|
/// Add an IR value to the e-graph, recursively adding its definition
/// Uses eager optimization: rules are applied immediately when adding nodes
pub fn EGraphBuilder::add_value(
  self : EGraphBuilder,
  value : Value,
) -> @egraph.EClassId {
  // Check if already converted
  match self.value_map.get(value.id) {
    Some(id) => return self.egraph.find(id) // Return canonical id
    None => ()
  }

  // Get the bit width from the value's type
  let bits = type_bits(value.ty)

  // Look up the defining instruction
  let class_id = match self.def_map.get(value.id) {
    None => {
      // No definition found - treat as a variable (parameter or external)
      let id = self.egraph.add_var(value.id)
      self.egraph.set_type(id, bits)
      id
    }
    Some(inst) =>
      // Try to convert the opcode (pass full instruction for type info)
      match opcode_to_eopcode(inst) {
        None => {
          // Not an optimizable opcode - treat as variable
          let id = self.egraph.add_var(value.id)
          self.egraph.set_type(id, bits)
          id
        }
        Some(eop) =>
          match eop {
            Const(c) => {
              let id = self.egraph.add_const(c)
              self.egraph.set_type(id, bits)
              id
            }
            _ => {
              // Recursively add operands
              let children : Array[@egraph.EClassId] = []
              for operand in inst.operands {
                children.push(self.add_value(operand))
              }
              // Add the node with eager optimization and type info
              self.egraph.add_eager_typed(
                { op: eop, children },
                bits,
                self.ruleset,
              )
            }
          }
      }
  }
  self.value_map.set(value.id, class_id)
  class_id
}

///|
/// Run optimization on the e-graph
/// With eager optimization, this only needs to rebuild to restore invariants
pub fn EGraphBuilder::optimize(self : EGraphBuilder) -> Unit {
  self.egraph.rebuild()
}

///|
/// Get the optimized e-graph
pub fn EGraphBuilder::get_egraph(self : EGraphBuilder) -> @egraph.EGraph {
  self.egraph
}

///|
/// Extract the best expression for a given IR value
pub fn EGraphBuilder::extract(
  self : EGraphBuilder,
  value : Value,
) -> (Int, @egraph.ENode)? {
  match self.value_map.get(value.id) {
    Some(class_id) => Some(self.egraph.extract(class_id))
    None => None
  }
}

///|
/// Optimize a single basic block's arithmetic expressions
/// Returns a map from original Value id to optimized ENode
pub fn optimize_block(block : Block) -> Map[Int, (Int, @egraph.ENode)] {
  let builder = EGraphBuilder::new()

  // First pass: register all definitions
  for inst in block.instructions {
    builder.register_def(inst)
  }

  // Second pass: add all arithmetic values to e-graph
  for inst in block.instructions {
    match inst.result {
      Some(v) =>
        // Only add if it's an optimizable operation
        match opcode_to_eopcode(inst) {
          Some(_) => builder.add_value(v) |> ignore
          None => ()
        }
      None => ()
    }
  }

  // Run saturation
  builder.optimize()

  // Extract optimized results
  let results : Map[Int, (Int, @egraph.ENode)] = {}
  for inst in block.instructions {
    match inst.result {
      Some(v) =>
        match builder.extract(v) {
          Some(result) => results.set(v.id, result)
          None => ()
        }
      None => ()
    }
  }
  results
}

///|
/// Convert EOpcode back to IR Opcode
fn eopcode_to_opcode(eop : @egraph.EOpcode) -> Opcode? {
  match eop {
    Const(c) => Some(Iconst(c))
    Fconst(_) => None // Would need to convert bits to Fconst
    Add => Some(Iadd)
    Sub => Some(Isub)
    Mul => Some(Imul)
    Sdiv => Some(Sdiv)
    Udiv => Some(Udiv)
    Srem => Some(Srem)
    Urem => Some(Urem)
    And => Some(Band)
    Or => Some(Bor)
    Xor => Some(Bxor)
    Shl => Some(Ishl)
    Sshr => Some(Sshr)
    Ushr => Some(Ushr)
    Rotl => Some(Rotl)
    Rotr => Some(Rotr)
    Neg => None // Neg is synthetic, not in IR
    Bnot => Some(Bnot) // Bitwise NOT
    Clz => Some(Clz)
    Ctz => Some(Ctz)
    Popcnt => Some(Popcnt)
    Bswap => None // Not in IR
    Bitrev => None // Not in IR
    Icmp(_) => None // Would need to reconstruct IntCC
    Eq => None // Shorthand for Icmp, not direct IR op
    Ne => None // Shorthand for Icmp, not direct IR op
    Select => Some(Select)
    Bmask => None // Not in IR
    // Integer min/max - would need special lowering
    Smin => None
    Smax => None
    Umin => None
    Umax => None
    // Integer absolute value - would need special lowering
    Iabs => None
    Ireduce(_, _) => Some(Ireduce)
    Uextend(_, _) => Some(Uextend)
    Sextend(_, _) => Some(Sextend)
    // Float operations - map to IR float opcodes
    Fadd => Some(Fadd)
    Fsub => Some(Fsub)
    Fmul => Some(Fmul)
    Fdiv => Some(Fdiv)
    Fmin => Some(Fmin)
    Fmax => Some(Fmax)
    Fcopysign => None // Not directly in IR
    Fneg => Some(Fneg)
    Fabs => Some(Fabs)
    Fsqrt => Some(Fsqrt)
    Fceil => Some(Fceil)
    Ffloor => Some(Ffloor)
    Ftrunc => Some(Ftrunc)
    Fnearest => Some(Fnearest)
    Fcmp(_) => None // Would need to reconstruct FloatCC
    Fpromote => Some(Fpromote)
    Fdemote => Some(Fdemote)
    FcvtToSint => Some(FcvtToSint)
    FcvtToUint => Some(FcvtToUint)
    SintToFcvt => Some(SintToFcvt)
    UintToFcvt => Some(UintToFcvt)
    // Vector operations
    Splat => None // Would need type info for IR Splat
    Vconst(_) => None // Would need to convert to proper type
    Var(_) => None // Variable reference, not an instruction
  }
}

///|
/// Check if the extracted expression is simpler than the original
/// Returns Some(simplified_opcode) if optimization found, None otherwise
pub fn EGraphBuilder::get_simplified_opcode(
  self : EGraphBuilder,
  value : Value,
) -> Opcode? {
  match self.value_map.get(value.id) {
    None => None
    Some(class_id) => {
      let (_, best_node) = self.egraph.extract(class_id)
      // Check if it's a constant folding result
      match best_node.op {
        Const(c) => Some(Iconst(c))
        _ =>
          // Check if the opcode changed
          match self.def_map.get(value.id) {
            None => None
            Some(orig_inst) => {
              let orig_eop = opcode_to_eopcode(orig_inst)
              match orig_eop {
                None => None
                Some(orig) =>
                  // Compare opcodes ignoring type parameters
                  if orig.tag() != best_node.op.tag() {
                    eopcode_to_opcode(best_node.op)
                  } else {
                    None
                  }
              }
            }
          }
      }
    }
  }
}

///|
/// Apply e-graph optimization to a function
/// Returns true if any optimization was applied
pub fn optimize_function(func : Function) -> Bool {
  let mut changed = false
  for block in func.blocks {
    let builder = EGraphBuilder::new()

    // Register all definitions in this block
    for inst in block.instructions {
      builder.register_def(inst)
    }

    // Add all values to e-graph
    for inst in block.instructions {
      match inst.result {
        Some(v) =>
          match opcode_to_eopcode(inst) {
            Some(_) => builder.add_value(v) |> ignore
            None => ()
          }
        None => ()
      }
    }

    // Run saturation
    builder.optimize()

    // Apply optimizations - for now, just constant folding
    for inst in block.instructions {
      match inst.result {
        Some(v) =>
          match builder.get_simplified_opcode(v) {
            Some(Iconst(c)) => {
              // Replace with constant
              inst.opcode = Iconst(c)
              inst.operands.clear()
              changed = true
            }
            Some(_) =>
              // Other optimizations would require operand rewriting
              // For now, skip these
              ()
            None => ()
          }
        None => ()
      }
    }
  }
  changed
}
