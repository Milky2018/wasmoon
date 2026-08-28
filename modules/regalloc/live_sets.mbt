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
  { queue: [], in_worklist: Array::make(size, false), }
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
fn propagate_live_sets(
  num_blocks : Int,
  cfg : DenseCfgEdges,
  block_defs : Array[SparseVRegSet],
  live_in : Array[SparseVRegSet],
) -> DenseLiveSets {
  let live_out : Array[SparseVRegSet] = []
  let dense_word_count = match live_in.get(0) {
    Some(set) =>
      match set.words {
        Dense(words) => words.length()
        _ => 0
      }
    None => 0
  }
  for _ in 0..<num_blocks {
    live_out.push(
      if dense_word_count > 0 {
        { words: Dense(Array::make(dense_word_count, 0UL)), }
      } else {
        SparseVRegSet::new()
      },
    )
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
