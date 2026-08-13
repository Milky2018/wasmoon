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
pub(all) enum ResolvedMoveStep {
  Transfer(ParallelMove)
  SpillScratchToEmergency(ty~ : ValueType, scratch~ : PhysicalReg)
  ReloadScratchFromEmergency(ty~ : ValueType, scratch~ : PhysicalReg)
} derive(Eq, Debug)

///|
pub struct ResolvedMovePlan {
  steps : Array[ResolvedMoveStep]
  requires_emergency : Bool
} derive(Eq, Debug)

///|
pub suberror MoveResolveError {
  MissingScratch(class~ : RegClass)
  InvalidScratch(reg~ : PhysicalReg, expected~ : RegClass)
  NoSafeCycleScratch(class~ : RegClass)
  BrokenCycle
} derive(Eq, Debug)

///|
pub impl Show for MoveResolveError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
fn move_bank(ty : ValueType) -> RegClass {
  reg_class_for_value_type(ty)
}

///|
fn select_legacy_scratch(
  class : RegClass,
  moves : Array[ParallelMove],
  scratch_int : Array[PhysicalReg],
  scratch_fp : Array[PhysicalReg],
) -> PhysicalReg raise MoveResolveError {
  let candidates = if class == Int { scratch_int } else { scratch_fp }
  for reg in candidates {
    if reg.class != class {
      raise InvalidScratch(reg~, expected=class)
    }
    let candidate : Location = Register(reg)
    let mut used = false
    for transfer in moves {
      if transfer.from == candidate || transfer.to == candidate {
        used = true
        break
      }
    }
    if !used {
      return reg
    }
  }
  if candidates.is_empty() {
    raise MissingScratch(class~)
  }
  raise NoSafeCycleScratch(class~)
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
fn linearize_single_bank(
  moves : Array[ParallelMove],
  scratch : PhysicalReg,
) -> Array[ParallelMove] raise MoveResolveError {
  let pending : Array[ParallelMove] = []
  let scratch_location : Location = Register(scratch)
  for transfer in moves {
    if transfer.from != transfer.to && !pending.contains(transfer) {
      if move_bank(transfer.ty) != scratch.class {
        raise InvalidScratch(reg=scratch, expected=move_bank(transfer.ty))
      }
      if transfer.from == scratch_location || transfer.to == scratch_location {
        raise NoSafeCycleScratch(class=scratch.class)
      }
      pending.push(transfer)
    }
  }
  let result : Array[ParallelMove] = []
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
      Some(index) => result.push(pending.remove(index))
      None => {
        let transfer = pending.remove(0)
        let mut saved_type : ValueType? = None
        for pending_move in pending {
          if pending_move.from == transfer.to {
            saved_type = Some(pending_move.ty)
            break
          }
        }
        guard saved_type is Some(saved_type) else { raise BrokenCycle }
        result.push(
          ParallelMove::new(saved_type, transfer.to, scratch_location),
        )
        for index in 0..<pending.length() {
          if pending[index].from == transfer.to {
            pending[index] = ParallelMove::new(
              pending[index].ty,
              scratch_location,
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
fn legalize_single_bank(
  moves : Array[ParallelMove],
  scratch : PhysicalReg,
) -> ResolvedMovePlan {
  let steps : Array[ResolvedMoveStep] = []
  let scratch_location : Location = Register(scratch)
  let mut live_cycle_type : ValueType? = None
  let mut requires_emergency = false
  for transfer in moves {
    if transfer.from is Stack(_) && transfer.to is Stack(_) {
      match live_cycle_type {
        Some(ty) => {
          steps.push(SpillScratchToEmergency(ty~, scratch~))
          requires_emergency = true
        }
        None => ()
      }
      steps.push(
        Transfer(
          ParallelMove::new(transfer.ty, transfer.from, scratch_location),
        ),
      )
      steps.push(
        Transfer(ParallelMove::new(transfer.ty, scratch_location, transfer.to)),
      )
      match live_cycle_type {
        Some(ty) => steps.push(ReloadScratchFromEmergency(ty~, scratch~))
        None => ()
      }
    } else {
      steps.push(Transfer(transfer))
      if transfer.to == scratch_location {
        live_cycle_type = Some(transfer.ty)
      } else if transfer.from == scratch_location {
        live_cycle_type = None
      }
    }
  }
  { steps, requires_emergency }
}

///|
pub fn plan_parallel_moves(
  moves : Array[ParallelMove],
  scratch_int : PhysicalReg,
  scratch_fp : PhysicalReg,
) -> ResolvedMovePlan raise MoveResolveError {
  if scratch_int.class != Int {
    raise InvalidScratch(reg=scratch_int, expected=Int)
  }
  if scratch_fp.class != FpVector {
    raise InvalidScratch(reg=scratch_fp, expected=FpVector)
  }
  let int_moves : Array[ParallelMove] = []
  let fp_moves : Array[ParallelMove] = []
  for transfer in moves {
    if move_bank(transfer.ty) == Int {
      int_moves.push(transfer)
    } else {
      fp_moves.push(transfer)
    }
  }
  let int_plan = legalize_single_bank(
    linearize_single_bank(int_moves, scratch_int),
    scratch_int,
  )
  let fp_plan = legalize_single_bank(
    linearize_single_bank(fp_moves, scratch_fp),
    scratch_fp,
  )
  for step in fp_plan.steps {
    int_plan.steps.push(step)
  }
  {
    steps: int_plan.steps,
    requires_emergency: int_plan.requires_emergency ||
    fp_plan.requires_emergency,
  }
}

///|
pub fn resolve_parallel_moves(
  moves : Array[ParallelMove],
  scratch_int : Array[PhysicalReg],
  scratch_fp : Array[PhysicalReg],
) -> Array[ParallelMove] raise MoveResolveError {
  if moves.is_empty() {
    return []
  }
  let plan = plan_parallel_moves(
    moves,
    select_legacy_scratch(Int, moves, scratch_int, scratch_fp),
    select_legacy_scratch(FpVector, moves, scratch_int, scratch_fp),
  )
  let resolved : Array[ParallelMove] = []
  for step in plan.steps {
    match step {
      Transfer(transfer) => resolved.push(transfer)
      SpillScratchToEmergency(..) | ReloadScratchFromEmergency(..) =>
        raise NoSafeCycleScratch(class=Int)
    }
  }
  resolved
}
