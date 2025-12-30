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
}

///|
pub fn EGraphBuilder::new() -> EGraphBuilder {
  { egraph: @egraph.EGraph::new(), value_map: {}, def_map: {} }
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
/// Convert an IR Opcode to an EOpcode (if optimizable)
fn opcode_to_eopcode(opcode : Opcode) -> @egraph.EOpcode? {
  match opcode {
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
    Ishl => Some(@egraph.EOpcode::Shl)
    Sshr => Some(@egraph.EOpcode::Sshr)
    Ushr => Some(@egraph.EOpcode::Ushr)
    Icmp(cc) => Some(@egraph.EOpcode::Cmp(intcc_to_ordinal(cc)))
    _ => None // Not optimizable via e-graph
  }
}

///|
/// Add an IR value to the e-graph, recursively adding its definition
pub fn EGraphBuilder::add_value(
  self : EGraphBuilder,
  value : Value,
) -> @egraph.EClassId {
  // Check if already converted
  match self.value_map.get(value.id) {
    Some(id) => return id
    None => ()
  }

  // Look up the defining instruction
  let class_id = match self.def_map.get(value.id) {
    None =>
      // No definition found - treat as a variable (parameter or external)
      self.egraph.add_var(value.id)
    Some(inst) =>
      // Try to convert the opcode
      match opcode_to_eopcode(inst.opcode) {
        None =>
          // Not an optimizable opcode - treat as variable
          self.egraph.add_var(value.id)
        Some(eop) =>
          match eop {
            Const(c) => self.egraph.add_const(c)
            _ => {
              // Recursively add operands
              let children : Array[@egraph.EClassId] = []
              for operand in inst.operands {
                children.push(self.add_value(operand))
              }
              // Add the node to e-graph
              self.egraph.add({ op: eop, children })
            }
          }
      }
  }
  self.value_map.set(value.id, class_id)
  class_id
}

///|
/// Run optimization on the e-graph
pub fn EGraphBuilder::optimize(self : EGraphBuilder) -> Unit {
  self.egraph.saturate(@egraph.standard_rules(), 10) |> ignore
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
        match opcode_to_eopcode(inst.opcode) {
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
    Neg => None // Neg is synthetic, not in IR
    Bnot => Some(Bnot) // Bitwise NOT
    Cmp(_) => None // Would need to reconstruct IntCC
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
              let orig_eop = opcode_to_eopcode(orig_inst.opcode)
              match orig_eop {
                None => None
                Some(orig) =>
                  if orig != best_node.op {
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
          match opcode_to_eopcode(inst.opcode) {
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
