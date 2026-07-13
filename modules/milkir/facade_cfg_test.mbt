///|
fn build_public_diamond() -> @milkir.Function raise @milkir.VerifyError {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("diamond")
  let condition = builder.add_param(I32)
  let left = builder.create_block()
  let right = builder.create_block()
  let exit = builder.create_block()
  builder.brnz(condition, left, right)
  builder.switch_to_block(left)
  builder.jump(exit, [])
  builder.switch_to_block(right)
  builder.jump(exit, [])
  builder.switch_to_block(exit)
  builder.return_([])
  builder.finalize()
}

///|
test "public CFG reports diamond edges" {
  let cfg = @milkir.CFG::build(build_public_diamond())
  debug_inspect(
    cfg,
    content=(
      #|{
      #|  size: 4,
      #|  num_blocks: 4,
      #|  successors: [[1, 2], [3], [3], []],
      #|  predecessors: [[], [0], [0], [1, 2]],
      #|  valid: [true, true, true, true],
      #|}
    ),
  )
  let valid_blocks : Array[Int] = []
  let exit_blocks : Array[Int] = []
  for block_id in -1..<=4 {
    if cfg.is_valid(block_id) {
      valid_blocks.push(block_id)
    }
    if cfg.is_valid(block_id) && cfg.is_exit_block(block_id) {
      exit_blocks.push(block_id)
    }
  }
  debug_inspect(
    valid_blocks,
    content=(
      #|[0, 1, 2, 3]
    ),
  )
  debug_inspect(
    exit_blocks,
    content=(
      #|[3]
    ),
  )
}

///|
test "public CFG reports dominance and complete traversals" {
  let cfg = @milkir.CFG::build(build_public_diamond())
  let dominance : Array[(Int, Int)] = []
  for dominator in 0..<cfg.num_blocks {
    for block_id in 0..<cfg.num_blocks {
      if cfg.dominates(dominator, block_id) {
        dominance.push((dominator, block_id))
      }
    }
  }
  debug_inspect(
    dominance,
    content=(
      #|[(0, 0), (0, 1), (0, 2), (0, 3), (1, 1), (2, 2), (3, 3)]
    ),
  )
  debug_inspect(
    cfg.compute_dominators(),
    content=(
      #|[0, 0, 0, 0]
    ),
  )
  debug_inspect(
    cfg.postorder(),
    content=(
      #|[3, 1, 2, 0]
    ),
  )
  debug_inspect(
    cfg.reverse_postorder(),
    content=(
      #|[0, 2, 1, 3]
    ),
  )
}

///|
test "public CFG renders graphviz edges" {
  let dot = @milkir.CFG::build(build_public_diamond()).to_dot("diamond")
  inspect(
    dot,
    content=(
      #|digraph diamond {
      #|  node [shape=box];
      #|  block0 -> block1;
      #|  block0 -> block2;
      #|  block1 -> block3;
      #|  block2 -> block3;
      #|}
      #|
    ),
  )
}

///|
test "public CFG discovers a natural loop and its preheader" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("loop")
  let condition = builder.add_param(I32)
  let header = builder.create_block()
  let body = builder.create_block()
  let exit = builder.create_block()
  builder.jump(header, [])
  builder.switch_to_block(header)
  builder.brnz(condition, body, exit)
  builder.switch_to_block(body)
  builder.jump(header, [])
  builder.switch_to_block(exit)
  builder.return_([])
  let cfg = @milkir.CFG::build(builder.finalize())
  debug_inspect(cfg.find_back_edges(), content="[(2, 1)]")
  let loops = cfg.find_loops()
  debug_inspect(
    loops,
    content=(
      #|[{ header: 1, blocks: [1, 2], back_edges: [(2, 1)] }]
    ),
  )
  debug_inspect(
    cfg.get_loop_preheader(loops[0]),
    content=(
      #|Some(0)
    ),
  )
}
