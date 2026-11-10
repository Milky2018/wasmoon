///|
/// Receive one contiguous group of ABI inputs. Register transfers must finish
/// before stack loads can reuse the target's scratch registers. The target
/// describes each pseudo as (type, incoming location, value-home operand).
pub fn[Inst, Buffer, Frame, E : Error] emit_incoming_values(
  function : Function[Inst],
  allocation : Allocation,
  body : ArrayView[Instruction],
  current_index : Int32,
  describe : (Inst) -> (ValueType, CallArgumentLocation, Int32)?,
  buffer : Buffer,
  frame : Frame,
  stack_base : Int32?,
  slot_offset : (Frame, StackSlot) -> Int32?,
  stack_scratch : (ValueType) -> PhysicalReg,
  int_scratch : PhysicalReg,
  fp_scratch : PhysicalReg,
  emit_moves : (Buffer, Frame, ResolvedMovePlan) -> Unit raise E,
  access_stack : (Buffer, Bool, ValueType, PhysicalReg, Int32) -> Unit raise E,
  invalid_moves : (MoveResolveError) -> E,
  missing_stack_area : E,
) -> Unit raise E {
  if current_index > 0 &&
    describe(function.instruction(body[current_index - 1]).unwrap()) is Some(_) {
    return
  }
  let register_moves : Array[ParallelMove] = []
  let stack_values : Array[(ValueType, Location, Int32)] = []
  for index in current_index..<body.length() {
    let instruction = body[index]
    guard describe(function.instruction(instruction).unwrap())
      is Some((ty, source, operand_index)) else {
      break
    }
    let value = function
      .instruction_operand_at(instruction, operand_index)
      .unwrap().value
    let home = allocation.value_location(value).unwrap()
    match source {
      CallRegister(reg) =>
        register_moves.push(ParallelMove::new(ty, Register(reg), home))
      CallStack(offset) => stack_values.push((ty, home, offset))
    }
  }
  let resolved = plan_parallel_moves(register_moves, int_scratch, fp_scratch) catch {
    error => raise invalid_moves(error)
  }
  emit_moves(buffer, frame, resolved)
  guard stack_base is Some(base) else {
    if !stack_values.is_empty() {
      raise missing_stack_area
    }
    return
  }
  for (ty, home, offset) in stack_values {
    match home {
      Register(destination) =>
        access_stack(buffer, true, ty, destination, base + offset)
      Stack(slot) => {
        let scratch = stack_scratch(ty)
        access_stack(buffer, true, ty, scratch, base + offset)
        access_stack(
          buffer,
          false,
          ty,
          scratch,
          slot_offset(frame, slot).unwrap(),
        )
      }
    }
  }
}

///|
/// Apply resolved physical moves using the target's register and frame
/// instructions. Parallel moves reach this stage in dependency order.
pub fn[Buffer, Frame, E : Error] emit_resolved_moves(
  plan : ResolvedMovePlan,
  buffer : Buffer,
  frame : Frame,
  slot_offset : (Frame, StackSlot) -> Int32?,
  emergency_offset : (Frame) -> Int32?,
  move_register : (Buffer, ValueType, PhysicalReg, PhysicalReg) -> Unit,
  access_stack : (Buffer, Bool, ValueType, PhysicalReg, Int32) -> Unit raise E,
  unresolved_stack_move : E,
  missing_emergency_area : E,
) -> Unit raise E {
  for step in plan.steps {
    match step {
      Transfer(transfer) =>
        match (transfer.from, transfer.to) {
          (Register(from), Register(to)) =>
            move_register(buffer, transfer.ty, to, from)
          (Stack(slot), Register(to)) =>
            access_stack(
              buffer,
              true,
              transfer.ty,
              to,
              slot_offset(frame, slot).unwrap(),
            )
          (Register(from), Stack(slot)) =>
            access_stack(
              buffer,
              false,
              transfer.ty,
              from,
              slot_offset(frame, slot).unwrap(),
            )
          (Stack(_), Stack(_)) => raise unresolved_stack_move
        }
      SpillScratchToEmergency(ty~, scratch~)
      | ReloadScratchFromEmergency(ty~, scratch~) => {
        guard emergency_offset(frame) is Some(offset) else {
          raise missing_emergency_area
        }
        access_stack(
          buffer,
          step is ReloadScratchFromEmergency(..),
          ty,
          scratch,
          offset,
        )
      }
    }
  }
}

///|
/// Copy stack arguments before register moves can overwrite their sources.
pub fn[Buffer, Frame, E : Error] emit_call_stack_transfers(
  plan : ResolvedCallTransferPlan,
  buffer : Buffer,
  frame : Frame,
  slot_offset : (Frame, StackSlot) -> Int32?,
  access_stack : (Buffer, Bool, ValueType, PhysicalReg, Int32) -> Unit raise E,
) -> Unit raise E {
  for transfer in plan.stack_transfers {
    let source = match transfer.source {
      Register(reg) => reg
      Stack(slot) => {
        let scratch = transfer.scratch.unwrap()
        access_stack(
          buffer,
          true,
          transfer.ty,
          scratch,
          slot_offset(frame, slot).unwrap(),
        )
        scratch
      }
    }
    // Integer call slots are eight bytes. Write the full slot so its upper
    // half is canonical for callees that consume the native-width value.
    let stack_type : ValueType = if transfer.ty is I32 {
      I64
    } else {
      transfer.ty
    }
    access_stack(buffer, false, stack_type, source, transfer.offset)
  }
}
