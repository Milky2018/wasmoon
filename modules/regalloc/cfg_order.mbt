///|
/// Reverse postorder over every CFG root, starting with the entry block.
///
/// The verifier seeds block 0 and every predecessor-free block separately,
/// so unreachable rooted components remain verifiable. The explicit stack
/// keeps input-controlled CFG depth off the native call stack.
fn reverse_postorder_from_roots(
  successors : Array[Array[Int]],
  has_predecessor : Array[Bool],
) -> Array[Int] {
  let postorder : Array[Int] = []
  let visited = Array::make(successors.length(), false)
  for root in 0..<successors.length() {
    if root != 0 && has_predecessor[root] {
      continue
    }
    if visited[root] {
      continue
    }
    let stack : Array[(Int, Int)] = [(root, 0)]
    visited[root] = true
    while stack.length() > 0 {
      let (block, next_successor) = stack[stack.length() - 1]
      let block_successors = successors[block]
      if next_successor < block_successors.length() {
        stack[stack.length() - 1] = (block, next_successor + 1)
        let target = block_successors[next_successor]
        if target >= 0 && target < successors.length() && !visited[target] {
          visited[target] = true
          stack.push((target, 0))
        }
      } else {
        postorder.push(block)
        stack.pop() |> ignore
      }
    }
  }
  postorder.rev_in_place()
  postorder
}
