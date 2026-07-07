// ============ Production MachV Function ============

///|
/// Machine-level value kind needed after MilkIR lowering.
///
/// Keep this in MachV instead of carrying `@milkir.Type` through register
/// allocation and emission.
pub(all) enum ValueKind {
  I32
  I64
  F32
  F64
  V128
  Ptr
} derive(Eq, Debug)

///|
/// MachV function - a complete machine-level function in virtual-register form.
pub(all) struct Function {
  name : String
  params : Array[@abi.VReg] // Function parameters
  results : Array[@abi.RegClass] // Result types (for return value allocation)
  result_kinds : Array[ValueKind] // Full return kind info for multi-value returns
  blocks : Array[@block.MachVBlock]
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
  // True when lowering materialized the embedding's primary memory base.
  mut uses_primary_memory_base : Bool
}

///|
pub fn Function::get_max_outgoing_args_size(self : Function) -> Int {
  self.max_outgoing_args_size
}

///|
pub fn Function::get_num_spill_slots(self : Function) -> Int {
  self.num_spill_slots
}

///|
pub fn Function::get_name(self : Function) -> String {
  self.name
}

///|
pub fn Function::get_params(self : Function) -> Array[@abi.VReg] {
  self.params
}

///|
pub fn Function::get_blocks(self : Function) -> Array[@block.MachVBlock] {
  self.blocks
}

///|
pub fn Function::get_param_pregs(self : Function) -> Array[@abi.PReg?] {
  self.param_pregs
}

///|
pub fn Function::get_result_kinds(self : Function) -> Array[ValueKind] {
  self.result_kinds
}

///|
pub fn Function::new(name : String) -> Function {
  {
    name,
    params: [],
    results: [],
    result_kinds: [],
    blocks: [],
    next_vreg_id: 0,
    num_spill_slots: 0,
    param_pregs: [],
    int_stack_params: 0,
    max_outgoing_args_size: 0,
    uses_primary_memory_base: false,
  }
}

///|
/// Clone the base structure of a function for regalloc transformations.
/// Copies: name, next_vreg_id, int_stack_params, max_outgoing_args_size,
/// uses_primary_memory_base
/// Empty: params, results, result_kinds, blocks, param_pregs
/// Zero: num_spill_slots
pub fn Function::clone_base(self : Function) -> Function {
  {
    name: self.name,
    params: [],
    results: [],
    result_kinds: [],
    blocks: [],
    next_vreg_id: self.next_vreg_id,
    num_spill_slots: 0,
    param_pregs: [],
    int_stack_params: self.int_stack_params,
    max_outgoing_args_size: self.max_outgoing_args_size,
    uses_primary_memory_base: self.uses_primary_memory_base,
  }
}

///|
/// Set the number of spill slots (called by register allocator)
pub fn Function::set_num_spill_slots(self : Function, n : Int) -> Unit {
  self.num_spill_slots = n
}

///|
/// Add a parameter physical register mapping (called by register allocator)
pub fn Function::add_param_preg(self : Function, preg : @abi.PReg?) -> Unit {
  self.param_pregs.push(preg)
}

///|
/// Set the number of integer stack parameters (called during lowering)
pub fn Function::set_int_stack_params(self : Function, n : Int) -> Unit {
  self.int_stack_params = n
}

///|
/// Update max outgoing args size if the new size is larger (called during lowering)
pub fn Function::update_max_outgoing_args_size(
  self : Function,
  size : Int,
) -> Unit {
  if size > self.max_outgoing_args_size {
    self.max_outgoing_args_size = size
  }
}

///|
pub fn Function::mark_uses_primary_memory_base(self : Function) -> Unit {
  self.uses_primary_memory_base = true
}

///|
pub fn Function::uses_primary_memory_base(self : Function) -> Bool {
  self.uses_primary_memory_base
}

///|
/// Push a parameter vreg directly (used during regalloc reconstruction)
pub fn Function::push_param(self : Function, vreg : @abi.VReg) -> Unit {
  self.params.push(vreg)
}

///|
pub fn Function::new_vreg(self : Function, class : @abi.RegClass) -> @abi.VReg {
  let id = self.next_vreg_id
  self.next_vreg_id = id + 1
  { id, class }
}

///|
pub fn Function::add_param(self : Function, class : @abi.RegClass) -> @abi.VReg {
  let vreg = self.new_vreg(class)
  self.params.push(vreg)
  vreg
}

///|
pub fn Function::add_result(self : Function, class : @abi.RegClass) -> Unit {
  self.results.push(class)
}

///|
/// Add a result kind with full kind information for multi-value returns
pub fn Function::add_result_kind(self : Function, ty : ValueKind) -> Unit {
  self.result_kinds.push(ty)
}

///|
/// Check if this function needs a hidden pointer for extra return values
/// Returns true if there are more than 2 integer or 2 float returns
pub fn Function::needs_extra_results_ptr(self : Function) -> Bool {
  let mut int_count = 0
  let mut float_count = 0
  for ty in self.result_kinds {
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
pub fn Function::calls_multi_value_function(self : Function) -> Bool {
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
/// Returns true if this function contains any call-like instruction.
pub fn Function::has_calls(self : Function) -> Bool {
  for block in self.blocks {
    for inst in block.insts {
      let call_type = inst.opcode.call_type()
      if call_type is Regular || call_type is TailCall {
        return true
      }
    }
  }
  false
}

///|
/// Returns true if context cache 0 caching should be enabled for this function.
pub fn Function::should_reserve_context_cache_0(self : Function) -> Bool {
  ignore(self)
  // Cranelift-style policy:
  // Keep memory base as a regular SSA value and let RA/CSE/LICM place it.
  // Do not reserve a dedicated physical register for context cache 0.
  false
}

///|
/// Returns true if the function loads the module `context cache 1` from embedding context.
/// Used to reserve a dedicated register for caching the context cache 1 pointer.
pub fn Function::uses_context_cache_1(self : Function) -> Bool {
  ignore(self)
  // Function-table layout is owned by the embedding runtime. MachV no longer
  // infers it from a built-in context offset.
  false
}

///|
/// Returns true if context cache 1 pointer caching should be enabled for this function.
pub fn Function::should_reserve_context_cache_1(self : Function) -> Bool {
  ignore(self)
  // Cranelift-style policy:
  // Keep context cache 1 pointer as a regular SSA value; avoid a dedicated pinned
  // physical register that increases global register pressure.
  false
}

///|
pub fn Function::new_block(self : Function) -> @block.MachVBlock {
  let id = self.blocks.length()
  let block = @block.MachVBlock::new(id)
  self.blocks.push(block)
  block
}

///|
pub fn Function::print(self : Function) -> String {
  let mut result = "machv \{self.name}("
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
pub impl Show for Function with fn output(self, logger) {
  logger.write_string(self.print())
}
