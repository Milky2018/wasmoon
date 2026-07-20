///|
priv struct PlanMove {
  value : VirtualReg
  from : Location
  to : Location
}

///|
fn move_aliases(lhs : Location, rhs : Location) -> Bool {
  location_key(lhs) == location_key(rhs)
}

///|
fn move_source_is_pending(moves : Array[PlanMove], location : Location) -> Bool {
  for transfer in moves {
    if move_aliases(transfer.from, location) {
      return true
    }
  }
  false
}

///|
fn safe_move_scratch(
  environment : MachineEnv,
  class : RegClass,
  pending : Array[PlanMove],
) -> PhysicalReg? {
  for scratch in environment.scratch_regs {
    if scratch.class != class {
      continue
    }
    let location = Reg(scratch)
    let mut used = false
    for transfer in pending {
      if move_aliases(transfer.from, location) ||
        move_aliases(transfer.to, location) {
        used = true
        break
      }
    }
    if !used {
      return Some(scratch)
    }
  }
  None
}

///|
fn emit_resolved_move(
  result : Array[PlanMove],
  transfer : PlanMove,
  environment : MachineEnv,
) -> Unit raise VerifyError {
  if transfer.from is Spill(_) && transfer.to is Spill(_) {
    guard safe_move_scratch(environment, transfer.value.class, [transfer])
      is Some(reg) else {
      raise ScratchRegisterUnavailable(
        message="no scratch register for stack-to-stack transfer",
      )
    }
    result.push({ value: transfer.value, from: transfer.from, to: Reg(reg) })
    result.push({ value: transfer.value, from: Reg(reg), to: transfer.to })
  } else {
    result.push(transfer)
  }
}

///|
fn resolve_plan_moves(
  moves : Array[PlanMove],
  environment : MachineEnv,
) -> Array[PlanMove] raise VerifyError {
  let pending : Array[PlanMove] = []
  for transfer in moves {
    if transfer.from != transfer.to {
      let mut duplicate = false
      for previous in pending {
        if previous.value == transfer.value &&
          previous.from == transfer.from &&
          previous.to == transfer.to {
          duplicate = true
          break
        }
      }
      if !duplicate {
        pending.push(transfer)
      }
    }
  }
  let result : Array[PlanMove] = []
  while !pending.is_empty() {
    let mut ready = -1
    for index, transfer in pending {
      if !move_source_is_pending(pending, transfer.to) {
        ready = index
        break
      }
    }
    if ready >= 0 {
      emit_resolved_move(result, pending.remove(ready), environment)
      continue
    }
    let cycle = pending[0]
    guard safe_move_scratch(environment, cycle.value.class, pending)
      is Some(scratch) else {
      raise ScratchRegisterUnavailable(
        message="no safe scratch register for parallel-transfer cycle",
      )
    }
    let temporary = Reg(scratch)
    let mut source_value : VirtualReg? = None
    for transfer in pending {
      if move_aliases(transfer.from, cycle.to) {
        source_value = Some(transfer.value)
        break
      }
    }
    guard source_value is Some(value) else {
      raise InvalidPlan(message="parallel-transfer cycle has no source owner")
    }
    result.push({ value, from: cycle.to, to: temporary })
    for index in 0..<pending.length() {
      if move_aliases(pending[index].from, cycle.to) {
        pending[index] = {
          value: pending[index].value,
          from: temporary,
          to: pending[index].to,
        }
      }
    }
  }
  result
}

///|
fn resolve_instruction_edits(
  plan : AllocationPlan,
  environment : MachineEnv,
) -> Unit raise VerifyError {
  let original = plan.edits.copy()
  let positions : Array[EditPosition] = []
  for edit in original {
    if edit.position is Edge(_) || positions.contains(edit.position) {
      continue
    }
    positions.push(edit.position)
  }
  plan.edits.clear()
  for position in positions {
    let moves : Array[PlanMove] = []
    for edit in original {
      if edit.position == position {
        moves.push({ value: edit.value, from: edit.from, to: edit.to })
      }
    }
    for transfer in resolve_plan_moves(moves, environment) {
      plan.add_edit({
        value: transfer.value,
        from: transfer.from,
        to: transfer.to,
        position,
      })
    }
  }
  for edit in original {
    if edit.position is Edge(_) {
      plan.add_edit(edit)
    }
  }
}
