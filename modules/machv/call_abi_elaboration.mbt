///|
/// How a hidden safepoint describes roots already present in its arguments.
pub(all) enum StackMapArgumentRoots {
  Fixed(Int)
  I32ConstantOperand(Int)
  /// Infer the existing root arguments from the allocation helper signature.
  AllocationOperands
} derive(Debug, Eq)

///|
/// One external call whose runtime ABI requires an explicit stack-map id.
pub struct HiddenSafepointAbi {
  priv symbol : ExternalSymbol
  priv argument_roots : StackMapArgumentRoots
}

///|
pub fn HiddenSafepointAbi::new(
  symbol : ExternalSymbol,
  argument_roots : StackMapArgumentRoots,
) -> HiddenSafepointAbi {
  { symbol, argument_roots, }
}

///|
/// Runtime calls used to make caller-owned GC roots visible while a call runs.
pub struct CallerRootScopeAbi {
  priv push_symbol : ExternalSymbol
  priv pop_symbol : ExternalSymbol
}

///|
pub fn CallerRootScopeAbi::new(
  push_symbol : ExternalSymbol,
  pop_symbol : ExternalSymbol,
) -> CallerRootScopeAbi {
  { push_symbol, pop_symbol, }
}

///|
/// A constrained, target-neutral call-site ABI transformation.
pub struct CallAbiElaboration {
  priv root_scope : CallerRootScopeAbi?
  priv hidden_safepoints : Array[HiddenSafepointAbi]
}

///|
pub fn CallAbiElaboration::new(
  root_scope? : CallerRootScopeAbi,
  hidden_safepoints? : Array[HiddenSafepointAbi] = [],
) -> CallAbiElaboration {
  { root_scope, hidden_safepoints: hidden_safepoints.copy(), }
}

///|
pub suberror CallAbiElaborationError {
  InvalidInput(cause~ : MachVVerifyError)
  InvalidOutput(cause~ : MachVVerifyError)
  InvalidCall(instruction_id~ : Int, message~ : String)
} derive(Debug, Eq)

///|
pub impl Show for CallAbiElaborationError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
priv struct CallSiteRequirement {
  instruction : Instruction
  call : SemanticCall
  operands : Array[Value]
  metadata : InstructionMetadata
}

///|
fn FunctionConstruction::integer_constants(
  self : FunctionConstruction,
) -> Array[Int64?] {
  let constants : Array[Int64?] = Array::make(self.values.length(), None)
  for block_id in self.block_indices_in_cfg_order() {
    for instruction in self.blocks[block_id].instructions {
      let data = self.instructions[instruction.id]
      for result in data.results {
        constants[result.id] = match data.operation {
          I32Const(bits) =>
            Some(bits.reinterpret_as_int().to_int64() & 0xFFFFFFFFL)
          I64Const(bits) => Some(bits.reinterpret_as_int64())
          Copy if data.operands is [source] => constants[source.id]
          _ => None
        }
      }
    }
  }
  constants
}

///|
fn hidden_safepoint_abi(
  elaboration : CallAbiElaboration,
  call : SemanticCall,
) -> HiddenSafepointAbi? {
  guard call.callee is External(symbol) else { return None }
  for hidden in elaboration.hidden_safepoints {
    if hidden.symbol == symbol {
      return Some(hidden)
    }
  }
  None
}

///|
fn FunctionConstruction::call_context_operand(
  self : FunctionConstruction,
  instruction : Instruction,
  call : SemanticCall,
  operands : Array[Value],
) -> Value raise CallAbiElaborationError {
  let index = match call.protocol {
    Internal => if call.callee is Indirect { 1 } else { 0 }
    Platform => 0
  }
  guard index >= 0 &&
    index < operands.length() &&
    self.values[operands[index].id].ty == Ptr64 else {
    raise InvalidCall(
      instruction_id=instruction.id,
      message="caller root scope requires a ptr64 execution environment",
    )
  }
  operands[index]
}

///|
fn FunctionConstruction::hidden_argument_root_count(
  self : FunctionConstruction,
  instruction : Instruction,
  call : SemanticCall,
  abi : HiddenSafepointAbi,
  operands : Array[Value],
  constants : Array[Int64?],
) -> Int raise CallAbiElaborationError {
  match abi.argument_roots {
    Fixed(count) => {
      guard count >= 0 else {
        raise InvalidCall(
          instruction_id=instruction.id,
          message="hidden safepoint root count must be non-negative",
        )
      }
      count
    }
    I32ConstantOperand(index) => {
      guard index >= 0 && index < operands.length() else {
        raise InvalidCall(
          instruction_id=instruction.id,
          message="hidden safepoint root count operand is missing",
        )
      }
      let value = operands[index]
      guard self.values[value.id].ty == I32 &&
        constants[value.id] is Some(count) &&
        count >= 0L &&
        count <= 2147483647L else {
        raise InvalidCall(
          instruction_id=instruction.id,
          message="hidden safepoint root count must be a compile-time i32 constant",
        )
      }
      count.to_int()
    }
    AllocationOperands =>
      match call.signature.params {
        [Ptr64, I32, I32, I64] => 1
        [Ptr64, I32, Ptr64, I32] =>
          self.hidden_argument_root_count(
            instruction,
            call,
            HiddenSafepointAbi::new(abi.symbol, I32ConstantOperand(3)),
            operands,
            constants,
          )
        _ =>
          raise InvalidCall(
            instruction_id=instruction.id,
            message="allocation helper has an unsupported ABI",
          )
      }
  }
}

///|
fn FunctionConstruction::append_detached_instruction(
  self : FunctionConstruction,
  block : Block,
  operation : Operation,
  operands : Array[Value],
  result_types : Array[ValueType],
  metadata : InstructionMetadata,
) -> (Instruction, Array[Value]) {
  let instruction = Instruction::new(self.owner, self.instructions.length())
  let results : Array[Value] = []
  for index, ty in result_types {
    results.push(self.allocate_value(ty, InstructionResult(instruction, index)))
  }
  self.instructions.push({
    operation: operation.copy(),
    operands: operands.copy(),
    results,
    metadata: {
      source: metadata.source,
      live_gc_roots: metadata.live_gc_roots.copy(),
      stack_map: metadata.stack_map,
    },
    alive: true,
    parent: Some(block),
  })
  (instruction, results)
}

///|
fn root_scope_push_call(symbol : ExternalSymbol) -> SemanticCall {
  SemanticCall::new(
    External(symbol),
    Signature::new([Ptr64, Ptr64, I32], []),
    Platform,
    CallBehavior::new(ReadWrite, true, false, false, false),
  )
}

///|
fn root_scope_pop_call(symbol : ExternalSymbol) -> SemanticCall {
  SemanticCall::new(
    External(symbol),
    Signature::new([Ptr64], []),
    Platform,
    CallBehavior::new(ReadWrite, true, false, false, false),
  )
}

///|
fn FunctionConstruction::append_root_scope_push(
  self : FunctionConstruction,
  block : Block,
  destination : Array[Instruction],
  context : Value,
  roots : Array[Value],
  object : StackObject,
  symbol : ExternalSymbol,
) -> Unit {
  let (address_instruction, address_results) = self.append_detached_instruction(
    block,
    StackAddress(object),
    [],
    [Ptr64],
    InstructionMetadata::empty(),
  )
  destination.push(address_instruction)
  let address = address_results[0]
  for index, root in roots {
    let (store, _) = self.append_detached_instruction(
      block,
      Store(StoreSpec::new(W64, GcRef64, (index * 8).to_uint64(), Little, None)),
      [address, root],
      [],
      InstructionMetadata::empty(),
    )
    destination.push(store)
  }
  let (count_instruction, count_results) = self.append_detached_instruction(
    block,
    I32Const(roots.length().reinterpret_as_uint()),
    [],
    [I32],
    InstructionMetadata::empty(),
  )
  destination.push(count_instruction)
  let (push, _) = self.append_detached_instruction(
    block,
    Call(root_scope_push_call(symbol)),
    [context, address, count_results[0]],
    [],
    InstructionMetadata::empty(),
  )
  destination.push(push)
}

///|
fn FunctionConstruction::append_root_scope_pop(
  self : FunctionConstruction,
  block : Block,
  destination : Array[Instruction],
  context : Value,
  symbol : ExternalSymbol,
) -> Unit {
  let (pop, _) = self.append_detached_instruction(
    block,
    Call(root_scope_pop_call(symbol)),
    [context],
    [],
    InstructionMetadata::empty(),
  )
  destination.push(pop)
}

///|
/// Apply a constrained call-site ABI transformation in place.
///
/// Existing blocks, values, instructions, and metadata retain their identity.
/// The transformation may insert caller-root-scope calls and may append a
/// stack-map id operand to explicitly configured hidden safepoints. No-op
/// functions return without changing their canonical storage.
fn FunctionConstruction::elaborate_call_abi_verified(
  self : FunctionConstruction,
  elaboration : CallAbiElaboration,
) -> Unit raise CallAbiElaborationError {
  let mut root_scope_capacity = 0
  let mut needs_elaboration = false
  let mut has_hidden_safepoint = false
  for block in self.blocks {
    for instruction in block.instructions {
      let data = self.instructions[instruction.id]
      guard data.alive && data.operation is Call(call) else { continue }
      let hidden = hidden_safepoint_abi(elaboration, call)
      let has_roots = !data.metadata.live_gc_roots.is_empty()
      if !has_roots && hidden is None {
        continue
      }
      has_hidden_safepoint = has_hidden_safepoint || hidden is Some(_)
      if has_roots {
        guard elaboration.root_scope is Some(_) else {
          raise InvalidCall(
            instruction_id=instruction.id,
            message="live GC roots require a caller root-scope ABI",
          )
        }
        if call.behavior.returns_twice {
          raise InvalidCall(
            instruction_id=instruction.id,
            message="returns-twice calls cannot use a caller root scope",
          )
        }
        if data.metadata.live_gc_roots.length() > root_scope_capacity {
          root_scope_capacity = data.metadata.live_gc_roots.length()
        }
      }
      needs_elaboration = true
    }
  }
  if !needs_elaboration {
    return
  }
  let constants = if has_hidden_safepoint {
    Some(self.integer_constants())
  } else {
    None
  }
  let requirements : Array[CallSiteRequirement?] = Array::make(
    self.instructions.length(),
    None,
  )
  let argument_root_counts : Array[Int?] = Array::make(
    self.instructions.length(),
    None,
  )
  let mut next_stack_map_id = 0
  for data in self.instructions {
    if data.alive && data.metadata.stack_map is Some(stack_map) {
      if stack_map.id + 1 > next_stack_map_id {
        next_stack_map_id = stack_map.id + 1
      }
    }
  }
  for block in self.blocks {
    for instruction in block.instructions {
      let data = self.instructions[instruction.id]
      guard data.alive && data.operation is Call(call) else { continue }
      let hidden = hidden_safepoint_abi(elaboration, call)
      let has_roots = !data.metadata.live_gc_roots.is_empty()
      if !has_roots && hidden is None {
        continue
      }
      let metadata = match data.metadata.stack_map {
        Some(stack_map) =>
          InstructionMetadata::new(
            data.metadata.source,
            data.metadata.live_gc_roots,
            stack_map~,
          )
        None =>
          InstructionMetadata::new(
            data.metadata.source,
            data.metadata.live_gc_roots,
          )
      }
      if has_roots {
        self.call_context_operand(instruction, call, data.operands) |> ignore
      }
      if hidden is Some(abi) {
        if call.protocol != Platform || !call.behavior.gc_safepoint {
          raise InvalidCall(
            instruction_id=instruction.id,
            message="hidden safepoint must be a platform GC safepoint",
          )
        }
        if metadata.stack_map is Some(_) {
          raise InvalidCall(
            instruction_id=instruction.id,
            message="hidden safepoint already has stack-map metadata",
          )
        }
        argument_root_counts[instruction.id] = Some(
          self.hidden_argument_root_count(
            instruction,
            call,
            abi,
            data.operands,
            constants.unwrap(),
          ),
        )
      }
      requirements[instruction.id] = Some({
        instruction,
        call,
        operands: data.operands.copy(),
        metadata,
      })
    }
  }
  let root_scope_object = if root_scope_capacity > 0 {
    Some(self.allocate_stack_object(root_scope_capacity * 8, 16))
  } else {
    None
  }
  for block_index, block in self.blocks {
    let original = block.instructions.copy()
    let rewritten : Array[Instruction] = []
    for instruction in original {
      match requirements[instruction.id] {
        None => rewritten.push(instruction)
        Some(requirement) => {
          let context = if !requirement.metadata.live_gc_roots.is_empty() {
            let context = self.call_context_operand(
              requirement.instruction,
              requirement.call,
              requirement.operands,
            )
            let scope = elaboration.root_scope.unwrap()
            self.append_root_scope_push(
              Block::new(self.owner, block_index),
              rewritten,
              context,
              requirement.metadata.live_gc_roots,
              root_scope_object.unwrap(),
              scope.push_symbol,
            )
            Some(context)
          } else {
            None
          }
          if argument_root_counts[instruction.id] is Some(argument_root_count) {
            let (id_instruction, id_results) = self.append_detached_instruction(
              Block::new(self.owner, block_index),
              I32Const(next_stack_map_id.reinterpret_as_uint()),
              [],
              [I32],
              InstructionMetadata::empty(),
            )
            rewritten.push(id_instruction)
            let operands = requirement.operands.copy()
            operands.push(id_results[0])
            let parameters = requirement.call.signature.params.copy()
            parameters.push(I32)
            let old = self.instructions[instruction.id]
            self.instructions[instruction.id] = {
              operation: Call(
                SemanticCall::new(
                  requirement.call.callee,
                  Signature::new(parameters, requirement.call.signature.results),
                  requirement.call.protocol,
                  requirement.call.behavior,
                ),
              ),
              operands,
              results: old.results,
              metadata: InstructionMetadata::new(
                requirement.metadata.source,
                requirement.metadata.live_gc_roots,
                stack_map=StackMapMetadata::new(
                  next_stack_map_id,
                  argument_root_count~,
                ),
              ),
              alive: old.alive,
              parent: old.parent,
            }
            next_stack_map_id += 1
          }
          rewritten.push(instruction)
          if context is Some(context) {
            self.append_root_scope_pop(
              Block::new(self.owner, block_index),
              rewritten,
              context,
              elaboration.root_scope.unwrap().pop_symbol,
            )
          }
        }
      }
    }
    self.blocks[block_index].instructions.clear()
    self.blocks[block_index].instructions.append(rewritten)
  }
}

///|
/// Apply a constrained call-site ABI transformation in place.
///
/// Existing blocks, values, instructions, and metadata retain their identity.
/// The transformation may insert caller-root-scope calls and may append a
/// stack-map id operand to explicitly configured hidden safepoints. No-op
/// functions return without changing their canonical storage.
pub fn Function::elaborate_call_abi(
  self : Function,
  elaboration : CallAbiElaboration,
) -> Function raise CallAbiElaborationError {
  self.verify() catch {
    error => raise InvalidInput(cause=error)
  }
  self.verified = false
  self.as_construction().elaborate_call_abi_verified(elaboration)
  self.verify() catch {
    error => raise InvalidOutput(cause=error)
  }
  self
}

///|
/// Apply the same target-neutral call ABI directly to compact selection input.
pub fn SelectionPlan::elaborate_call_abi(
  self : SelectionPlan,
  elaboration : CallAbiElaboration,
) -> SelectionPlan raise CallAbiElaborationError {
  self.verify() catch {
    error => raise InvalidInput(cause=error)
  }
  self.verified = false
  self.construction.elaborate_call_abi_verified(elaboration)
  self.verify_checked_construction() catch {
    error => raise InvalidOutput(cause=error)
  }
  self
}
