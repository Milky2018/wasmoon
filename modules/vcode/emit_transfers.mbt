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
