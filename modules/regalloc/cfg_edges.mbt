///|
struct DenseCfgEdges {
  preds : Array[Array[Int]]
  succs : Array[Array[Int]]
} derive(Debug)

///|
fn build_dense_successor_edges(
  block_ids : Array[Int],
  block_successor_ids : Array[Array[Int]],
) -> DenseCfgEdges {
  let n = block_ids.length()
  let mut max_block_id = -1
  for block_id in block_ids {
    if block_id > max_block_id {
      max_block_id = block_id
    }
  }
  let block_id_to_index = if max_block_id < 0 {
    []
  } else {
    Array::make(max_block_id + 1, -1)
  }
  for i, block_id in block_ids {
    if block_id >= 0 && block_id < block_id_to_index.length() {
      block_id_to_index[block_id] = i
    }
  }

  let preds : Array[Array[Int]] = []
  let succs : Array[Array[Int]] = []
  for _ in 0..<n {
    preds.push([])
    succs.push([])
  }

  for block_idx, successor_ids in block_successor_ids {
    if block_idx >= n {
      break
    }
    let block_succs : Array[Int] = []
    for succ_id in successor_ids {
      if succ_id >= 0 && succ_id < block_id_to_index.length() {
        let succ_idx = block_id_to_index[succ_id]
        if succ_idx >= 0 {
          block_succs.push(succ_idx)
          preds[succ_idx].push(block_idx)
        }
      }
    }
    succs[block_idx] = block_succs
  }

  { preds, succs, }
}
