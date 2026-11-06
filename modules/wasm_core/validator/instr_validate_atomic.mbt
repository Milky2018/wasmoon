///|
fn validate_atomic(
  ctx : ValidationContext,
  stack : OperandStack,
  subopcode : Int32,
  memory_index : Int32,
  alignment : Int32,
  offset : Int64,
) -> Unit raise ValidationError {
  let memory = if subopcode == 3 {
    None
  } else {
    let memory = ctx.memory_type(memory_index)
    validate_mem_offset(memory, offset)
    Some(memory)
  }
  guard @types.atomic_opcode(subopcode) is Some(info) else {
    raise TypeMismatch("unsupported atomic subopcode \{subopcode}")
  }
  if info.operation is Fence {
    return
  }
  let addr_type = memory.unwrap().addr_type()
  if alignment != info.natural_alignment {
    raise InvalidAlignment(
      "\{info.validation_name()} alignment \{alignment} must equal natural alignment \{info.natural_alignment}",
    )
  }
  match info.operation {
    Notify => {
      stack.pop(I32)
      stack.pop(addr_type)
      stack.push(I32)
    }
    Wait => {
      stack.pop(I64)
      stack.pop(info.value_type)
      stack.pop(addr_type)
      stack.push(I32)
    }
    Load => {
      stack.pop(addr_type)
      stack.push(info.value_type)
    }
    Store => {
      stack.pop(info.value_type)
      stack.pop(addr_type)
    }
    Rmw(_) | CompareExchange => {
      stack.pop(info.value_type)
      if info.operation is CompareExchange {
        stack.pop(info.value_type)
      }
      stack.pop(addr_type)
      stack.push(info.value_type)
    }
    Fence => ()
  }
}
