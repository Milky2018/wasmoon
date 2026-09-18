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
    validate_value_type(
      local_type,
      num_types,
      stack_switching=ctx.stack_switching,
    )
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
    bulk_memory: ctx.bulk_memory,
    stack_switching: ctx.stack_switching,
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
  let stack = OperandStack::new_with_subtyping(func_ctx.subtyping_ctx)

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
    validate_expr(ctx, stack, [instr]) catch {
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
    validate_value_type(
      local_type,
      num_types,
      stack_switching=ctx.stack_switching,
    )
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
    bulk_memory: ctx.bulk_memory,
    stack_switching: ctx.stack_switching,
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
  let stack = OperandStack::new_with_subtyping(func_ctx.subtyping_ctx)

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
  let tasks : Array[ValidationTask] = [Sequence(instrs[:], stack)]
  while tasks.pop() is Some(task) {
    match task {
      Sequence([], _) => ()
      Sequence([instr, .. rest], current) => {
        tasks.push(Sequence(rest, current))
        let (bt, body, alternative, kind, exit_name) = match instr {
          Block(bt, body) => (bt, body, None, BlockLabel, "block exit")
          Loop(bt, body) => (bt, body, None, LoopLabel, "loop exit")
          If(bt, body, other) => {
            current.pop(I32)
            (bt, body, Some(other), BlockLabel, "if-then exit")
          }
          TryTable(bt, _, body) =>
            (bt, body, None, BlockLabel, "try_table exit")
          _ => {
            validate_leaf_instr(ctx, current, instr)
            continue
          }
        }
        let results = get_block_results(ctx, bt)
        let params = get_block_params(ctx, bt)
        for i = params.length() - 1; i >= 0; i = i - 1 {
          current.pop(params[i])
        }
        // Catch targets refer to the enclosing labels, before entering the try.
        if instr is TryTable(_, handlers, _) {
          validate_catch_handlers(ctx, handlers)
        }
        let saved_init = ctx.local_init.copy()
        ctx.labels.push({ kind, block_type: bt, })
        tasks.push(ExitControl(current, results))
        if alternative is Some(other) {
          let other_stack = OperandStack::new_with_subtyping(ctx.subtyping_ctx)
          for param in params {
            other_stack.push(param)
          }
          tasks.push(
            FinishBranch(other_stack, results, saved_init, "if-else exit"),
          )
          tasks.push(Sequence(other[:], other_stack))
        }
        let inner = OperandStack::new_with_subtyping(ctx.subtyping_ctx)
        for param in params {
          inner.push(param)
        }
        tasks.push(FinishBranch(inner, results, saved_init, exit_name))
        tasks.push(Sequence(body[:], inner))
      }
      FinishBranch(inner, results, saved_init, exit_name) => {
        inner.check_height(results.length(), exit_name)
        for i = results.length() - 1; i >= 0; i = i - 1 {
          inner.pop(results[i])
        }
        // Each branch starts with the enclosing definite-initialization state.
        for i in 0..<saved_init.length() {
          ctx.local_init[i] = saved_init[i]
        }
      }
      ExitControl(outer, results) => {
        ctx.labels.pop() |> ignore
        for result in results {
          outer.push(result)
        }
      }
    }
  }
}

///|
priv enum ValidationTask {
  Sequence(ArrayView[@types.Instruction], OperandStack)
  FinishBranch(OperandStack, Array[@types.ValueType], Array[Bool], String)
  ExitControl(OperandStack, Array[@types.ValueType])
}

///|
fn validate_catch_handlers(
  ctx : ValidationContext,
  handlers : Array[@types.CatchHandler],
) -> Unit raise ValidationError {
  for handler in handlers {
    match handler {
      Catch(tag_idx, label_idx) => {
        // Validate tag index
        if tag_idx < 0 || tag_idx >= ctx.tags.length() {
          raise UnknownTag(tag_idx)
        }
        // Validate label index (labels are indexed from innermost)
        if label_idx > ctx.labels.length() {
          raise InvalidLabelIndex(label_idx)
        }
        // Get expected types at label
        let expected_types = if label_idx == ctx.labels.length() {
          ctx.returns
        } else {
          let target_label = ctx.labels[ctx.labels.length() - 1 - label_idx]
          get_label_types(ctx, target_label)
        }
        // Catch provides tag params
        let tag_type = ctx.exception_tag_type(tag_idx)
        if tag_type.params.length() != expected_types.length() {
          raise TypeMismatch(
            "catch handler arity mismatch: tag has \{tag_type.params.length()} params, label expects \{expected_types.length()}",
          )
        }
        // Check that each tag param is a subtype of the expected label type
        for i, param_type in tag_type.params {
          if !ctx.subtyping_ctx.value_type_subtype(
              param_type,
              expected_types[i],
            ) {
            raise TypeMismatch(
              "catch handler type mismatch: tag param \{i} has type \{param_type}, label expects \{expected_types[i]}",
            )
          }
        }
      }
      CatchRef(tag_idx, label_idx) => {
        // Validate tag index
        if tag_idx < 0 || tag_idx >= ctx.tags.length() {
          raise UnknownTag(tag_idx)
        }
        // Validate label index
        if label_idx > ctx.labels.length() {
          raise InvalidLabelIndex(label_idx)
        }
        // Get expected types at label
        let expected_types = if label_idx == ctx.labels.length() {
          ctx.returns
        } else {
          let target_label = ctx.labels[ctx.labels.length() - 1 - label_idx]
          get_label_types(ctx, target_label)
        }
        // CatchRef provides tag params + exnref
        let tag_type = ctx.exception_tag_type(tag_idx)
        let expected_arity = tag_type.params.length() + 1
        if expected_arity != expected_types.length() {
          raise TypeMismatch(
            "catch_ref handler arity mismatch: tag has \{tag_type.params.length()} params + exnref, label expects \{expected_types.length()}",
          )
        }
        // Check that each tag param is a subtype of the expected label type
        for i, param_type in tag_type.params {
          if !ctx.subtyping_ctx.value_type_subtype(
              param_type,
              expected_types[i],
            ) {
            raise TypeMismatch(
              "catch_ref handler type mismatch: tag param \{i} has type \{param_type}, label expects \{expected_types[i]}",
            )
          }
        }
        // The last expected type should be ExnRef (exnref is always a subtype of itself)
      }
      CatchAll(label_idx) => {
        // Validate label index
        if label_idx > ctx.labels.length() {
          raise InvalidLabelIndex(label_idx)
        }
        // CatchAll provides no values
        let expected_types = if label_idx == ctx.labels.length() {
          ctx.returns
        } else {
          let target_label = ctx.labels[ctx.labels.length() - 1 - label_idx]
          get_label_types(ctx, target_label)
        }
        if expected_types.length() != 0 {
          raise TypeMismatch(
            "catch_all handler arity mismatch: provides 0 values, label expects \{expected_types.length()}",
          )
        }
      }
      CatchAllRef(label_idx) => {
        // Validate label index
        if label_idx > ctx.labels.length() {
          raise InvalidLabelIndex(label_idx)
        }
        // CatchAllRef provides exnref only
        let expected_types = if label_idx == ctx.labels.length() {
          ctx.returns
        } else {
          let target_label = ctx.labels[ctx.labels.length() - 1 - label_idx]
          get_label_types(ctx, target_label)
        }
        if expected_types.length() != 1 {
          raise TypeMismatch(
            "catch_all_ref handler arity mismatch: provides 1 value (exnref), label expects \{expected_types.length()}",
          )
        }
      }
    }
  }
}
