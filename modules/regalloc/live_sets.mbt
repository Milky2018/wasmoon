///|
pub(all) struct LiveSetUseDef {
  vreg_id : Int
  def_point : ProgramPoint?
  is_entry_param_def : Bool
  use_points : Array[ProgramPoint]
} derive(Debug)

///|
pub(all) struct DenseLiveSets {
  live_in : Array[Array[Int]]
  live_out : Array[Array[Int]]
} derive(Debug)

///|
priv struct LivenessWorklist {
  queue : Array[Int]
  in_worklist : Array[Bool]
}

///|
fn LivenessWorklist::new(size : Int) -> LivenessWorklist {
  { queue: [], in_worklist: Array::make(size, false) }
}

///|
fn LivenessWorklist::push(self : LivenessWorklist, block_id : Int) -> Unit {
  if block_id >= 0 &&
    block_id < self.in_worklist.length() &&
    !self.in_worklist[block_id] {
    self.queue.push(block_id)
    self.in_worklist[block_id] = true
  }
}

///|
fn LivenessWorklist::pop(self : LivenessWorklist) -> Int? {
  match self.queue.pop() {
    Some(id) => {
      self.in_worklist[id] = false
      Some(id)
    }
    None => None
  }
}

///|
fn live_set_mask_index(block_idx : Int, vreg_id : Int, row_width : Int) -> Int {
  block_idx * row_width + vreg_id
}

///|
pub fn compute_dense_live_sets(
  num_blocks : Int,
  num_vregs : Int,
  cfg : DenseCfgEdges,
  use_defs : Array[LiveSetUseDef],
) -> DenseLiveSets {
  let matrix_size = num_blocks * num_vregs
  let block_def_mask : FixedArray[Bool] = FixedArray::make(matrix_size, false)
  let live_in_mask : FixedArray[Bool] = FixedArray::make(matrix_size, false)
  let live_out_mask : FixedArray[Bool] = FixedArray::make(matrix_size, false)
  let live_in_list : Array[Array[Int]] = []
  let live_out_list : Array[Array[Int]] = []
  for _ in 0..<num_blocks {
    live_in_list.push([])
    live_out_list.push([])
  }

  for info in use_defs {
    let vreg_id = info.vreg_id
    if vreg_id < 0 || vreg_id >= num_vregs {
      continue
    }
    let mut def_point : ProgramPoint? = None
    if info.def_point is Some(def) {
      if !info.is_entry_param_def {
        def_point = Some(def)
      }
      if !info.is_entry_param_def && def.block >= 0 && def.block < num_blocks {
        let idx = live_set_mask_index(def.block, vreg_id, num_vregs)
        if idx >= 0 && idx < block_def_mask.length() {
          block_def_mask[idx] = true
        }
      }
    }
    for use_point in info.use_points {
      let block_idx = use_point.block
      if block_idx < 0 || block_idx >= num_blocks {
        continue
      }
      let include_use = match def_point {
        Some(def) =>
          if def.block != block_idx {
            true
          } else {
            use_point.compare_with_order(def, []) < 0
          }
        None => true
      }
      if include_use {
        let idx = live_set_mask_index(block_idx, vreg_id, num_vregs)
        if idx >= 0 && idx < live_in_mask.length() && !live_in_mask[idx] {
          live_in_mask[idx] = true
          live_in_list[block_idx].push(vreg_id)
        }
      }
    }
  }

  let worklist = LivenessWorklist::new(num_blocks)
  for i in 0..<num_blocks {
    worklist.push(i)
  }
  while worklist.pop() is Some(block_idx) {
    let old_live_in_size = live_in_list[block_idx].length()
    let row_base = block_idx * num_vregs

    for succ in cfg.succs[block_idx] {
      if succ < 0 || succ >= live_in_list.length() {
        continue
      }
      for vreg_id in live_in_list[succ] {
        let out_idx = row_base + vreg_id
        if out_idx < 0 || out_idx >= live_out_mask.length() {
          continue
        }
        if !live_out_mask[out_idx] {
          live_out_mask[out_idx] = true
          live_out_list[block_idx].push(vreg_id)
          let def_idx = row_base + vreg_id
          let in_idx = row_base + vreg_id
          if def_idx >= 0 &&
            def_idx < block_def_mask.length() &&
            !block_def_mask[def_idx] &&
            in_idx >= 0 &&
            in_idx < live_in_mask.length() &&
            !live_in_mask[in_idx] {
            live_in_mask[in_idx] = true
            live_in_list[block_idx].push(vreg_id)
          }
        }
      }
    }

    if live_in_list[block_idx].length() > old_live_in_size {
      for pred in cfg.preds[block_idx] {
        worklist.push(pred)
      }
    }
  }

  { live_in: live_in_list, live_out: live_out_list }
}
