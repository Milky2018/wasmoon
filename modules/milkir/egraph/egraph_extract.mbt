// Extraction: choosing one representative e-node per class.
//
// The cost model and its saturating arithmetic live here. Extraction reads
// the e-graph and writes nothing back, so it stays clear of the rebuild
// machinery in `egraph.mbt`.

// ============================================================================
// Cost model for extraction
// ============================================================================

///|
/// Cost of an e-node (lower is better)
fn node_cost(node : ENode) -> Int {
  match node.op {
    Const(_) => 0 // Constants are free
    Fconst(_) => 0 // Float constants are free
    Var(_) => 0 // Variables are free (already in registers)
    // Simple ALU ops
    Add | Sub => 1
    And | Or | Xor => 1
    Shl | Sshr | Ushr => 1
    Rotl | Rotr => 1
    Neg | Bnot => 1
    // Bit manipulation (usually single instruction)
    Clz | Ctz => 2
    Popcnt => 2
    Bswap => 2
    Bitrev => 3 // Bit reverse is more expensive on some architectures
    // Comparison
    Icmp(_) | Eq | Ne => 1
    // Conditional
    Select => 2
    Bmask => 1
    // Integer min/max (same cost as select - typically implemented with compare+select)
    Smin | Smax | Umin | Umax => 2
    // Integer absolute value
    Iabs => 2
    // Three-way comparison (two compares + subtract)
    SpaceshipS | SpaceshipU => 3
    // Type conversion (integer) - ignore bit width parameters for cost
    Ireduce(_, _) | Uextend(_, _) | Sextend(_, _) => 1
    // Expensive integer ops
    Mul => 3
    Sdiv | Udiv => 10
    Srem | Urem => 10
    // Float arithmetic (similar to integer on modern CPUs)
    Fadd | Fsub => 2
    Fmul => 3
    Fdiv => 10
    Fmin | Fmax => 2
    Fcopysign => 1
    // Float unary
    Fneg | Fabs => 1
    Fsqrt => 15 // Square root is expensive
    Fceil | Ffloor | Ftrunc | Fnearest => 2
    // Float comparison
    Fcmp(_) => 2
    // Float-integer conversion
    Fpromote | Fdemote => 2
    FcvtToSint | FcvtToUint => 3
    SintToFcvt | UintToFcvt => 3
    // Vector ops
    Splat => 2
    Vconst(_) => 0 // Vector constants are free
  }
}

///|
/// Extraction cost uses Cranelift-style ordering:
/// 1) lower op_cost is always better
/// 2) tie-break with shallower depth
/// Arithmetic is saturating and reserves an infinity sentinel.
priv struct ExtractCost {
  op_cost : Int
  depth : Int
  infinite : Bool
}

///|
fn extract_cost_max_finite() -> Int {
  @int.MAX_VALUE - 1
}

///|
const EXTRACT_INFINITY_DEPTH : Int = 255

///|
fn extract_cost_finite(op_cost : Int, depth : Int) -> ExtractCost {
  if op_cost >= extract_cost_max_finite() {
    extract_cost_infinity()
  } else {
    { op_cost, depth, infinite: false, }
  }
}

///|
fn extract_cost_infinity() -> ExtractCost {
  {
    op_cost: extract_cost_max_finite(),
    depth: EXTRACT_INFINITY_DEPTH,
    infinite: true,
  }
}

///|
fn extract_cost_is_better(lhs : ExtractCost, rhs : ExtractCost) -> Bool {
  if lhs.infinite {
    false
  } else if rhs.infinite {
    true
  } else if lhs.op_cost < rhs.op_cost {
    true
  } else if lhs.op_cost > rhs.op_cost {
    false
  } else {
    lhs.depth < rhs.depth
  }
}

///|
fn extract_cost_add(lhs : ExtractCost, rhs : ExtractCost) -> ExtractCost {
  if lhs.infinite || rhs.infinite {
    return extract_cost_infinity()
  }
  let max_finite = extract_cost_max_finite()
  let op_cost = if lhs.op_cost > max_finite - rhs.op_cost {
    return extract_cost_infinity()
  } else {
    lhs.op_cost + rhs.op_cost
  }
  let depth = if lhs.depth >= rhs.depth { lhs.depth } else { rhs.depth }
  extract_cost_finite(op_cost, depth)
}

///|
fn extract_cost_increment_depth(cost : ExtractCost) -> ExtractCost {
  if cost.infinite {
    return cost
  }
  let depth = if cost.depth >= EXTRACT_INFINITY_DEPTH {
    EXTRACT_INFINITY_DEPTH
  } else {
    cost.depth + 1
  }
  extract_cost_finite(cost.op_cost, depth)
}

///|
fn extract_cost_equal(lhs : ExtractCost, rhs : ExtractCost) -> Bool {
  lhs.infinite == rhs.infinite &&
  lhs.op_cost == rhs.op_cost &&
  lhs.depth == rhs.depth
}

///|
fn extract_node_tiebreak_less(lhs : ENode, rhs : ENode) -> Bool {
  lhs.compare(rhs) < 0
}

///|
/// Extract the best (lowest cost) expression from an e-class
/// Returns the total cost and the best e-node
///
/// Costs are computed with a bottom-up fixpoint over the whole e-graph
/// (egg-style relaxation) rather than a memoized DFS: a DFS that prices
/// re-entered classes as infinite while an ancestor is on the stack can
/// memoize that context-dependent infinity and poison later queries that
/// reach the class through a cycle-free route. The fixpoint has no
/// evaluation context, so every class settles to its true best cost.
pub fn EGraph::extract(self : EGraph, id : EClassId) -> (Int, ENode) {
  let canonical = self.find(id)
  let table = self.compute_extraction_table()
  match table.get(canonical.0) {
    Some((cost, node)) =>
      if cost.infinite {
        (@int.MAX_VALUE, node)
      } else {
        (cost.op_cost, node)
      }
    // No finite extraction exists (every node participates in a cycle).
    None => (@int.MAX_VALUE, { op: Var(-1), children: [], })
  }
}

///|
/// Best node per class root, computed once for the whole e-graph.
///
/// Elaboration needs every class's chosen node, not one class's, so it pays
/// for the shared fixpoint once instead of re-running extraction per value.
/// Classes with no finite extraction (every node cyclic) are absent.
pub fn EGraph::best_nodes(self : EGraph) -> Map[Int, ENode] {
  let best : Map[Int, ENode] = Map([])
  for class_id, entry in self.compute_extraction_table() {
    let (_, node) = entry
    best.set(class_id, node)
  }
  best
}

///|
/// Relax per-class best costs with a dependency worklist. A class is revisited
/// only when one of its children's costs improves.
fn EGraph::compute_extraction_table(
  self : EGraph,
) -> Map[Int, (ExtractCost, ENode)] {
  let table : Map[Int, (ExtractCost, ENode)] = Map([])
  let pending : Array[Int] = []
  let in_pending = Array::make(self.uf.parent.length(), false)
  for class_id, _ in self.classes {
    pending.push(class_id)
    in_pending[class_id] = true
  }
  while pending.pop() is Some(class_id) {
    in_pending[class_id] = false
    guard self.classes.get(class_id) is Some(eclass) else { continue }
    let mut improved = false
    for node in eclass.nodes {
      let mut total_cost = extract_cost_finite(node_cost(node), 0)
      let mut priceable = true
      for child in node.children {
        let child_root = self.find(child).0
        match table.get(child_root) {
          Some((child_cost, _)) =>
            total_cost = extract_cost_add(total_cost, child_cost)
          None => {
            priceable = false
            break
          }
        }
      }
      if !priceable {
        continue
      }
      total_cost = extract_cost_increment_depth(total_cost)
      match table.get(class_id) {
        Some((best_cost, best_node)) =>
          if extract_cost_is_better(total_cost, best_cost) ||
            (
              extract_cost_equal(total_cost, best_cost) &&
              extract_node_tiebreak_less(node, best_node)
            ) {
            table.set(class_id, (total_cost, node))
            improved = true
          }
        None => {
          table.set(class_id, (total_cost, node))
          improved = true
        }
      }
    }
    if improved && self.parents.get(class_id) is Some(owners) {
      for owner in owners {
        let root = self.uf.find(owner)
        if root >= 0 && root < in_pending.length() && !in_pending[root] {
          in_pending[root] = true
          pending.push(root)
        }
      }
    }
  }
  table
}
