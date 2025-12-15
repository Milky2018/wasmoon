// ============ VCode Function ============

///|
/// VCode function - a complete function in VCode form
pub(all) struct VCodeFunction {
  name : String
  params : Array[@abi.VReg] // Function parameters
  results : Array[@abi.RegClass] // Result types (for return value allocation)
  result_types : Array[@ir.Type] // Full return type info for multi-value returns
  blocks : Array[@block.VCodeBlock]
  mut next_vreg_id : Int
  mut num_spill_slots : Int // Number of spill slots used by register allocator
  // Map from param index to allocated physical register (for params that cross calls)
  // This is filled by apply_allocation and used by emit_prologue
  param_pregs : Array[@abi.PReg?]
}

///|
pub fn VCodeFunction::new(name : String) -> VCodeFunction {
  {
    name,
    params: [],
    results: [],
    result_types: [],
    blocks: [],
    next_vreg_id: 0,
    num_spill_slots: 0,
    param_pregs: [],
  }
}

///|
pub fn VCodeFunction::new_vreg(
  self : VCodeFunction,
  class : @abi.RegClass,
) -> @abi.VReg {
  let id = self.next_vreg_id
  self.next_vreg_id = id + 1
  { id, class }
}

///|
pub fn VCodeFunction::add_param(
  self : VCodeFunction,
  class : @abi.RegClass,
) -> @abi.VReg {
  let vreg = self.new_vreg(class)
  self.params.push(vreg)
  vreg
}

///|
pub fn VCodeFunction::add_result(
  self : VCodeFunction,
  class : @abi.RegClass,
) -> Unit {
  self.results.push(class)
}

///|
/// Add a result type with full type information for multi-value returns
pub fn VCodeFunction::add_result_type(
  self : VCodeFunction,
  ty : @ir.Type,
) -> Unit {
  self.result_types.push(ty)
}

///|
/// Check if this function needs a hidden pointer for extra return values
/// Returns true if there are more than 2 integer or 2 float returns
pub fn VCodeFunction::needs_extra_results_ptr(self : VCodeFunction) -> Bool {
  let mut int_count = 0
  let mut float_count = 0
  for ty in self.result_types {
    if ty is (I32 | I64) {
      int_count = int_count + 1
    } else if ty is (F32 | F64) {
      float_count = float_count + 1
    }
  }
  int_count > 2 || float_count > 2
}

///|
/// Check if this function calls any function that returns more than 2 values
/// In that case, we need to allocate a local buffer for receiving extra results
pub fn VCodeFunction::calls_multi_value_function(self : VCodeFunction) -> Bool {
  for block in self.blocks {
    for inst in block.insts {
      if inst.opcode is CallIndirect(_, num_results) && num_results > 2 {
        return true
      }
    }
  }
  false
}

///|
pub fn VCodeFunction::new_block(self : VCodeFunction) -> @block.VCodeBlock {
  let id = self.blocks.length()
  let block = @block.VCodeBlock::new(id)
  self.blocks.push(block)
  block
}

///|
pub fn VCodeFunction::print(self : VCodeFunction) -> String {
  let mut result = "vcode \{self.name}("
  // Parameters
  for i, param in self.params {
    if i > 0 {
      result = result + ", "
    }
    result = result + param.to_string() + ":" + param.class.to_string()
  }
  result = result + ")"
  // Results
  if self.results.length() > 0 {
    result = result + " -> "
    if self.results.length() == 1 {
      result = result + self.results[0].to_string()
    } else {
      result = result + "("
      for i, r in self.results {
        if i > 0 {
          result = result + ", "
        }
        result = result + r.to_string()
      }
      result = result + ")"
    }
  }
  result = result + " {\n"
  // Blocks
  for block in self.blocks {
    result = result + "block\{block.id}"
    if block.params.length() > 0 {
      result = result + "("
      for i, param in block.params {
        if i > 0 {
          result = result + ", "
        }
        result = result + param.to_string() + ":" + param.class.to_string()
      }
      result = result + ")"
    }
    result = result + ":\n"
    // Instructions
    for inst in block.insts {
      result = result + "    \{inst}\n"
    }
    // Terminator
    if block.terminator is Some(term) {
      result = result + "    \{term}\n"
    }
  }
  result = result + "}\n"
  result
}

///|
pub impl Show for VCodeFunction with output(self, logger) {
  logger.write_string(self.print())
}
