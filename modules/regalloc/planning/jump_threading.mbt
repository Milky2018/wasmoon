///|
pub(all) enum ThreadArg {
  PhysicalArg(Int, Int)
  VirtualArg(Int, Int)
} derive(Eq, Debug)

///|
pub(all) struct ThreadBlock {
  id : Int
  params : Array[Int]
  target : Int?
  target_args : Array[ThreadArg]
  is_empty : Bool
} derive(Debug)

///|
pub(all) struct ThreadedJump {
  target : Int
  args : Array[ThreadArg]
  changed : Bool
} derive(Debug)

///|
fn substitute_thread_args(
  forwarded_args : Array[ThreadArg],
  params : Array[Int],
  incoming_args : Array[ThreadArg],
) -> Array[ThreadArg]? {
  let rewritten : Array[ThreadArg] = []
  for arg in forwarded_args {
    match arg {
      PhysicalArg(_, _) => rewritten.push(arg)
      VirtualArg(vreg_id, _) => {
        let mut mapped : ThreadArg? = None
        for i, param_id in params {
          if param_id == vreg_id {
            mapped = Some(incoming_args[i])
            break
          }
        }
        match mapped {
          Some(value) => rewritten.push(value)
          None => return None
        }
      }
    }
  }
  Some(rewritten)
}

///|
fn build_thread_block_index(blocks : Array[ThreadBlock]) -> Map[Int, Int] {
  let block_idx_by_id : Map[Int, Int] = Map([])
  for i, block in blocks {
    block_idx_by_id.set(block.id, i)
  }
  block_idx_by_id
}

///|
/// Resolve a jump target through chains of empty jump-only blocks.
///
/// A block can be threaded when it is empty, jumps to another block, and its
/// jump arguments can be expressed as forwarding this block's parameters.
pub fn resolve_threaded_jump(
  blocks : Array[ThreadBlock],
  start_target : Int,
  start_args : Array[ThreadArg],
) -> ThreadedJump {
  let block_idx_by_id = build_thread_block_index(blocks)
  let mut current = start_target
  let mut current_args = start_args.copy()
  let visited : Map[Int, Bool] = Map([])
  let mut changed = false
  while true {
    if visited.get(current).unwrap_or(false) {
      return { target: start_target, args: start_args, changed: false }
    }
    visited.set(current, true)
    match block_idx_by_id.get(current) {
      Some(block_idx) => {
        let block = blocks[block_idx]
        if block.is_empty &&
          block.target is Some(next) &&
          next != current &&
          block.params.length() == current_args.length() &&
          substitute_thread_args(block.target_args, block.params, current_args)
          is Some(mapped) {
          current = next
          current_args = mapped
          changed = true
          continue
        }
        return { target: current, args: current_args, changed }
      }
      None => return { target: current, args: current_args, changed }
    }
  }
  { target: start_target, args: start_args, changed: false }
}
