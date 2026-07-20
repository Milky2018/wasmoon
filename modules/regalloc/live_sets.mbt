///|
struct LiveSetUseDef {
  vreg_id : Int
  def_point : ProgramPoint?
  is_entry_param_def : Bool
  use_points : Array[ProgramPoint]
} derive(Debug)

///|
struct DenseLiveSets {
  live_in : Array[Array[Int]]
  live_out : Array[Array[Int]]
} derive(Debug)

///|
priv struct LivenessWorklist {
  queue : Array[Int]
  in_worklist : Array[Bool]
}

///|
fn LivenessWorklist::LivenessWorklist(size : Int) -> LivenessWorklist {
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
fn compute_live_sets_from_use_defs(
  num_blocks : Int,
  num_vregs : Int,
  cfg : DenseCfgEdges,
  use_defs : Array[LiveSetUseDef],
) -> DenseLiveSets {
  let block_defs : Array[SparseVRegSet] = []
  let live_in : Array[SparseVRegSet] = []
  let live_out : Array[SparseVRegSet] = []
  for _ in 0..<num_blocks {
    block_defs.push(SparseVRegSet::new())
    live_in.push(SparseVRegSet::new())
    live_out.push(SparseVRegSet::new())
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
        block_defs[def.block].set(vreg_id, true)
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
        live_in[block_idx].set(vreg_id, true)
      }
    }
  }

  let worklist = LivenessWorklist::LivenessWorklist(num_blocks)
  for i in 0..<num_blocks {
    worklist.push(i)
  }
  while worklist.pop() is Some(block_idx) {
    let mut changed = false
    for succ in cfg.succs[block_idx] {
      if succ < 0 || succ >= live_in.length() {
        continue
      }
      if live_out[block_idx].union_with(live_in[succ]) {
        changed = true
      }
    }
    if live_in[block_idx].union_without(
        live_out[block_idx],
        block_defs[block_idx],
      ) {
      changed = true
    }
    if changed {
      for pred in cfg.preds[block_idx] {
        worklist.push(pred)
      }
    }
  }
  {
    live_in: live_in.map(set => set.to_sorted_array()),
    live_out: live_out.map(set => set.to_sorted_array()),
  }
}
