///|
priv enum CallTransferDestination {
  TransferRegister(PhysicalReg)
  TransferOutgoingStack(Int)
}

///|
/// One allocated source and its physical destination in a target call layout.
pub struct CallTransfer {
  priv ty : ValueType
  priv source : Location
  priv destination : CallTransferDestination
}

///|
pub fn CallTransfer::to_register(
  ty : ValueType,
  source : Location,
  destination : PhysicalReg,
) -> CallTransfer {
  { ty, source, destination: TransferRegister(destination), }
}

///|
pub fn CallTransfer::to_stack(
  ty : ValueType,
  source : Location,
  offset : Int,
) -> CallTransfer {
  { ty, source, destination: TransferOutgoingStack(offset), }
}

///|
pub struct StackArgumentTransfer {
  ty : ValueType
  source : Location
  offset : Int
  scratch : PhysicalReg?
} derive(Eq, Debug)

///|
pub struct CallTransferPlan {
  stack_transfers : Array[StackArgumentTransfer]
  register_moves : Array[ParallelMove]
} derive(Eq, Debug)

///|
pub struct ResolvedCallTransferPlan {
  stack_transfers : Array[StackArgumentTransfer]
  register_moves : ResolvedMovePlan
} derive(Eq, Debug)

///|
pub suberror CallTransferError {
  InvalidSourceClass(index~ : Int)
  ForeignSourceStack(index~ : Int)
  InvalidSourceStackType(
    index~ : Int,
    expected~ : ValueType,
    actual~ : ValueType
  )
  InvalidSourceStackLayout(index~ : Int)
  InvalidDestinationClass(index~ : Int)
  InvalidStackOffset(index~ : Int, offset~ : Int)
  InvalidOutgoingStackRange(start~ : Int, size~ : Int)
  OutgoingStackDestinationOutOfRange(index~ : Int, offset~ : Int)
  DuplicateRegisterDestination(index~ : Int, register~ : PhysicalReg)
  OverlappingStackDestination(first~ : Int, second~ : Int)
  ProtectedLocationOverwrite(index~ : Int, location~ : Location)
  MoveResolutionFailed(cause~ : MoveResolveError)
} derive(Eq, Debug)

///|
fn transfer_size(ty : ValueType) -> Int {
  match ty {
    I32 | F32 => 4
    I64 | F64 | Ptr64 | GcRef64 => 8
    V128 => 16
  }
}

///|
fn ranges_overlap(
  left : Int,
  left_size : Int,
  right : Int,
  right_size : Int,
) -> Bool {
  left < right + right_size && right < left + left_size
}

///|
fn stack_transfer_scratch(
  ty : ValueType,
  scratch_int : Array[PhysicalReg],
  scratch_fp : Array[PhysicalReg],
  reserved : Array[Location],
) -> PhysicalReg raise CallTransferError {
  let candidates = if reg_class_for_value_type(ty) == Int {
    scratch_int
  } else {
    scratch_fp
  }
  let expected = reg_class_for_value_type(ty)
  for scratch in candidates {
    if scratch.class != expected {
      raise MoveResolutionFailed(cause=InvalidScratch(reg=scratch, expected~))
    }
    if !reserved.contains(Register(scratch)) {
      return scratch
    }
  }
  raise MoveResolutionFailed(
    cause=MissingScratch(class=reg_class_for_value_type(ty)),
  )
}

///|
/// Build one atomic call setup from allocated sources.
///
/// Outgoing stack arguments are captured before any ABI register destination is
/// overwritten. Register destinations are then resolved as one parallel move.
fn prepare_call_transfers(
  allocation : Allocation,
  transfers : Array[CallTransfer],
  outgoing_stack_start : Int,
  outgoing_stack_size : Int,
  scratch_int : Array[PhysicalReg],
  scratch_fp : Array[PhysicalReg],
  protected_locations : Array[Location],
) -> CallTransferPlan raise CallTransferError {
  if outgoing_stack_start < 0 || outgoing_stack_size < 0 {
    raise InvalidOutgoingStackRange(
      start=outgoing_stack_start,
      size=outgoing_stack_size,
    )
  }
  let outgoing_stack_end = outgoing_stack_start + outgoing_stack_size
  if outgoing_stack_end < outgoing_stack_start {
    raise InvalidOutgoingStackRange(
      start=outgoing_stack_start,
      size=outgoing_stack_size,
    )
  }
  let stack_transfers : Array[StackArgumentTransfer] = []
  let register_moves : Array[ParallelMove] = []
  let register_destinations : Array[PhysicalReg] = []
  let stack_indices : Array[Int] = []
  let scratch_reserved = protected_locations.copy()
  for transfer in transfers {
    if transfer.source is Register(source) &&
      !scratch_reserved.contains(Register(source)) {
      scratch_reserved.push(Register(source))
    }
    if transfer.destination is TransferRegister(destination) &&
      !scratch_reserved.contains(Register(destination)) {
      scratch_reserved.push(Register(destination))
    }
  }
  for index, transfer in transfers {
    match transfer.source {
      Register(source) =>
        if source.class != reg_class_for_value_type(transfer.ty) {
          raise InvalidSourceClass(index~)
        }
      Stack(slot) =>
        match allocation.stack_slot_type(slot) {
          None => raise ForeignSourceStack(index~)
          Some(actual) => {
            if actual != transfer.ty {
              raise InvalidSourceStackType(
                index~,
                expected=transfer.ty,
                actual~,
              )
            }
            let size = transfer_size(transfer.ty)
            if allocation.stack_slot_size(slot).unwrap() < size ||
              allocation.stack_slot_alignment(slot).unwrap() < size {
              raise InvalidSourceStackLayout(index~)
            }
          }
        }
    }
    match transfer.destination {
      TransferRegister(destination) => {
        if destination.class != reg_class_for_value_type(transfer.ty) {
          raise InvalidDestinationClass(index~)
        }
        if register_destinations.contains(destination) {
          raise DuplicateRegisterDestination(index~, register=destination)
        }
        register_destinations.push(destination)
        let destination_location = Register(destination)
        if protected_locations.contains(destination_location) &&
          transfer.source != destination_location {
          raise ProtectedLocationOverwrite(
            index~,
            location=destination_location,
          )
        }
        register_moves.push(
          ParallelMove::new(transfer.ty, transfer.source, destination_location),
        )
      }
      TransferOutgoingStack(offset) => {
        let size = transfer_size(transfer.ty)
        if offset < 0 || offset % size != 0 {
          raise InvalidStackOffset(index~, offset~)
        }
        let end = offset + size
        if offset < outgoing_stack_start ||
          end < offset ||
          end > outgoing_stack_end {
          raise OutgoingStackDestinationOutOfRange(index~, offset~)
        }
        for previous in stack_indices {
          let previous_transfer = transfers[previous]
          guard previous_transfer.destination
            is TransferOutgoingStack(previous_offset) else {
            continue
          }
          if ranges_overlap(
              offset,
              size,
              previous_offset,
              transfer_size(previous_transfer.ty),
            ) {
            raise OverlappingStackDestination(first=previous, second=index)
          }
        }
        stack_indices.push(index)
        let scratch = match transfer.source {
          Register(_) => None
          Stack(_) =>
            Some(
              stack_transfer_scratch(
                transfer.ty,
                scratch_int,
                scratch_fp,
                scratch_reserved,
              ),
            )
        }
        stack_transfers.push({
          ty: transfer.ty,
          source: transfer.source,
          offset,
          scratch,
        })
      }
    }
  }
  { stack_transfers, register_moves, }
}

///|
pub fn plan_call_transfers(
  allocation : Allocation,
  transfers : Array[CallTransfer],
  outgoing_stack_start : Int,
  outgoing_stack_size : Int,
  scratch_int : Array[PhysicalReg],
  scratch_fp : Array[PhysicalReg],
  protected_locations : Array[Location],
) -> CallTransferPlan raise CallTransferError {
  let transfer_plan = prepare_call_transfers(
    allocation, transfers, outgoing_stack_start, outgoing_stack_size, scratch_int,
    scratch_fp, protected_locations,
  )
  let register_moves = resolve_parallel_moves(
    transfer_plan.register_moves,
    scratch_int,
    scratch_fp,
  ) catch {
    error => raise MoveResolutionFailed(cause=error)
  }
  { stack_transfers: transfer_plan.stack_transfers, register_moves, }
}

///|
pub fn plan_resolved_call_transfers(
  allocation : Allocation,
  transfers : Array[CallTransfer],
  outgoing_stack_start : Int,
  outgoing_stack_size : Int,
  stack_scratch_int : Array[PhysicalReg],
  stack_scratch_fp : Array[PhysicalReg],
  move_scratch_int : PhysicalReg,
  move_scratch_fp : PhysicalReg,
  protected_locations : Array[Location],
) -> ResolvedCallTransferPlan raise CallTransferError {
  let transfer_plan = prepare_call_transfers(
    allocation, transfers, outgoing_stack_start, outgoing_stack_size, stack_scratch_int,
    stack_scratch_fp, protected_locations,
  )
  let register_moves = plan_parallel_moves(
    transfer_plan.register_moves,
    move_scratch_int,
    move_scratch_fp,
  ) catch {
    error => raise MoveResolutionFailed(cause=error)
  }
  { stack_transfers: transfer_plan.stack_transfers, register_moves, }
}
