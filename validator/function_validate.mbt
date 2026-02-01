///|
/// Validate a function body with instruction offset tracking
fn validate_function_with_offset(
  ctx : ValidationContext,
  func_type : @types.FuncType,
  code : @types.FunctionCode,
  func_idx : Int,
) -> Unit raise ValidationError {
  let num_types = ctx.types.length()

  // Validate type indices in local types
  for local_type in code.locals {
    validate_value_type(local_type, num_types)
  }

  // Set up locals: params + declared locals
  let locals : Array[@types.ValueType] = []
  let local_init : Array[Bool] = []
  // Parameters are always initialized (provided by caller)
  for param in func_type.params {
    locals.push(param)
    local_init.push(true)
  }
  // Declared locals: initialized only if they have a default value (not non-nullable ref)
  for local_type in code.locals {
    locals.push(local_type)
    // Non-nullable reference types don't have a default value, so they start uninitialized
    local_init.push(!is_non_nullable_ref(local_type))
  }

  // Create validation context for this function
  let func_ctx : ValidationContext = {
    types: ctx.types,
    funcs: ctx.funcs,
    tables: ctx.tables,
    mems: ctx.mems,
    globals: ctx.globals,
    tags: ctx.tags,
    elems: ctx.elems,
    data_count: ctx.data_count,
    locals,
    labels: [],
    returns: func_type.results,
    local_init,
    declared_funcs: ctx.declared_funcs,
    subtyping_ctx: ctx.subtyping_ctx,
  }
  let stack = OperandStack::new()

  // Validate function body with offset tracking
  validate_expr_with_offset(func_ctx, stack, code.body, func_idx)

  // Check that final stack has exactly the return types
  let expected_height = func_type.results.length()
  stack.check_height(expected_height, "function return") catch {
    e =>
      raise WithContext(
        ValidationErrorContext::from_error(e).with_func_idx(func_idx),
      )
  }

  // Pop and verify return types
  let num_results = func_type.results.length()
  for offset in 0..<num_results {
    let i = num_results - 1 - offset
    stack.pop(func_type.results[i]) catch {
      e =>
        raise WithContext(
          ValidationErrorContext::from_error(e).with_func_idx(func_idx),
        )
    }
  }
}

///|
/// Validate an expression with instruction offset tracking
fn validate_expr_with_offset(
  ctx : ValidationContext,
  stack : OperandStack,
  instrs : Array[@types.Instruction],
  func_idx : Int,
) -> Unit raise ValidationError {
  for i, instr in instrs {
    validate_instr(ctx, stack, instr) catch {
      e =>
        raise WithContext(
          ValidationErrorContext::from_error(e)
          .with_func_idx(func_idx)
          .with_instr_offset(i)
          .with_instruction(instr.to_string()),
        )
    }
  }
}

///|
/// Validate a function body
fn validate_function(
  ctx : ValidationContext,
  func_type : @types.FuncType,
  code : @types.FunctionCode,
) -> Unit raise ValidationError {
  let num_types = ctx.types.length()

  // Validate type indices in local types
  for local_type in code.locals {
    validate_value_type(local_type, num_types)
  }

  // Set up locals: params + declared locals
  let locals : Array[@types.ValueType] = []
  let local_init : Array[Bool] = []
  // Parameters are always initialized (provided by caller)
  for param in func_type.params {
    locals.push(param)
    local_init.push(true)
  }
  // Declared locals: initialized only if they have a default value (not non-nullable ref)
  for local_type in code.locals {
    locals.push(local_type)
    // Non-nullable reference types don't have a default value, so they start uninitialized
    local_init.push(!is_non_nullable_ref(local_type))
  }

  // Create validation context for this function
  let func_ctx : ValidationContext = {
    types: ctx.types,
    funcs: ctx.funcs,
    tables: ctx.tables,
    mems: ctx.mems,
    globals: ctx.globals,
    tags: ctx.tags,
    elems: ctx.elems,
    data_count: ctx.data_count,
    locals,
    labels: [],
    returns: func_type.results,
    local_init,
    declared_funcs: ctx.declared_funcs,
    subtyping_ctx: ctx.subtyping_ctx,
  }
  let stack = OperandStack::new()

  // Validate function body
  validate_expr(func_ctx, stack, code.body)

  // Check that final stack has exactly the return types
  let expected_height = func_type.results.length()
  stack.check_height(expected_height, "function return")

  // Pop and verify return types
  let results_count = func_type.results.length()
  for offset in 0..<results_count {
    let i = results_count - 1 - offset
    stack.pop(func_type.results[i])
  }
}

///|
/// Validate an expression (sequence of instructions)
fn validate_expr(
  ctx : ValidationContext,
  stack : OperandStack,
  instrs : Array[@types.Instruction],
) -> Unit raise ValidationError {
  for instr in instrs {
    validate_instr(ctx, stack, instr)
  }
}
