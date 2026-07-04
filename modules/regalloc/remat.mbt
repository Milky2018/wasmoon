///|
pub(all) struct RematDefInfo {
  vreg : VirtualReg
  block_id : Int
  inst_index : Int
} derive(Eq, Debug)

///|
pub(all) struct RematUseInfo {
  vreg : VirtualReg
  block_id : Int
  inst_index : Int
} derive(Eq, Debug)

///|
pub(all) struct RematCloneInfo {
  vreg : VirtualReg
  block_id : Int
  inst_index : Int
} derive(Eq, Debug)

///|
fn find_remat_def(
  defs : Array[RematDefInfo],
  vreg : VirtualReg,
) -> RematDefInfo? {
  for def in defs {
    if def.vreg == vreg {
      return Some(def)
    }
  }
  None
}

///|
pub fn plan_long_distance_rematerializations(
  defs : Array[RematDefInfo],
  uses : Array[RematUseInfo],
  min_distance? : Int = 4,
  per_vreg_clone_cap? : Int = 16,
) -> Array[RematCloneInfo] {
  let clones : Array[RematCloneInfo] = []
  let clone_count : Map[Int, Int] = {}
  for item in uses {
    match find_remat_def(defs, item.vreg) {
      Some(def) => {
        if def.block_id != item.block_id {
          continue
        }
        if item.inst_index - def.inst_index < min_distance {
          continue
        }
        let cloned = clone_count.get(item.vreg.id).unwrap_or(0)
        if cloned >= per_vreg_clone_cap {
          continue
        }
        clone_count.set(item.vreg.id, cloned + 1)
        clones.push({
          vreg: item.vreg,
          block_id: item.block_id,
          inst_index: item.inst_index,
        })
      }
      None => ()
    }
  }
  clones
}
