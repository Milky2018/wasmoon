///|
pub fn compute_spill_weight(
  uses : Array[@regalloc.UsePosition],
  loop_depths : Array[Int],
) -> Int {
  let mut weight = 0
  for use_pos in uses {
    let mut depth = if use_pos.point.block >= 0 &&
      use_pos.point.block < loop_depths.length() {
      loop_depths[use_pos.point.block]
    } else {
      0
    }
    if depth < 0 {
      depth = 0
    }
    if depth > 10 {
      depth = 10
    }
    let mut hot_bonus = 1000
    for _ in 0..<depth {
      hot_bonus = hot_bonus * 4
    }
    let def_bonus = match use_pos.kind {
      LiveDef | LiveUseDef => 2000
      LiveUse => 0
    }
    let constraint_bonus = match use_pos.constraint {
      AnyReg => 1000
      FixedReg(_) => 2000
    }
    weight = weight + hot_bonus + def_bonus + constraint_bonus
  }
  if weight <= 0 {
    1
  } else {
    weight
  }
}
