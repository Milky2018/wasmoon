// ============ VCode Function ============

///|
/// VCode function - a complete function in VCode form
pub struct VCodeFunction {
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
  // Stack parameter count for ABI: tracks int overflow count for correct stack layout
  mut int_stack_params : Int
  // Maximum outgoing argument space needed by any call in this function
  // Pre-allocated in prologue so SP doesn't move during call sequences
  mut max_outgoing_args_size : Int
}

///|
pub fn VCodeFunction::get_max_outgoing_args_size(self : VCodeFunction) -> Int {
  self.max_outgoing_args_size
}

///|
pub fn VCodeFunction::get_num_spill_slots(self : VCodeFunction) -> Int {
  self.num_spill_slots
}

///|
pub fn VCodeFunction::get_name(self : VCodeFunction) -> String {
  self.name
}

///|
pub fn VCodeFunction::get_params(self : VCodeFunction) -> Array[@abi.VReg] {
  self.params
}

///|
pub fn VCodeFunction::get_blocks(
  self : VCodeFunction,
) -> Array[@block.VCodeBlock] {
  self.blocks
}

///|
pub fn VCodeFunction::get_param_pregs(
  self : VCodeFunction,
) -> Array[@abi.PReg?] {
  self.param_pregs
}

///|
pub fn VCodeFunction::get_result_types(self : VCodeFunction) -> Array[@ir.Type] {
  self.result_types
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
    int_stack_params: 0,
    max_outgoing_args_size: 0,
  }
}

///|
/// Clone the base structure of a function for regalloc transformations.
/// Copies: name, next_vreg_id, int_stack_params, max_outgoing_args_size
/// Empty: params, results, result_types, blocks, param_pregs
/// Zero: num_spill_slots
pub fn VCodeFunction::clone_base(self : VCodeFunction) -> VCodeFunction {
  {
    name: self.name,
    params: [],
    results: [],
    result_types: [],
    blocks: [],
    next_vreg_id: self.next_vreg_id,
    num_spill_slots: 0,
    param_pregs: [],
    int_stack_params: self.int_stack_params,
    max_outgoing_args_size: self.max_outgoing_args_size,
  }
}

///|
/// Set the number of spill slots (called by register allocator)
pub fn VCodeFunction::set_num_spill_slots(
  self : VCodeFunction,
  n : Int,
) -> Unit {
  self.num_spill_slots = n
}

///|
/// Add a parameter physical register mapping (called by register allocator)
pub fn VCodeFunction::add_param_preg(
  self : VCodeFunction,
  preg : @abi.PReg?,
) -> Unit {
  self.param_pregs.push(preg)
}

///|
/// Set the number of integer stack parameters (called during lowering)
pub fn VCodeFunction::set_int_stack_params(
  self : VCodeFunction,
  n : Int,
) -> Unit {
  self.int_stack_params = n
}

///|
/// Update max outgoing args size if the new size is larger (called during lowering)
pub fn VCodeFunction::update_max_outgoing_args_size(
  self : VCodeFunction,
  size : Int,
) -> Unit {
  if size > self.max_outgoing_args_size {
    self.max_outgoing_args_size = size
  }
}

///|
/// Push a parameter vreg directly (used during regalloc reconstruction)
pub fn VCodeFunction::push_param(
  self : VCodeFunction,
  vreg : @abi.VReg,
) -> Unit {
  self.params.push(vreg)
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
      if inst.opcode is CallPtr(_, num_results, _) && num_results > 2 {
        return true
      }
    }
  }
  false
}

///|
/// Returns true if the function uses `LoadMemBase(memidx=0)`.
/// Used to enable caching of the memory0 descriptor pointer in a reserved register.
pub fn VCodeFunction::uses_mem0(self : VCodeFunction) -> Bool {
  for block in self.blocks {
    for inst in block.insts {
      if inst.opcode is LoadMemBase(0) {
        return true
      }
    }
  }
  false
}

///|
/// Returns true if the function loads the module `func_table` from vmctx.
/// Used to reserve a dedicated register for caching the func_table pointer.
pub fn VCodeFunction::uses_func_table(self : VCodeFunction) -> Bool {
  for block in self.blocks {
    for inst in block.insts {
      if inst.opcode is Load(I64, @abi.VMCTX_FUNC_TABLE_OFFSET) {
        // The base should be vmctx (X19).
        if inst.uses.length() > 0 &&
          inst.uses[0] is Physical(preg) &&
          preg.index == @abi.REG_VMCTX {
          return true
        }
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
