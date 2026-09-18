///|
fn Translator::continuation_signature(
  self : Translator,
  index : Int,
) -> @types.FuncType {
  guard self.module_types[index].composite is Cont(function_index) else {
    abort("validated continuation type expected")
  }
  self.func_types[function_index]
}

///|
fn Translator::pop_continuation_arguments(
  self : Translator,
  count : Int,
) -> Array[Value] {
  let arguments : Array[Value] = []
  for _ in 0..<count {
    arguments.push(self.pop())
  }
  arguments.rev_in_place()
  arguments
}

///|
fn Translator::translate_cont_new(self : Translator, index : Int) -> Unit {
  let function = self.pop()
  self.push(
    @wasm_milkir.continuation_operation(self.builder, ContNew(index), [Ref], [
      function,
    ])[0],
  )
}

///|
fn Translator::translate_cont_bind(
  self : Translator,
  input : Int,
  output : Int,
) -> Unit {
  let reference = self.pop()
  let count = self.continuation_signature(input).params.length() -
    self.continuation_signature(output).params.length()
  let operands = [reference]
  operands.append(self.pop_continuation_arguments(count))
  self.push(
    @wasm_milkir.continuation_operation(
      self.builder,
      ContBind(input, output),
      [Ref],
      operands,
    )[0],
  )
}

///|
fn Translator::translate_cont_suspend(self : Translator, tag : Int) -> Unit {
  let signature = self.func_types[self.tags[tag].type_idx]
  let arguments = self.pop_continuation_arguments(signature.params.length())
  self.spill_locals_if_in_try()
  for
    value in @wasm_milkir.continuation_operation(
      self.builder,
      ContSuspend(tag),
      signature.results.map(type_from_wasm),
      arguments,
    ) {
    self.push(value)
  }
}

///|
fn continuation_payload_words(types : Array[Type]) -> Int {
  let mut words = 0
  for ty in types {
    words += if ty == V128 { 2 } else { 1 }
  }
  words
}

///|
/// Resume produces a status plus disjoint result regions. Only the selected
/// handler edge consumes its region; the normal edge consumes function results.
fn Translator::translate_cont_resume(
  self : Translator,
  index : Int,
  exception_tag : Int,
  handlers : Array[@types.ResumeHandler],
) -> Unit {
  let reference = self.pop()
  let signature = self.continuation_signature(index)
  let input_types : Array[@types.ValueType] = if exception_tag == -2 {
    signature.params
  } else if exception_tag == -1 {
    [ExnRef]
  } else {
    self.get_tag_param_types(exception_tag)
  }
  let operands = [reference]
  operands.append(self.pop_continuation_arguments(input_types.length()))
  let normal_types = signature.results.map(type_from_wasm)
  let result_types : Array[Type] = [I32]
  result_types.append(normal_types)
  let regions : Array[(Int, Int)] = []
  for handler in handlers {
    match handler {
      OnLabel(tag, depth) => {
        let types = self.get_tag_param_types(tag).map(type_from_wasm)
        types.push(Ref)
        let word_offset = continuation_payload_words(
          result_types[1:].to_owned(),
        )
        regions.push((result_types.length(), types.length()))
        operands.push(self.builder.iconst_i32(tag))
        operands.push(self.builder.iconst_i32(0))
        operands.push(self.builder.iconst_i32(word_offset))
        result_types.append(types)
        depth |> ignore
      }
      OnSwitch(tag) => {
        regions.push((0, 0))
        operands.push(self.builder.iconst_i32(tag))
        operands.push(self.builder.iconst_i32(1))
        operands.push(self.builder.iconst_i32(0))
      }
    }
  }
  self.spill_locals_if_in_try()
  let results = @wasm_milkir.continuation_operation(
    self.builder,
    ContResume(index, input_types.length(), handlers.length(), exception_tag),
    result_types,
    operands,
  )
  for handler_index, handler in handlers {
    if handler is OnLabel(_, depth) {
      let target_index = self.block_stack.length() - 1 - depth
      let region = regions[handler_index]
      let arguments : Array[Value] = []
      for i in 0..<region.1 {
        arguments.push(results[region.0 + i])
      }
      let fallthrough = self.builder.create_block()
      let condition = self.builder.icmp(
        Eq,
        results[0],
        self.builder.iconst_i32(handler_index),
      )
      if target_index >= 0 {
        let frame = self.block_stack[target_index]
        self.push_local_args(arguments, frame.local_params)
        self.mark_block_frame_reachable(target_index)
        self.branch_with_unwind(
          condition,
          frame.block,
          arguments,
          fallthrough,
          frame.handler_depth,
        )
      } else {
        let target = self.get_or_create_return_continuation()
        self.branch_with_unwind(condition, target, arguments, fallthrough, 0)
      }
      self.builder.switch_to_block(fallthrough)
    }
  }
  for i in 0..<normal_types.length() {
    self.push(results[i + 1])
  }
}

///|
fn Translator::translate_cont_switch(
  self : Translator,
  index : Int,
  tag : Int,
) -> Unit {
  let reference = self.pop()
  let signature = self.continuation_signature(index)
  let last = signature.params[signature.params.length() - 1]
  let other_index = match last {
    RefContTyped(index) | RefNullContTyped(index) => index
    _ => abort("validated switch continuation expected")
  }
  let operands = [reference]
  operands.append(
    self.pop_continuation_arguments(signature.params.length() - 1),
  )
  self.spill_locals_if_in_try()
  for
    value in @wasm_milkir.continuation_operation(
      self.builder,
      ContSwitch(index, tag),
      self.continuation_signature(other_index).params.map(type_from_wasm),
      operands,
    ) {
    self.push(value)
  }
}
