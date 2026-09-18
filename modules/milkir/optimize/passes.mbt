///|
using @analysis {
  type FunctionAnalysis,
  is_cheap_rematerializable_constant,
  compute_use_counts,
  opcode_semantics,
}

///|
using @acyclic {run_acyclic_optimization_with_budget_and_analysis}
