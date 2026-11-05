///|
/// Validate a function body
fn validate_function(
  ctx : ValidationContext,
  func_type : @types.FuncType,
  code : @types.FunctionCode,
  func_idx? : Int32,
) -> Unit raise ValidationError {

  // Validate type indices in local types
  for local_type in code.locals {
    validate_value_type(
      local_type,
      ctx.types,
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
    ..ctx,
    locals,
    labels: [],
    returns: func_type.results,
    local_init,
  }
  let stack = OperandStack::new_with_subtyping(func_ctx.subtyping_ctx)

  validate_expr(func_ctx, stack, code.body, func_idx?)
  try {
    // Check that final stack has exactly the return types
    let expected_height = func_type.results.length()
    stack.check_height(expected_height, "function return")

    // Pop and verify return types
    let results_count = func_type.results.length()
    for offset in 0..<results_count {
      let i = results_count - 1 - offset
      stack.pop(func_type.results[i])
    }
  } catch {
    error =>
      match func_idx {
        Some(index) =>
          raise WithContext(
            ValidationErrorContext::from_error(error).with_func_idx(index),
          )
        None => raise error
      }
  }
}

///|
/// Use the same worklist for raw and contextual validation. A contextual
/// error identifies the enclosing top-level instruction.
fn validate_expr(
  ctx : ValidationContext,
  stack : OperandStack,
  instrs : ArrayView[@types.Instruction],
  func_idx? : Int32,
) -> Unit raise ValidationError {
  let tasks : Array[ValidationTask] = [Sequence(instrs, stack)]
  let mut instr_offset = 0
  try {
    while tasks.pop() is Some(task) {
      match task {
        Sequence(sequence, current) => {
          let record_offset = func_idx is Some(_) &&
            physical_equal(current, stack)
          let sequence_offset = instrs.length() - sequence.length()
          for index, instr in sequence {
            if record_offset {
              instr_offset = sequence_offset + index
            }
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
            if index + 1 < sequence.length() {
              tasks.push(Sequence(sequence[index + 1:], current))
            }
            tasks.push(ExitControl(current, results))
            if alternative is Some(other) {
              let other_stack = OperandStack::new_with_subtyping(
                ctx.subtyping_ctx,
              )
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
            break
          }
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
  } catch {
    error =>
      if func_idx is Some(index) {
        raise WithContext(
          ValidationErrorContext::from_error(error)
          .with_func_idx(index)
          .with_instr_offset(instr_offset)
          .with_instruction(instrs[instr_offset].to_string()),
        )
      } else {
        raise error
      }
  }
}

///|
priv enum ValidationTask {
  Sequence(ArrayView[@types.Instruction], OperandStack)
  FinishBranch(
    OperandStack,
    ReadOnlyArray[@types.ValueType],
    Array[Bool],
    String
  )
  ExitControl(OperandStack, ReadOnlyArray[@types.ValueType])
}

///|
fn validate_catch_handlers(
  ctx : ValidationContext,
  handlers : ArrayView[@types.CatchHandler],
) -> Unit raise ValidationError {
  for handler in handlers {
    let (tag, label, carries_ref, name) = match handler {
      Catch(tag, label) => (Some(tag), label, false, "catch")
      CatchRef(tag, label) => (Some(tag), label, true, "catch_ref")
      CatchAll(label) => (None, label, false, "catch_all")
      CatchAllRef(label) => (None, label, true, "catch_all_ref")
    }
    if tag is Some(index) && (index < 0 || index >= ctx.tags.length()) {
      raise UnknownTag(index)
    }
    if label < 0 || label > ctx.labels.length() {
      raise InvalidLabelIndex(label)
    }
    let expected = if label == ctx.labels.length() {
      ctx.returns
    } else {
      ReadOnlyArray::from_array(
        get_label_types(ctx, ctx.labels[ctx.labels.length() - 1 - label]),
      )
    }
    let params = match tag {
      Some(index) => ctx.exception_tag_type(index).params
      None => []
    }
    let arity = params.length() + (if carries_ref { 1 } else { 0 })
    if arity != expected.length() {
      let supplied = match handler {
        Catch(_, _) => "tag has \{params.length()} params"
        CatchRef(_, _) => "tag has \{params.length()} params + exnref"
        CatchAll(_) => "provides 0 values"
        CatchAllRef(_) => "provides 1 value (exnref)"
      }
      raise TypeMismatch(
        "\{name} handler arity mismatch: \{supplied}, label expects \{expected.length()}",
      )
    }
    for i, param in params {
      if !ctx.subtyping_ctx.value_type_subtype(param, expected[i]) {
        raise TypeMismatch(
          "\{name} handler type mismatch: tag param \{i} has type \{param}, label expects \{expected[i]}",
        )
      }
    }
    if carries_ref &&
      !ctx.subtyping_ctx.value_type_subtype(ExnRef, expected[params.length()]) {
      raise TypeMismatch(
        "\{name} handler type mismatch: exception reference cannot enter label type \{expected[params.length()]}",
      )
    }
  }
}
