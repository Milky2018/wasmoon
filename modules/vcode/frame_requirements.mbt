///|
/// The ABI quantities contributed by one selected instruction.
pub(all) enum FrameUse {
  Call(Int32, Int32)
  Incoming(Int32)
  Tail(Int32)
  LocalObject(Int32, Int32, Int32)
}

///|
pub(all) struct StackObjectRequirements {
  size : Int32
  alignment : Int32
  offsets : Array[Int32]
}

///|
pub(all) struct FrameRequirements {
  outgoing_args_size : Int32
  incoming_args_size : Int32
  tail_args_size : Int32
  result_area_size : Int32
  has_calls : Bool
  stack_objects : StackObjectRequirements?
}

///|
fn align_frame_area(size : Int32, alignment : Int32) -> Int32 {
  (size + alignment - 1) / alignment * alignment
}

///|
/// Recompute the requirements from current VCode for planning and verification.
pub fn[Inst] collect_frame_requirements(
  function : Function[Inst],
  frame_use : (Inst) -> FrameUse?,
) -> Result[FrameRequirements, String] {
  let mut outgoing = 0
  let mut incoming = 0
  let mut tail = 0
  let mut results = 0
  let mut has_calls = false
  let objects : Array[(Int32, Int32)?] = []
  for index in 0..<function.instruction_count() {
    let inst = function
      .instruction(function.instruction_at(index).unwrap())
      .unwrap()
    match frame_use(inst) {
      Some(Call(stack, result)) => {
        has_calls = true
        outgoing = outgoing.max(stack)
        results = results.max(result)
      }
      Some(Incoming(end)) => incoming = incoming.max(end)
      Some(Tail(stack)) => tail = tail.max(stack)
      Some(LocalObject(id, size, alignment)) => {
        if id < 0 ||
          size <= 0 ||
          alignment <= 0 ||
          (alignment & (alignment - 1)) != 0 {
          return Err("invalid stack-object descriptor in target VCode")
        }
        while objects.length() <= id {
          objects.push(None)
        }
        match objects[id] {
          Some(existing) if existing != (size, alignment) =>
            return Err("stack-object id has conflicting size or alignment")
          None => objects[id] = Some((size, alignment))
          _ => ()
        }
      }
      None => ()
    }
  }
  let offsets : Array[Int32] = []
  let mut size = 0
  let mut alignment = 1
  for object in objects {
    guard object is Some((object_size, object_alignment)) else {
      return Err("stack-object ids must be dense within one function")
    }
    let offset = align_frame_area(size, object_alignment)
    offsets.push(offset)
    size = offset + object_size
    alignment = alignment.max(object_alignment)
  }
  let incoming = align_frame_area(incoming, 16)
  Ok({
    outgoing_args_size: outgoing,
    incoming_args_size: incoming,
    tail_args_size: if function.protocol() == Internal {
      incoming.max(tail)
    } else {
      incoming
    },
    result_area_size: results,
    has_calls,
    stack_objects: if offsets.is_empty() {
      None
    } else {
      Some({ size: align_frame_area(size, alignment), alignment, offsets, })
    },
  })
}

///|
pub fn[Inst] used_callee_saved_registers(
  function : Function[Inst],
  allocation : Allocation,
  is_callee_saved : (PhysicalReg) -> Bool,
  link_register~ : PhysicalReg? = None,
) -> Array[PhysicalReg] {
  let regs : Array[PhysicalReg] = []
  fn record(regs : Array[PhysicalReg], reg : PhysicalReg) -> Unit {
    if is_callee_saved(reg) && !regs.contains(reg) {
      regs.push(reg)
    }
  }
  for index in 0..<function.value_count() {
    let location = allocation.allocated_value_location_at(index).unwrap()
    if location.is_register() {
      record(regs, location.register_unchecked())
    }
  }
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    for operand in 0..<function.instruction_operand_count(instruction) {
      let location = allocation
        .allocated_operand_location_at(index, operand)
        .unwrap()
      if location.is_register() {
        record(regs, location.register_unchecked())
      }
    }
  }
  for edit in allocation.edits() {
    match edit.kind() {
      Spill(reg~, ..) | Reload(reg~, ..) => record(regs, reg)
      Move(from~, to~, ..) => {
        record(regs, from)
        record(regs, to)
      }
      EdgeMove(from~, to~, ..) => {
        if from is Register(reg) {
          record(regs, reg)
        }
        if to is Register(reg) {
          record(regs, reg)
        }
      }
    }
  }
  if link_register is Some(reg) {
    regs.push(reg)
  }
  regs.sort_by(fn(left, right) {
    let class_order = match (left.class, right.class) {
      (Int, FpVector) => -1
      (FpVector, Int) => 1
      _ => 0
    }
    if class_order != 0 {
      class_order
    } else {
      left.id.compare(right.id)
    }
  })
  regs
}

///|
pub fn[Inst] requires_emergency_move_area(
  function : Function[Inst],
  allocation : Allocation,
  is_abi_materialization : (Inst) -> Bool,
  int_scratch : PhysicalReg,
  fp_scratch : PhysicalReg,
) -> Bool raise MoveResolveError {
  fn instruction_edits_require_emergency(
    instruction : Instruction,
    placement : PointPlacement,
  ) -> Bool raise MoveResolveError {
    !allocation.edits_at(instruction, placement).is_empty() &&
    plan_parallel_moves(
      allocation_edit_moves(function, allocation, instruction, placement),
      int_scratch,
      fp_scratch,
    ).requires_emergency
  }
  for block in function.layout() {
    for instruction in function.block_body(block) {
      if !is_abi_materialization(function.instruction(instruction).unwrap()) {
        if instruction_edits_require_emergency(instruction, Before) ||
          instruction_edits_require_emergency(instruction, After) {
          return true
        }
      }
    }
    let terminator = function.block_terminator(block).unwrap()
    if instruction_edits_require_emergency(terminator, Before) ||
      instruction_edits_require_emergency(terminator, After) {
      return true
    }
    for successor_index in 0..<function.instruction_successor_count(terminator) {
      if !allocation.edge_edits_at(block, successor_index).is_empty() &&
        plan_parallel_moves(
          allocation_edge_moves(function, allocation, block, successor_index),
          int_scratch,
          fp_scratch,
        ).requires_emergency {
        return true
      }
    }
  }
  false
}
