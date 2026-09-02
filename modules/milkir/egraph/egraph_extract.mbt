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
/// Extraction state is indexed directly by eclass id. Costs and depths stay in
/// unboxed scalar arrays; the optional node is also the entry's presence bit.
/// This avoids rebuilding an `Option<(ExtractCost, ENode)>` object graph on
/// every successful relaxation.
priv struct ExtractionTable {
  op_costs : Array[Int]
  depths : Array[Int]
  nodes : Array[ENode?]
}

///|
fn extract_cost_max_finite() -> Int {
  @int.MAX_VALUE - 1
}

///|
const EXTRACT_INFINITY_DEPTH : Int = 255

///|
fn extract_cost_is_better(
  lhs_cost : Int,
  lhs_depth : Int,
  rhs_cost : Int,
  rhs_depth : Int,
) -> Bool {
  let infinity = extract_cost_max_finite()
  if lhs_cost == infinity {
    false
  } else if rhs_cost == infinity {
    true
  } else if lhs_cost < rhs_cost {
    true
  } else if lhs_cost > rhs_cost {
    false
  } else {
    lhs_depth < rhs_depth
  }
}

///|
fn extract_cost_add(lhs : Int, rhs : Int) -> Int {
  let max_finite = extract_cost_max_finite()
  if lhs == max_finite || rhs == max_finite || lhs > max_finite - rhs {
    max_finite
  } else {
    lhs + rhs
  }
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
  match table.nodes[canonical.0] {
    Some(node) =>
      if table.op_costs[canonical.0] == extract_cost_max_finite() {
        (@int.MAX_VALUE, node)
      } else {
        (table.op_costs[canonical.0], node)
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
  self.best_nodes_with_budget(@int.MAX_VALUE)
}

///|
/// Best node per class with an aggregate cap on e-nodes priced.
///
/// A partial table is safe: callers preserve the original IR for classes
/// whose best node was not established before the bound.
pub fn EGraph::best_nodes_with_budget(
  self : EGraph,
  max_work : Int,
) -> Map[Int, ENode] {
  let best : Map[Int, ENode] = Map([])
  let table = self.compute_extraction_table_with_budget(max_work)
  for class_id, entry in table.nodes {
    if entry is Some(node) {
      best.set(class_id, node)
    }
  }
  best
}

///|
/// Relax per-class best costs with a dependency worklist. A class is revisited
/// only when one of its children's costs improves.
fn EGraph::compute_extraction_table(self : EGraph) -> ExtractionTable {
  self.compute_extraction_table_with_budget(@int.MAX_VALUE)
}

///|
fn EGraph::compute_extraction_table_with_budget(
  self : EGraph,
  max_work : Int,
) -> ExtractionTable {
  let class_count = self.uf.parent.length()
  let table : ExtractionTable = {
    op_costs: Array::make(class_count, extract_cost_max_finite()),
    depths: Array::make(class_count, EXTRACT_INFINITY_DEPTH),
    nodes: Array::make(class_count, None),
  }
  let pending : Array[Int] = []
  let in_pending = Array::make(class_count, false)
  for class_id, eclass in self.classes {
    if eclass is Some(_) {
      pending.push(class_id)
      in_pending[class_id] = true
    }
  }
  let mut work = 0
  let mut exhausted = false
  while pending.pop() is Some(class_id) {
    in_pending[class_id] = false
    guard self.class_at(class_id) is Some(eclass) else { continue }
    let mut improved = false
    for node in eclass.nodes {
      if work >= max_work {
        exhausted = true
        break
      }
      work = work + 1
      let mut total_cost = node_cost(node)
      let mut total_depth = 0
      let mut priceable = true
      for child in node.children {
        let child_root = self.find(child).0
        match table.nodes[child_root] {
          Some(_) => {
            total_cost = extract_cost_add(
              total_cost,
              table.op_costs[child_root],
            )
            if table.depths[child_root] > total_depth {
              total_depth = table.depths[child_root]
            }
          }
          None => {
            priceable = false
            break
          }
        }
      }
      if !priceable {
        continue
      }
      if total_cost == extract_cost_max_finite() {
        total_depth = EXTRACT_INFINITY_DEPTH
      } else if total_depth < EXTRACT_INFINITY_DEPTH {
        total_depth = total_depth + 1
      }
      match table.nodes[class_id] {
        Some(best_node) =>
          if extract_cost_is_better(
              total_cost,
              total_depth,
              table.op_costs[class_id],
              table.depths[class_id],
            ) ||
            (
              total_cost == table.op_costs[class_id] &&
              total_depth == table.depths[class_id] &&
              extract_node_tiebreak_less(node, best_node)
            ) {
            table.op_costs[class_id] = total_cost
            table.depths[class_id] = total_depth
            table.nodes[class_id] = Some(node)
            improved = true
          }
        None => {
          table.op_costs[class_id] = total_cost
          table.depths[class_id] = total_depth
          table.nodes[class_id] = Some(node)
          improved = true
        }
      }
    }
    if exhausted {
      break
    }
    if improved && self.parent_list(class_id) is Some(owners) {
      for owner in owners {
        let root = self.uf.find(owner)
        if root >= 0 && root < in_pending.length() && !in_pending[root] {
          in_pending[root] = true
          pending.push(root)
        }
      }
    }
  }
  self.last_extraction_work = work
  self.last_extraction_budget_exhausted = exhausted
  table
}
