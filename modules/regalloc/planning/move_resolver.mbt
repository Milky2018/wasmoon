///|
pub(all) struct ParallelMove {
  from : @regalloc.Location
  to : @regalloc.Location
  class : @regalloc.RegClass
} derive(Eq, Debug)

///|
fn move_class_bank(class : @regalloc.RegClass) -> Int {
  match class {
    Int => 0
    Float | Vector => 1
  }
}

///|
fn move_class_key(class : @regalloc.RegClass) -> Int {
  match class {
    Int => 0
    Float => 1
    Vector => 2
  }
}

///|
fn move_same_location(
  lhs : @regalloc.Location,
  rhs : @regalloc.Location,
) -> Bool {
  lhs == rhs
}

///|
fn loc_exact_key(loc : @regalloc.Location, class : @regalloc.RegClass) -> Int {
  match loc {
    Reg(preg) => 1_000_000 + preg.id * 4 + move_class_key(preg.class)
    Spill(slot) => slot * 4 + move_class_key(class)
  }
}

///|
fn reg_bank(class : @regalloc.RegClass) -> Int {
  match class {
    Int => 0
    Float | Vector => 1
  }
}

///|
fn loc_key(loc : @regalloc.Location, class : @regalloc.RegClass) -> Int {
  match loc {
    Reg(preg) => preg.id * 2 + reg_bank(preg.class)
    Spill(slot) => 1_000_000 + slot * 4 + move_class_key(class)
  }
}

///|
fn aliases(
  lhs : @regalloc.Location,
  lhs_class : @regalloc.RegClass,
  rhs : @regalloc.Location,
  rhs_class : @regalloc.RegClass,
) -> Bool {
  loc_key(lhs, lhs_class) == loc_key(rhs, rhs_class)
}

///|
fn pick_scratch(
  class : @regalloc.RegClass,
  scratch_int : Array[@regalloc.PhysicalReg],
  scratch_float : Array[@regalloc.PhysicalReg],
  avoid : @regalloc.Location?,
) -> @regalloc.Location {
  let candidates = match class {
    Int => scratch_int
    Float | Vector => scratch_float
  }
  guard candidates.length() > 0 else {
    abort("resolve_parallel_moves: missing scratch registers")
  }
  if avoid is Some(Reg(preg)) &&
    candidates.length() > 1 &&
    candidates[0].id == preg.id {
    Reg(candidates[1])
  } else {
    Reg(candidates[0])
  }
}

///|
fn pick_cycle_scratch(
  class : @regalloc.RegClass,
  scratch_int : Array[@regalloc.PhysicalReg],
  scratch_float : Array[@regalloc.PhysicalReg],
  src_set : Set[Int],
  avoid_a : @regalloc.Location,
  avoid_b : @regalloc.Location,
) -> @regalloc.Location {
  let candidates = match class {
    Int => scratch_int
    Float | Vector => scratch_float
  }
  for preg in candidates {
    let candidate : @regalloc.Location = Reg(preg)
    let key = loc_key(candidate, class)
    if src_set.contains(key) {
      continue
    }
    if aliases(candidate, class, avoid_a, class) ||
      aliases(candidate, class, avoid_b, class) {
      continue
    }
    return candidate
  }
  abort("resolve_parallel_moves: no safe scratch register for cycle")
}

///|
fn emit_stack_to_stack(
  mv : ParallelMove,
  result : Array[ParallelMove],
  scratch_int : Array[@regalloc.PhysicalReg],
  scratch_float : Array[@regalloc.PhysicalReg],
) -> Unit {
  let temp = pick_scratch(mv.class, scratch_int, scratch_float, None)
  result.push({ from: mv.from, to: temp, class: mv.class })
  result.push({ from: temp, to: mv.to, class: mv.class })
}

///|
fn rebuild_src_set(pending : Array[ParallelMove]) -> Set[Int] {
  let srcs : Set[Int] = Set([])
  for mv in pending {
    srcs.add(loc_key(mv.from, mv.class))
  }
  srcs
}

///|
fn resolve_single_bank_moves(
  moves : Array[ParallelMove],
  scratch_int : Array[@regalloc.PhysicalReg],
  scratch_float : Array[@regalloc.PhysicalReg],
) -> Array[ParallelMove] {
  let result : Array[ParallelMove] = []
  let pending : Array[ParallelMove] = []
  let seen : Set[Int] = Set([])
  for mv in moves {
    if !move_same_location(mv.from, mv.to) {
      let key = (
          loc_exact_key(mv.from, mv.class) * 131071 +
          loc_exact_key(mv.to, mv.class)
        ) *
        8 +
        move_class_key(mv.class)
      if !seen.contains(key) {
        seen.add(key) |> ignore
        pending.push(mv)
      }
    }
  }
  if pending.length() <= 1 {
    if pending.length() == 1 &&
      pending[0].from is Spill(_) &&
      pending[0].to is Spill(_) {
      emit_stack_to_stack(pending[0], result, scratch_int, scratch_float)
      return result
    }
    return pending
  }
  while pending.length() > 0 {
    let src_set = rebuild_src_set(pending)
    let mut found_idx : Int? = None
    for i, mv in pending {
      if !src_set.contains(loc_key(mv.to, mv.class)) {
        found_idx = Some(i)
        break
      }
    }
    match found_idx {
      Some(idx) => {
        let mv = pending.remove(idx)
        if mv.from is Spill(_) && mv.to is Spill(_) {
          emit_stack_to_stack(mv, result, scratch_int, scratch_float)
        } else {
          result.push(mv)
        }
      }
      None => {
        let mv = pending.remove(0)
        let temp = pick_cycle_scratch(
          mv.class,
          scratch_int,
          scratch_float,
          src_set,
          mv.from,
          mv.to,
        )
        result.push({ from: mv.to, to: temp, class: mv.class })
        for i in 0..<pending.length() {
          if aliases(pending[i].from, pending[i].class, mv.to, mv.class) {
            pending[i] = {
              from: temp,
              to: pending[i].to,
              class: pending[i].class,
            }
          }
        }
        pending.push(mv)
      }
    }
  }
  result
}

///|
pub fn resolve_parallel_moves(
  moves : Array[ParallelMove],
  scratch_int : Array[@regalloc.PhysicalReg],
  scratch_float : Array[@regalloc.PhysicalReg],
) -> Array[ParallelMove] {
  let mut has_int = false
  let mut has_fp = false
  for mv in moves {
    if move_class_bank(mv.class) == 0 {
      has_int = true
    } else {
      has_fp = true
    }
  }
  if has_int && has_fp {
    let int_moves : Array[ParallelMove] = []
    let fp_moves : Array[ParallelMove] = []
    for mv in moves {
      if move_class_bank(mv.class) == 0 {
        int_moves.push(mv)
      } else {
        fp_moves.push(mv)
      }
    }
    let resolved = resolve_single_bank_moves(
      int_moves, scratch_int, scratch_float,
    )
    let resolved_fp = resolve_single_bank_moves(
      fp_moves, scratch_int, scratch_float,
    )
    for mv in resolved_fp {
      resolved.push(mv)
    }
    resolved
  } else {
    resolve_single_bank_moves(moves, scratch_int, scratch_float)
  }
}
