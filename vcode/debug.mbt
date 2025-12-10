// Debug utilities for VCode analysis

///|
/// Dump VCode function for analysis (prints to stdout)
pub fn dump_vcode(func : VCodeFunction, tag : String) -> Unit {
  println("=== VCode Dump: \{tag} ===")
  println("Function: \{func.name}")
  println("Params: \{func.params.length()}")
  println("Blocks: \{func.blocks.length()}")
  println("")
  for block in func.blocks {
    println("Block \{block.id}:")
    let mut params_str = "  Params: ["
    for i, param in block.params {
      if i > 0 {
        params_str = params_str + ", "
      }
      params_str = params_str + param.to_string()
    }
    params_str = params_str + "]"
    println(params_str)
    for i, inst in block.insts {
      println("  [\{i}] \{inst}")
    }
    println("  Terminator: \{block.terminator}")
    println("")
  }
  println("=== End VCode Dump ===")
  println("")
}

///|
/// Dump register allocation details
pub fn dump_regalloc(
  func_name : String,
  liveness : LivenessResult,
  alloc : RegAllocResult,
) -> Unit {
  println("=== RegAlloc Dump: \{func_name} ===")
  println("Live Intervals:")
  for entry in liveness.intervals {
    let (_vreg_id, interval) = entry
    println("  \{interval}")
  }
  println("")
  println("Register Assignments:")
  for entry in alloc.assignments {
    let (vreg_id, preg) = entry
    println("  v\{vreg_id} -> \{preg}")
  }
  println("=== End RegAlloc Dump ===")
  println("")
}
