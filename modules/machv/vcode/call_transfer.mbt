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
  { ty, source, destination: TransferRegister(destination) }
}

///|
pub fn CallTransfer::to_stack(
  ty : ValueType,
  source : Location,
  offset : Int,
) -> CallTransfer {
  { ty, source, destination: TransferOutgoingStack(offset) }
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
pub suberror CallTransferError {
  InvalidSourceClass(index~ : Int)
  InvalidDestinationClass(index~ : Int)
  InvalidStackOffset(index~ : Int, offset~ : Int)
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
) -> PhysicalReg raise CallTransferError {
  let candidates = if reg_class_for_value_type(ty) == Int {
    scratch_int
  } else {
    scratch_fp
  }
  guard candidates.get(0) is Some(scratch) else {
    raise MoveResolutionFailed(
      cause=MissingScratch(class=reg_class_for_value_type(ty)),
    )
  }
  if scratch.class != reg_class_for_value_type(ty) {
    raise MoveResolutionFailed(
      cause=InvalidScratch(reg=scratch, expected=reg_class_for_value_type(ty)),
    )
  }
  scratch
}

///|
/// Build one atomic call setup from allocated sources.
///
/// Outgoing stack arguments are captured before any ABI register destination is
/// overwritten. Register destinations are then resolved as one parallel move.
pub fn plan_call_transfers(
  transfers : Array[CallTransfer],
  scratch_int : Array[PhysicalReg],
  scratch_fp : Array[PhysicalReg],
  protected_locations : Array[Location],
) -> CallTransferPlan raise CallTransferError {
  let stack_transfers : Array[StackArgumentTransfer] = []
  let register_moves : Array[ParallelMove] = []
  let register_destinations : Array[PhysicalReg] = []
  let stack_indices : Array[Int] = []
  for index, transfer in transfers {
    if transfer.source is Register(source) &&
      source.class != reg_class_for_value_type(transfer.ty) {
      raise InvalidSourceClass(index~)
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
            Some(stack_transfer_scratch(transfer.ty, scratch_int, scratch_fp))
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
  let register_moves = resolve_parallel_moves(
    register_moves, scratch_int, scratch_fp,
  ) catch {
    error => raise MoveResolutionFailed(cause=error)
  }
  { stack_transfers, register_moves }
}
