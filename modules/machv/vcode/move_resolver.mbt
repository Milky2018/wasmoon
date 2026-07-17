///|
pub struct ParallelMove {
  ty : ValueType
  from : Location
  to : Location
} derive(Eq, Debug)

///|
pub fn ParallelMove::new(
  ty : ValueType,
  from : Location,
  to : Location,
) -> ParallelMove {
  { ty, from, to }
}

///|
pub suberror MoveResolveError {
  MissingScratch(class~ : RegClass)
  InvalidScratch(reg~ : PhysicalReg, expected~ : RegClass)
  NoSafeCycleScratch(class~ : RegClass)
  BrokenCycle
} derive(Eq, Debug)

///|
pub impl Show for MoveResolveError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn move_bank(ty : ValueType) -> RegClass {
  reg_class_for_value_type(ty)
}

///|
fn scratch_for_bank(
  class : RegClass,
  scratch_int : Array[PhysicalReg],
  scratch_fp : Array[PhysicalReg],
) -> Array[PhysicalReg] raise MoveResolveError {
  let candidates = if class == Int { scratch_int } else { scratch_fp }
  for reg in candidates {
    if reg.class != class {
      raise InvalidScratch(reg~, expected=class)
    }
  }
  if candidates.is_empty() {
    raise MissingScratch(class~)
  }
  candidates
}

///|
fn pick_scratch(
  class : RegClass,
  scratch_int : Array[PhysicalReg],
  scratch_fp : Array[PhysicalReg],
) -> Location raise MoveResolveError {
  Register(scratch_for_bank(class, scratch_int, scratch_fp)[0])
}

///|
fn source_locations(moves : Array[ParallelMove]) -> Array[Location] {
  let sources : Array[Location] = []
  for transfer in moves {
    if !sources.contains(transfer.from) {
      sources.push(transfer.from)
    }
  }
  sources
}

///|
fn pick_cycle_scratch(
  class : RegClass,
  scratch_int : Array[PhysicalReg],
  scratch_fp : Array[PhysicalReg],
  sources : Array[Location],
  from : Location,
  to : Location,
) -> Location raise MoveResolveError {
  for reg in scratch_for_bank(class, scratch_int, scratch_fp) {
    let candidate : Location = Register(reg)
    if !sources.contains(candidate) && candidate != from && candidate != to {
      return candidate
    }
  }
  raise NoSafeCycleScratch(class~)
}

///|
fn emit_stack_to_stack(
  transfer : ParallelMove,
  result : Array[ParallelMove],
  scratch_int : Array[PhysicalReg],
  scratch_fp : Array[PhysicalReg],
) -> Unit raise MoveResolveError {
  let temporary = pick_scratch(move_bank(transfer.ty), scratch_int, scratch_fp)
  result.push(ParallelMove::new(transfer.ty, transfer.from, temporary))
  result.push(ParallelMove::new(transfer.ty, temporary, transfer.to))
}

///|
fn resolve_single_bank(
  moves : Array[ParallelMove],
  scratch_int : Array[PhysicalReg],
  scratch_fp : Array[PhysicalReg],
) -> Array[ParallelMove] raise MoveResolveError {
  let result : Array[ParallelMove] = []
  let pending : Array[ParallelMove] = []
  for transfer in moves {
    if transfer.from != transfer.to && !pending.contains(transfer) {
      pending.push(transfer)
    }
  }
  if pending.length() == 1 {
    let transfer = pending[0]
    if transfer.from is Stack(_) && transfer.to is Stack(_) {
      emit_stack_to_stack(transfer, result, scratch_int, scratch_fp)
      return result
    }
    return pending
  }
  while !pending.is_empty() {
    let sources = source_locations(pending)
    let mut ready : Int? = None
    for index, transfer in pending {
      if !sources.contains(transfer.to) {
        ready = Some(index)
        break
      }
    }
    match ready {
      Some(index) => {
        let transfer = pending.remove(index)
        if transfer.from is Stack(_) && transfer.to is Stack(_) {
          emit_stack_to_stack(transfer, result, scratch_int, scratch_fp)
        } else {
          result.push(transfer)
        }
      }
      None => {
        let transfer = pending.remove(0)
        let class = move_bank(transfer.ty)
        let temporary = pick_cycle_scratch(
          class,
          scratch_int,
          scratch_fp,
          sources,
          transfer.from,
          transfer.to,
        )
        let mut saved_type : ValueType? = None
        for pending_move in pending {
          if pending_move.from == transfer.to {
            saved_type = Some(pending_move.ty)
            break
          }
        }
        guard saved_type is Some(saved_type) else { raise BrokenCycle }
        result.push(ParallelMove::new(saved_type, transfer.to, temporary))
        for index in 0..<pending.length() {
          if pending[index].from == transfer.to {
            pending[index] = ParallelMove::new(
              pending[index].ty,
              temporary,
              pending[index].to,
            )
          }
        }
        pending.push(transfer)
      }
    }
  }
  result
}

///|
pub fn resolve_parallel_moves(
  moves : Array[ParallelMove],
  scratch_int : Array[PhysicalReg],
  scratch_fp : Array[PhysicalReg],
) -> Array[ParallelMove] raise MoveResolveError {
  let int_moves : Array[ParallelMove] = []
  let fp_moves : Array[ParallelMove] = []
  for transfer in moves {
    if move_bank(transfer.ty) == Int {
      int_moves.push(transfer)
    } else {
      fp_moves.push(transfer)
    }
  }
  let resolved = resolve_single_bank(int_moves, scratch_int, scratch_fp)
  for transfer in resolve_single_bank(fp_moves, scratch_int, scratch_fp) {
    resolved.push(transfer)
  }
  resolved
}
