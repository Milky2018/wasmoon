///|
fn validate_continuation_types(
  module_ : @types.Module,
  enabled : Bool,
) -> Unit raise ValidationError {
  fn check_type(ty : @types.ValueType) -> Unit raise ValidationError {
    validate_value_type(ty, module_.types.length(), stack_switching=enabled)
    match ty {
      RefContTyped(index) | RefNullContTyped(index) => {
        guard module_.types[index].composite is Cont(_) else {
          raise TypeMismatch("reference does not name a continuation type")
        }
      }
      _ => ()
    }
  }
  for subtype in module_.types {
    if subtype.composite is Cont(index) {
      if !enabled {
        raise TypeMismatch("stack switching is not enabled")
      }
      guard module_.func_type_at(index) is Some(_) else {
        raise TypeMismatch("continuation must name a function type")
      }
    }
    for ty in collect_value_types_from_subtype(subtype) {
      check_type(ty)
    }
  }
  for import_ in module_.imports {
    match import_.desc {
      Global(ty) => check_type(ty.value_type)
      Table(ty) => check_type(ty.elem_type)
      _ => ()
    }
  }
  for global in module_.globals {
    check_type(global.type_.value_type)
  }
  for table in module_.tables {
    check_type(table.type_.elem_type)
  }
  for elem in module_.elems {
    check_type(elem.type_)
  }
  for code in module_.codes {
    for local_type in code.locals {
      check_type(local_type)
    }
  }
}

///|
fn ValidationContext::continuation_function_index(
  self : ValidationContext,
  index : Int,
) -> Int raise ValidationError {
  if index < 0 || index >= self.types.length() {
    raise InvalidTypeIndex(index)
  }
  guard self.types[index].composite is Cont(function) else {
    raise TypeMismatch("expected a continuation type")
  }
  self.get_func_type(function) |> ignore
  function
}

///|
fn ValidationContext::continuation_function_type(
  self : ValidationContext,
  index : Int,
) -> @types.FuncType raise ValidationError {
  self.get_func_type(self.continuation_function_index(index))
}

///|
fn ValidationContext::control_tag_type(
  self : ValidationContext,
  index : Int,
) -> @types.FuncType raise ValidationError {
  if index < 0 || index >= self.tags.length() {
    raise UnknownTag(index)
  }
  self.tags[index]
}

///|
fn ValidationContext::exception_tag_type(
  self : ValidationContext,
  index : Int,
) -> @types.FuncType raise ValidationError {
  let signature = self.control_tag_type(index)
  if !signature.results.is_empty() {
    raise TypeMismatch("exception tags cannot return values")
  }
  signature
}

///|
fn ValidationContext::signature_subtype(
  self : ValidationContext,
  params1 : Array[@types.ValueType],
  results1 : Array[@types.ValueType],
  params2 : Array[@types.ValueType],
  results2 : Array[@types.ValueType],
) -> Bool {
  if params1.length() != params2.length() ||
    results1.length() != results2.length() {
    return false
  }
  for i, parameter in params1 {
    if !self.subtyping_ctx.value_type_subtype(params2[i], parameter) {
      return false
    }
  }
  for i, result in results1 {
    if !self.subtyping_ctx.value_type_subtype(result, results2[i]) {
      return false
    }
  }
  true
}

///|
fn ValidationContext::check_resume_handlers(
  self : ValidationContext,
  index : Int,
  handlers : Array[@types.ResumeHandler],
) -> @types.FuncType raise ValidationError {
  let resumed = self.continuation_function_type(index)
  for handler in handlers {
    match handler {
      OnLabel(tag_index, label) => {
        let tag = self.control_tag_type(tag_index)
        if label < 0 || label > self.labels.length() {
          raise InvalidLabelIndex(label)
        }
        let values = if label == self.labels.length() {
          self.returns
        } else {
          get_label_types(self, self.labels[self.labels.length() - 1 - label])
        }
        if values.length() != tag.params.length() + 1 {
          raise TypeMismatch(
            "resume handler label arity does not match its tag",
          )
        }
        for i, parameter in tag.params {
          if !self.subtyping_ctx.value_type_subtype(parameter, values[i]) {
            raise TypeMismatch(
              "resume handler label does not accept its tag parameters",
            )
          }
        }
        let continuation = match values[values.length() - 1] {
          RefContTyped(index) | RefNullContTyped(index) =>
            self.continuation_function_type(index)
          _ =>
            raise TypeMismatch(
              "resume handler label must end in a continuation reference",
            )
        }
        if !self.signature_subtype(
            tag.results,
            resumed.results,
            continuation.params,
            continuation.results,
          ) {
          raise TypeMismatch("resume handler continuation type mismatch")
        }
      }
      OnSwitch(tag_index) => {
        let tag = self.control_tag_type(tag_index)
        if !self.signature_subtype(tag.params, tag.results, [], resumed.results) ||
          !self.signature_subtype([], resumed.results, tag.params, tag.results) {
          raise TypeMismatch(
            "switch handler tag does not match continuation results",
          )
        }
      }
    }
  }
  resumed
}

///|
fn pop_continuation_arguments(
  stack : OperandStack,
  types : Array[@types.ValueType],
) -> Unit raise ValidationError {
  for i = types.length() - 1; i >= 0; i = i - 1 {
    stack.pop(types[i])
  }
}

///|
fn push_continuation_results(
  stack : OperandStack,
  types : Array[@types.ValueType],
) -> Unit {
  for ty in types {
    stack.push(ty)
  }
}

///|
fn validate_continuation_instruction(
  ctx : ValidationContext,
  stack : OperandStack,
  instruction : @types.Instruction,
) -> Bool raise ValidationError {
  match instruction {
    ContNew(_)
    | ContBind(_, _)
    | Suspend(_)
    | Resume(_, _)
    | ResumeThrow(_, _, _)
    | ResumeThrowRef(_, _)
    | Switch(_, _) =>
      if !ctx.stack_switching {
        raise TypeMismatch("stack switching is not enabled")
      }
    _ => return false
  }
  match instruction {
    ContNew(index) => {
      let function = ctx.continuation_function_index(index)
      stack.pop(RefNullFuncTyped(function))
      stack.push(RefContTyped(index))
    }
    ContBind(input, output) => {
      let before = ctx.continuation_function_type(input)
      let after = ctx.continuation_function_type(output)
      let count = before.params.length() - after.params.length()
      if count < 0 {
        raise TypeMismatch("continuation binding increases parameter count")
      }
      let remaining : Array[@types.ValueType] = []
      for i in count..<before.params.length() {
        remaining.push(before.params[i])
      }
      if !ctx.signature_subtype(
          remaining,
          before.results,
          after.params,
          after.results,
        ) {
        raise TypeMismatch("continuation binding type mismatch")
      }
      stack.pop(RefNullContTyped(input))
      for i = count - 1; i >= 0; i = i - 1 {
        stack.pop(before.params[i])
      }
      stack.push(RefContTyped(output))
    }
    Suspend(index) => {
      let tag = ctx.control_tag_type(index)
      pop_continuation_arguments(stack, tag.params)
      push_continuation_results(stack, tag.results)
    }
    Resume(index, handlers) => {
      let function = ctx.check_resume_handlers(index, handlers)
      stack.pop(RefNullContTyped(index))
      pop_continuation_arguments(stack, function.params)
      push_continuation_results(stack, function.results)
    }
    ResumeThrow(index, tag, handlers) => {
      let function = ctx.check_resume_handlers(index, handlers)
      let exception = ctx.exception_tag_type(tag)
      stack.pop(RefNullContTyped(index))
      pop_continuation_arguments(stack, exception.params)
      push_continuation_results(stack, function.results)
    }
    ResumeThrowRef(index, handlers) => {
      let function = ctx.check_resume_handlers(index, handlers)
      stack.pop(RefNullContTyped(index))
      stack.pop(ExnRef)
      push_continuation_results(stack, function.results)
    }
    Switch(index, tag_index) => {
      let function = ctx.continuation_function_type(index)
      let tag = ctx.control_tag_type(tag_index)
      if !tag.params.is_empty() || function.params.is_empty() {
        raise TypeMismatch(
          "switch requires a result-only tag and a continuation parameter",
        )
      }
      let other = match function.params[function.params.length() - 1] {
        RefContTyped(index) | RefNullContTyped(index) =>
          ctx.continuation_function_type(index)
        _ =>
          raise TypeMismatch(
            "switch continuation must end in a continuation parameter",
          )
      }
      if !ctx.signature_subtype(
          tag.results,
          tag.results,
          function.results,
          other.results,
        ) {
        raise TypeMismatch("switch continuation result mismatch")
      }
      stack.pop(RefNullContTyped(index))
      for i = function.params.length() - 2; i >= 0; i = i - 1 {
        stack.pop(function.params[i])
      }
      push_continuation_results(stack, other.params)
    }
    _ => ()
  }
  true
}
