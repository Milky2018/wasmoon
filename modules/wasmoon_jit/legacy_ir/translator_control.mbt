///|
/// Translate an if-else construct
///
/// On-demand loading:
/// - Support block params (multi-value extension)
/// - Pass params to both then and else blocks
/// - Pass all mutable locals through continuation for SSA phi nodes
fn Translator::translate_if(
  self : Translator,
  block_type : @types.BlockType,
  then_body : Array[@types.Instruction],
  else_body : Array[@types.Instruction],
) -> Unit {
  // Save the unreachable state from outer context
  let outer_is_unreachable = self.is_unreachable
  let result_types = get_block_result_types(block_type, self.func_types)
  let param_types = get_block_param_types(block_type, self.func_types)

  // Pop condition first (it's on top of the stack)
  let cond = if outer_is_unreachable {
    // Create a dummy value when unreachable
    self.builder.iconst_i32(0)
  } else {
    self.pop()
  }

  // Pop param values from stack (Note: params are below condition)
  let param_values : Array[Value] = []
  if !outer_is_unreachable {
    for _ in 0..<param_types.length() {
      param_values.push(self.pop())
    }
    param_values.rev_in_place()
  }
  let then_block = self.builder.create_block()
  let else_block = self.builder.create_block()
  let continuation = self.builder.create_block()

  // Add block params to then_block and else_block for the if's input params
  for ty in param_types {
    self.builder.add_block_param(then_block, ty) |> ignore
    self.builder.add_block_param(else_block, ty) |> ignore
  }

  // Add continuation parameters for explicit results
  for ty in result_types {
    self.builder.add_block_param(continuation, ty) |> ignore
  }

  // Add continuation parameters for ALL locals (SSA phi nodes)
  let local_param_start = result_types.length()
  for loc in self.locals {
    self.builder.add_block_param(continuation, loc.ty) |> ignore
  }

  // Branch with param values (only if not unreachable)
  // Note: pass params to both then and else blocks
  if !outer_is_unreachable {
    if param_values.is_empty() {
      // No params, use simple branch
      self.builder.brnz(cond, then_block, else_block)
    } else {
      // Has params, use trampoline blocks to pass arguments
      let then_trampoline = self.builder.create_block()
      let else_trampoline = self.builder.create_block()
      self.builder.brnz(cond, then_trampoline, else_trampoline)
      // Then trampoline jumps to then_block with args
      self.builder.switch_to_block(then_trampoline)
      self.builder.jump(then_block, param_values)
      // Else trampoline jumps to else_block with args
      self.builder.switch_to_block(else_trampoline)
      self.builder.jump(else_block, param_values)
    }
  }

  // Record stack height AFTER popping params (for stack restoration)
  let stack_height_after_params = self.value_stack.length()

  // Push frame for then branch (else block as the "else" continuation)
  let frame : BlockFrame = {
    block: continuation,
    result_types,
    stack_height: stack_height_after_params,
  }
  self.block_stack.push(frame)

  // Save locals at entry for else branch
  let saved_locals = self.locals.copy()

  // Translate then body
  self.builder.switch_to_block(then_block)
  self.is_unreachable = outer_is_unreachable // Reset for then body

  // Push block params onto value stack (they become available in the then body)
  for i, _ty in param_types {
    self.push(then_block.params[i].0)
  }
  for instr in then_body {
    self.translate_instruction(instr)
  }

  // Jump to continuation from then block with locals (only if not unreachable)
  if !self.is_unreachable &&
    self.builder.current_block() is Some(block) &&
    block.terminator is None {
    let args : Array[Value] = []
    for _ in 0..<result_types.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Pass locals
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.jump(continuation, args)
  }

  // Restore stack to original height for else branch
  while self.value_stack.length() > frame.stack_height {
    self.pop() |> ignore
  }

  // Restore locals to entry state for else branch
  for i, loc in saved_locals {
    self.locals[i] = loc
  }

  // Translate else body
  self.builder.switch_to_block(else_block)
  self.is_unreachable = outer_is_unreachable // Reset for else body

  // Push block params onto value stack (they become available in the else body)
  for i, _ty in param_types {
    self.push(else_block.params[i].0)
  }
  for instr in else_body {
    self.translate_instruction(instr)
  }

  // Jump to continuation from else block with locals (only if not unreachable)
  if !self.is_unreachable &&
    self.builder.current_block() is Some(block) &&
    block.terminator is None {
    let args : Array[Value] = []
    for _ in 0..<result_types.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Pass locals
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.jump(continuation, args)
  }

  // Pop frame
  self.block_stack.pop() |> ignore

  // Switch to continuation
  self.builder.switch_to_block(continuation)

  // Continuation is reachable if outer was reachable.
  // Even if both branches end with `br 0` (making them "unreachable" after the br),
  // those branches jump TO the continuation, so the continuation is still reachable.
  // Only mark continuation unreachable if the outer context was unreachable.
  self.is_unreachable = outer_is_unreachable

  // Push results onto stack
  for i, _ty in result_types {
    self.push(continuation.params[i].0)
  }

  // Update locals to use the continuation's phi values
  for i, _loc in self.locals {
    self.locals[i] = continuation.params[local_param_start + i].0
  }
}

///|
/// Translate a br instruction
/// We need to pass both explicit params AND current local values
fn Translator::translate_br(self : Translator, depth : Int) -> Unit {
  let idx = self.block_stack.length() - 1 - depth
  if idx >= 0 && idx < self.block_stack.length() {
    // Jump to a block within the function
    let frame = self.block_stack[idx]
    let args : Array[Value] = []
    // Pop explicit block params
    for _ in 0..<frame.result_types.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Always pass current local values
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.jump(frame.block, args)
  } else if idx == -1 {
    // Jump to function level (early return)
    let ret_cont = self.get_or_create_return_continuation()
    let args : Array[Value] = []
    // Pop function result values
    for _ in 0..<self.func_result_types.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Always pass current local values
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.jump(ret_cont, args)
  }
  // After br, code is unreachable
  self.is_unreachable = true
}

///|
/// Translate a br_if instruction
/// Critical edge splitting is needed because brnz doesn't support block args
fn Translator::translate_br_if(self : Translator, depth : Int) -> Unit {
  let cond = self.pop()
  let idx = self.block_stack.length() - 1 - depth

  // For br_if, we need a fallthrough block and a taken block (critical edge split)
  let fallthrough = self.builder.create_block()
  let taken = self.builder.create_block()
  if idx >= 0 && idx < self.block_stack.length() {
    // Jump to a block within the function
    let frame = self.block_stack[idx]

    // Collect values that would be passed on branch
    let args : Array[Value] = []
    for i in 0..<frame.result_types.length() {
      args.push(
        self.value_stack[self.value_stack.length() -
        frame.result_types.length() +
        i],
      )
    }

    // Always pass current local values
    for loc in self.locals {
      args.push(loc)
    }

    // Branch: taken goes to intermediate block, not-taken falls through
    self.builder.brnz(cond, taken, fallthrough)

    // Critical edge split: taken block jumps to target with args
    self.builder.switch_to_block(taken)
    self.builder.jump(frame.block, args)

    // Continue with fallthrough
    self.builder.switch_to_block(fallthrough)
  } else if idx == -1 {
    // Jump to function level (early return)
    let ret_cont = self.get_or_create_return_continuation()

    // Collect values that would be passed on branch
    let args : Array[Value] = []
    for i in 0..<self.func_result_types.length() {
      args.push(
        self.value_stack[self.value_stack.length() -
        self.func_result_types.length() +
        i],
      )
    }

    // Always pass current local values
    for loc in self.locals {
      args.push(loc)
    }

    // Branch: taken goes to intermediate block, not-taken falls through
    self.builder.brnz(cond, taken, fallthrough)

    // Critical edge split: taken block jumps to return continuation
    self.builder.switch_to_block(taken)
    self.builder.jump(ret_cont, args)

    // Continue with fallthrough
    self.builder.switch_to_block(fallthrough)
  }
}

///|
/// Translate a br_on_null instruction
/// br_on_null: pop ref, branch if null, otherwise push non-null ref and continue
fn Translator::translate_br_on_null(self : Translator, depth : Int) -> Unit {
  let ref_val = self.pop()
  let idx = self.block_stack.length() - 1 - depth

  // Check if reference is null.
  let null_sentinel = self.builder.iconst(ref_val.ty, @types.NULL_REF)
  let is_null = self.builder.icmp_eq(ref_val, null_sentinel)

  // For br_on_null, we need a fallthrough block and a taken block (critical edge split)
  let fallthrough = self.builder.create_block()
  let taken = self.builder.create_block()
  if idx >= 0 && idx < self.block_stack.length() {
    let frame = self.block_stack[idx]

    // Collect values that would be passed on branch (not including the ref since it's null)
    let args : Array[Value] = []
    for i in 0..<frame.result_types.length() {
      args.push(
        self.value_stack[self.value_stack.length() -
        frame.result_types.length() +
        i],
      )
    }

    // Always pass current local values
    for loc in self.locals {
      args.push(loc)
    }

    // Branch: if null, go to taken block; otherwise fall through
    self.builder.brnz(is_null, taken, fallthrough)

    // Critical edge split: taken block jumps to target with args
    self.builder.switch_to_block(taken)
    self.builder.jump(frame.block, args)

    // Continue with fallthrough - push the non-null ref back on stack
    self.builder.switch_to_block(fallthrough)
    self.push(ref_val)
  } else if idx == -1 {
    // Jump to function level (early return)
    let ret_cont = self.get_or_create_return_continuation()
    let args : Array[Value] = []
    for i in 0..<self.func_result_types.length() {
      args.push(
        self.value_stack[self.value_stack.length() -
        self.func_result_types.length() +
        i],
      )
    }
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.brnz(is_null, taken, fallthrough)
    self.builder.switch_to_block(taken)
    self.builder.jump(ret_cont, args)
    self.builder.switch_to_block(fallthrough)
    self.push(ref_val)
  }
}

///|
/// Translate a br_on_non_null instruction
/// br_on_non_null: pop ref, branch with ref if non-null, otherwise continue
fn Translator::translate_br_on_non_null(self : Translator, depth : Int) -> Unit {
  let ref_val = self.pop()
  let idx = self.block_stack.length() - 1 - depth

  // Check if reference is null.
  let null_sentinel = self.builder.iconst(ref_val.ty, @types.NULL_REF)
  let is_null = self.builder.icmp_eq(ref_val, null_sentinel)

  // For br_on_non_null, we need a fallthrough block and a taken block
  let fallthrough = self.builder.create_block()
  let taken = self.builder.create_block()
  if idx >= 0 && idx < self.block_stack.length() {
    let frame = self.block_stack[idx]

    // Collect values that would be passed on branch
    // For br_on_non_null, we need to collect args BEFORE the ref was popped
    // The block expects result_types.length() values, and the ref is one of them
    // Since we already popped ref_val, we need to include it manually
    let args : Array[Value] = []
    // If the block expects N results, and the ref is one of them (the last one),
    // we need N-1 values from the stack plus the ref
    let stack_values_needed = frame.result_types.length() - 1
    for i in 0..<stack_values_needed {
      args.push(
        self.value_stack[self.value_stack.length() - stack_values_needed + i],
      )
    }
    // Add the ref as the last value (the non-null ref being passed)
    args.push(ref_val)

    // Always pass current local values
    for loc in self.locals {
      args.push(loc)
    }

    // Branch: if NOT null (is_null == false), go to taken block; otherwise fall through
    // Since is_null is 1 if null, 0 if non-null, we branch to fallthrough if null
    self.builder.brnz(is_null, fallthrough, taken)

    // Critical edge split: taken block jumps to target with args
    self.builder.switch_to_block(taken)
    self.builder.jump(frame.block, args)

    // Continue with fallthrough - reference is consumed (null), nothing pushed
    self.builder.switch_to_block(fallthrough)
  } else if idx == -1 {
    // Jump to function level (early return)
    let ret_cont = self.get_or_create_return_continuation()

    // Similar adjustment for function-level return
    let args : Array[Value] = []
    let stack_values_needed = self.func_result_types.length() - 1
    for i in 0..<stack_values_needed {
      args.push(
        self.value_stack[self.value_stack.length() - stack_values_needed + i],
      )
    }
    args.push(ref_val)
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.brnz(is_null, fallthrough, taken)
    self.builder.switch_to_block(taken)
    self.builder.jump(ret_cont, args)
    self.builder.switch_to_block(fallthrough)
  }
}

///|
/// Translate a br_on_cast instruction
/// br_on_cast: pop ref, if it matches target type, branch with the cast value;
/// otherwise push the original value and continue
fn Translator::translate_br_on_cast(
  self : Translator,
  depth : Int,
  target_type : @types.ValueType,
) -> Unit {
  let ref_val = self.pop()
  let idx = self.block_stack.length() - 1 - depth
  // Get the type index for the target type
  let type_idx = self.extract_type_idx(target_type)
  let nullable = target_type.is_nullable()
  // Use ref_test to check if the reference matches the target type
  let matches = self.builder.ref_test(type_idx, nullable, ref_val)
  // Create fallthrough and taken blocks
  let fallthrough = self.builder.create_block()
  let taken = self.builder.create_block()
  if idx >= 0 && idx < self.block_stack.length() {
    let frame = self.block_stack[idx]
    // Collect values that would be passed on branch (excluding the ref)
    let stack_values_needed = frame.result_types.length() - 1
    let stack_args : Array[Value] = []
    for i in 0..<stack_values_needed {
      stack_args.push(
        self.value_stack[self.value_stack.length() - stack_values_needed + i],
      )
    }
    // Branch: if matches (matches == 1), go to taken; otherwise fall through
    self.builder.brnz(matches, taken, fallthrough)
    // Critical edge split: taken block creates cast value and jumps to target
    self.builder.switch_to_block(taken)
    // Create the cast value in the taken block (we know the cast succeeded here)
    let cast_val = self.builder.ref_cast(type_idx, nullable, ref_val)
    let args : Array[Value] = []
    for v in stack_args {
      args.push(v)
    }
    args.push(cast_val)
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.jump(frame.block, args)
    // Continue with fallthrough - push the original ref back
    self.builder.switch_to_block(fallthrough)
    self.push(ref_val)
  } else if idx == -1 {
    // Jump to function level (early return)
    let ret_cont = self.get_or_create_return_continuation()
    let stack_values_needed = self.func_result_types.length() - 1
    let stack_args : Array[Value] = []
    for i in 0..<stack_values_needed {
      stack_args.push(
        self.value_stack[self.value_stack.length() - stack_values_needed + i],
      )
    }
    self.builder.brnz(matches, taken, fallthrough)
    self.builder.switch_to_block(taken)
    // Create the cast value in the taken block
    let cast_val = self.builder.ref_cast(type_idx, nullable, ref_val)
    let args : Array[Value] = []
    for v in stack_args {
      args.push(v)
    }
    args.push(cast_val)
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.jump(ret_cont, args)
    self.builder.switch_to_block(fallthrough)
    self.push(ref_val)
  }
}

///|
/// Translate a br_on_cast_fail instruction
/// br_on_cast_fail: pop ref, if it does NOT match target type, branch with the value;
/// otherwise push the cast value and continue
fn Translator::translate_br_on_cast_fail(
  self : Translator,
  depth : Int,
  target_type : @types.ValueType,
) -> Unit {
  let ref_val = self.pop()
  let idx = self.block_stack.length() - 1 - depth
  // Get the type index for the target type
  let type_idx = self.extract_type_idx(target_type)
  let nullable = target_type.is_nullable()
  // Use ref_test to check if the reference matches the target type
  let matches = self.builder.ref_test(type_idx, nullable, ref_val)
  // Create fallthrough and taken blocks
  let fallthrough = self.builder.create_block()
  let taken = self.builder.create_block()
  if idx >= 0 && idx < self.block_stack.length() {
    let frame = self.block_stack[idx]
    // Collect values that would be passed on branch (excluding the ref)
    let stack_values_needed = frame.result_types.length() - 1
    let stack_args : Array[Value] = []
    for i in 0..<stack_values_needed {
      stack_args.push(
        self.value_stack[self.value_stack.length() - stack_values_needed + i],
      )
    }
    // Build args for the taken (fail) branch - uses original ref_val
    let args : Array[Value] = []
    for v in stack_args {
      args.push(v)
    }
    args.push(ref_val)
    for loc in self.locals {
      args.push(loc)
    }
    // Branch: if NOT matches (matches == 0), go to taken; otherwise fall through
    // brnz branches if non-zero, so we invert: if matches, go to fallthrough
    self.builder.brnz(matches, fallthrough, taken)
    // Critical edge split: taken block jumps to target with original ref
    self.builder.switch_to_block(taken)
    self.builder.jump(frame.block, args)
    // Continue with fallthrough - push the cast ref (it matched)
    self.builder.switch_to_block(fallthrough)
    let cast_val = self.builder.ref_cast(type_idx, nullable, ref_val)
    self.push(cast_val)
  } else if idx == -1 {
    // Jump to function level (early return)
    let ret_cont = self.get_or_create_return_continuation()
    let stack_values_needed = self.func_result_types.length() - 1
    let stack_args : Array[Value] = []
    for i in 0..<stack_values_needed {
      stack_args.push(
        self.value_stack[self.value_stack.length() - stack_values_needed + i],
      )
    }
    // Build args for the taken (fail) branch - uses original ref_val
    let args : Array[Value] = []
    for v in stack_args {
      args.push(v)
    }
    args.push(ref_val)
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.brnz(matches, fallthrough, taken)
    self.builder.switch_to_block(taken)
    self.builder.jump(ret_cont, args)
    // Continue with fallthrough - push the cast ref (it matched)
    self.builder.switch_to_block(fallthrough)
    let cast_val = self.builder.ref_cast(type_idx, nullable, ref_val)
    self.push(cast_val)
  }
}

///|
/// Translate a br_table instruction
/// Uses critical edge splitting to pass block arguments properly
fn Translator::translate_br_table(
  self : Translator,
  labels : Array[Int],
  default_ : Int,
) -> Unit {
  let index = self.pop()

  // Helper to get target block and result types for a given depth
  // Returns (target_block, result_types, is_function_level)
  fn get_target(self : Translator, depth : Int) -> (Block, Array[Type], Bool) {
    let idx = self.block_stack.length() - 1 - depth
    if idx >= 0 && idx < self.block_stack.length() {
      let frame = self.block_stack[idx]
      (frame.block, frame.result_types, false)
    } else {
      // Function level
      let ret_cont = self.get_or_create_return_continuation()
      (ret_cont, self.func_result_types, true)
    }
  }

  // Get default target info
  let (default_block, default_result_types, _) = get_target(self, default_)

  // Collect arguments that would be passed on branch (same for all targets)
  // All targets must have the same result type as the default
  let args : Array[Value] = []
  let num_results = default_result_types.length()
  // Only collect results if we have enough values on the stack
  if self.value_stack.length() >= num_results {
    for i in 0..<num_results {
      args.push(self.value_stack[self.value_stack.length() - num_results + i])
    }
  }
  // Always pass current local values
  for loc in self.locals {
    args.push(loc)
  }

  // Save the original block
  let original_block = self.builder.current_block()

  // Phase 1: Create intermediate blocks for unique target depths.
  //
  // br_table payloads can be very large with many repeated labels. Emitting one
  // unique intermediate block per target depth keeps IR size bounded and avoids
  // O(table_size) extra blocks in translator hot paths.
  let intermediate_blocks : Array[Block] = []
  let unique_depths : Array[Int] = []
  let depth_to_intermediate : Map[Int, Block] = {}
  let default_intermediate = self.builder.create_block()
  for depth in labels {
    if depth == default_ {
      intermediate_blocks.push(default_intermediate)
      continue
    }
    if depth_to_intermediate.get(depth) is Some(existing) {
      intermediate_blocks.push(existing)
      continue
    }
    let intermediate = self.builder.create_block()
    depth_to_intermediate.set(depth, intermediate)
    unique_depths.push(depth)
    intermediate_blocks.push(intermediate)
  }

  // Phase 2: Emit br_table in original block
  if original_block is Some(_) {
    self.builder.br_table(index, intermediate_blocks, default_intermediate)
  }

  // Phase 3: Fill in unique intermediate blocks with jumps to real targets.
  for depth in unique_depths {
    guard depth_to_intermediate.get(depth) is Some(intermediate) else {
      continue
    }
    let (target_block, _, _) = get_target(self, depth)
    self.builder.switch_to_block(intermediate)
    self.builder.jump(target_block, args)
  }

  // Fill in default intermediate
  self.builder.switch_to_block(default_intermediate)
  self.builder.jump(default_block, args)

  // br_table is a terminator, code after it is unreachable
  // Don't switch back to original - leave current_block as the last intermediate
  self.is_unreachable = true
}

///|
/// Remap a local function index to global function index for cross-module calls
/// - For imports: use import_remap if available
/// - For local functions: add func_base
fn Translator::remap_func_idx(self : Translator, func_idx : Int) -> Int {
  if func_idx < self.num_imports {
    // Import function - use remap if available
    if self.import_remap.length() > 0 && func_idx < self.import_remap.length() {
      self.import_remap[func_idx]
    } else {
      func_idx
    }
  } else {
    // Local function - add base offset
    self.func_base + func_idx
  }
}

///|
/// Translate a direct call
fn Translator::translate_call(self : Translator, func_idx : Int) -> Unit {
  // Get function type
  let type_idx = if func_idx < self.num_imports {
    // Look up import function type
    if func_idx < self.import_func_type_indices.length() {
      self.import_func_type_indices[func_idx]
    } else {
      0 // Fallback
    }
  } else {
    let local_idx = func_idx - self.num_imports
    if local_idx < self.func_type_indices.length() {
      self.func_type_indices[local_idx]
    } else {
      0
    }
  }
  if type_idx < self.func_types.length() {
    let func_type = self.func_types[type_idx]
    // Pop arguments
    let args : Array[Value] = []
    for _ in 0..<func_type.params.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Get result types
    let result_types : Array[Type] = func_type.results.map(Type::from_wasm)
    // Remap function index for cross-module calls
    let global_func_idx = self.remap_func_idx(func_idx)
    // Emit call with multi-value support
    let results = self.builder.call_multi(global_func_idx, result_types, args)
    // Push all results onto the stack
    for v in results {
      self.push(v)
    }
  }
}

///|
/// Translate an indirect call
fn Translator::translate_call_indirect(
  self : Translator,
  type_idx : Int,
  table_idx : Int,
) -> Unit {
  if type_idx < self.func_types.length() {
    let func_type = self.func_types[type_idx]
    // Use original type_idx - the JIT type check (is_subtype_cached) handles
    // canonical indices internally to support both subtyping and structural equivalence
    // Pop callee (element index within the table)
    let elem_idx = self.pop()

    // Bounds check: elem_idx must be < table_size[table_idx]
    // Generate: if (elem_idx >= table_size) trap "out of bounds table access"
    if table_idx < self.table_sizes.length() {
      let table_size = self.table_sizes[table_idx]
      let size_const = self.builder.iconst(elem_idx.ty, table_size.to_int64())
      let out_of_bounds = self.builder.icmp_uge(elem_idx, size_const)

      // Create trap block and continuation block
      let trap_block = self.builder.create_block()
      let continue_block = self.builder.create_block()

      // Branch: if out_of_bounds goto trap_block else continue_block
      self.builder.brnz(out_of_bounds, trap_block, continue_block)

      // Trap block: emit trap instruction
      self.builder.switch_to_block(trap_block)
      self.builder.trap("out of bounds table access")

      // Continue block: proceed with call
      self.builder.switch_to_block(continue_block)
    }

    // Multi-table support: use elem_idx directly (no flattening needed)
    // The lowering phase handles table access via indirect_tables[table_idx]
    // Pop arguments
    let args : Array[Value] = []
    for _ in 0..<func_type.params.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Get result types
    let result_types : Array[Type] = func_type.results.map(Type::from_wasm)
    // Emit call_indirect with original type_idx
    // is_subtype_cached handles canonical indices for structural equivalence
    let results = self.builder.call_indirect_multi(
      type_idx, table_idx, result_types, elem_idx, args,
    )
    // Push all results onto the stack
    for v in results {
      self.push(v)
    }
  }
}

///|
/// Translate a call through function reference
fn Translator::translate_call_ref(self : Translator, type_idx : Int) -> Unit {
  if type_idx < self.func_types.length() {
    let func_type = self.func_types[type_idx]
    // Pop the function reference
    let func_ref = self.pop()

    // Null check: JIT null reference is NULL_REF (0)
    let null_sentinel = self.builder.iconst(func_ref.ty, @types.NULL_REF)
    let is_null = self.builder.icmp_eq(func_ref, null_sentinel)

    // Create trap block and continuation block
    let trap_block = self.builder.create_block()
    let continue_block = self.builder.create_block()

    // Branch: if is_null goto trap_block else continue_block
    self.builder.brnz(is_null, trap_block, continue_block)

    // Trap block: emit trap for null reference
    self.builder.switch_to_block(trap_block)
    self.builder.trap("null function reference")

    // Continue block: proceed with call
    self.builder.switch_to_block(continue_block)

    // Pop arguments
    let args : Array[Value] = []
    for _ in 0..<func_type.params.length() {
      args.push(self.pop())
    }
    args.rev_in_place()

    // Get result types
    let result_types : Array[Type] = func_type.results.map(Type::from_wasm)

    // Emit call_ref instruction
    let results = self.builder.call_ref_multi(
      type_idx, result_types, func_ref, args,
    )

    // Push all results onto the stack
    for v in results {
      self.push(v)
    }
  }
}

///|
/// Translate a tail call
fn Translator::translate_return_call(self : Translator, func_idx : Int) -> Unit {
  // Get function type
  let type_idx = if func_idx < self.num_imports {
    // Look up import function type
    if func_idx < self.import_func_type_indices.length() {
      self.import_func_type_indices[func_idx]
    } else {
      0 // Fallback
    }
  } else {
    let local_idx = func_idx - self.num_imports
    if local_idx < self.func_type_indices.length() {
      self.func_type_indices[local_idx]
    } else {
      0
    }
  }
  if type_idx < self.func_types.length() {
    let func_type = self.func_types[type_idx]
    // Pop arguments
    let args : Array[Value] = []
    for _ in 0..<func_type.params.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Remap function index for cross-module calls
    let global_func_idx = self.remap_func_idx(func_idx)
    // Emit return_call instruction (tail call - does not return to caller)
    // Note: emit a single ReturnCall IR instruction, not call + return
    self.builder.return_call_multi(global_func_idx, args)
    // Mark as unreachable since this is a terminator (does not return to this function)
    self.is_unreachable = true
  }
}

///|
/// Translate a tail call indirect
fn Translator::translate_return_call_indirect(
  self : Translator,
  type_idx : Int,
  table_idx : Int,
) -> Unit {
  if type_idx < self.func_types.length() {
    let func_type = self.func_types[type_idx]
    // Use original type_idx - the JIT type check (is_subtype_cached) handles
    // canonical indices internally to support both subtyping and structural equivalence
    // Pop callee (element index within the table)
    let elem_idx = self.pop()

    // Pop arguments
    let args : Array[Value] = []
    for _ in 0..<func_type.params.length() {
      args.push(self.pop())
    }
    args.rev_in_place()

    // Emit return_call_indirect instruction (tail call - does not return to caller)
    // Note: emit a single ReturnCallIndirect IR instruction, not call + return
    self.builder.return_call_indirect_multi(type_idx, table_idx, elem_idx, args)
    // Mark as unreachable since this is a terminator (does not return to this function)
    self.is_unreachable = true
  }
}

///|
/// Translate a tail call through function reference
fn Translator::translate_return_call_ref(
  self : Translator,
  type_idx : Int,
) -> Unit {
  if type_idx < self.func_types.length() {
    let func_type = self.func_types[type_idx]
    // Pop the function reference
    let func_ref = self.pop()

    // Null check: JIT null reference is NULL_REF (0)
    let null_sentinel = self.builder.iconst(func_ref.ty, @types.NULL_REF)
    let is_null = self.builder.icmp_eq(func_ref, null_sentinel)

    // Create trap block and continuation block
    let trap_block = self.builder.create_block()
    let continue_block = self.builder.create_block()

    // Branch: if is_null goto trap_block else continue_block
    self.builder.brnz(is_null, trap_block, continue_block)

    // Trap block: emit trap for null reference
    self.builder.switch_to_block(trap_block)
    self.builder.trap("null function reference")

    // Continue block: proceed with call
    self.builder.switch_to_block(continue_block)

    // Pop arguments
    let args : Array[Value] = []
    for _ in 0..<func_type.params.length() {
      args.push(self.pop())
    }
    args.rev_in_place()

    // Emit return_call_ref instruction (tail call - does not return to caller)
    // Note: emit a single ReturnCallRef IR instruction, not call + return
    self.builder.return_call_ref_multi(type_idx, func_ref, args)
    // Mark as unreachable since this is a terminator (does not return to this function)
    self.is_unreachable = true
  }
}
