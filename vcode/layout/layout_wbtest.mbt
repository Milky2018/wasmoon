// Tests for block layout optimization

///|
test "layout: no loops - preserves order" {
  // Create a simple linear function: block0 -> block1 -> block2
  let func = @regalloc.VCodeFunction::new("test_linear")
  let a = func.add_param(@abi.Int)
  func.add_result(@abi.Int)
  let block0 = func.new_block()
  let block1 = func.new_block()
  let block2 = func.new_block()

  // block0: jump to block1
  block0.set_terminator(@instr.Jump(block1.id, []))

  // block1: jump to block2
  block1.set_terminator(@instr.Jump(block2.id, []))

  // block2: return
  block2.set_terminator(@instr.Return([@abi.Virtual(a)]))

  // Compute layout
  let order = layout_blocks(func)

  // Should preserve original order (no loops)
  inspect(order, content="[0, 1, 2]")
}

///|
test "layout: simple loop - rotates" {
  // Create a simple while loop:
  // block0 (entry): init, jump to block1
  // block1 (header): condition check, branch to block2 or block3
  // block2 (body): body, jump back to block1 (back edge)
  // block3 (exit): return

  let func = @regalloc.VCodeFunction::new("test_loop")
  let counter = func.add_param(@abi.Int)
  func.add_result(@abi.Int)
  let block0 = func.new_block() // entry
  let block1 = func.new_block() // header
  let block2 = func.new_block() // body
  let block3 = func.new_block() // exit

  // block0: jump to loop header
  block0.set_terminator(@instr.Jump(block1.id, []))

  // block1 (header): branch on condition
  // if counter != 0, go to body; else go to exit
  block1.set_terminator(
    @instr.BranchZero(@abi.Virtual(counter), false, false, block3.id, block2.id),
  )

  // block2 (body): decrement and jump back to header
  block2.set_terminator(@instr.Jump(block1.id, [])) // back edge

  // block3 (exit): return
  block3.set_terminator(@instr.Return([@abi.Virtual(counter)]))

  // Compute layout
  let order = layout_blocks(func)

  // After rotation, we want: entry -> body -> header -> exit
  // block0 (entry) placed first
  // block2 (body) placed before header
  // block1 (header) placed after body (so back edge falls through)
  // block3 (exit) placed last

  // Expected order: [0, 2, 1, 3]
  // block0 = entry (placed first)
  // block2 = body (loop body)
  // block1 = header (after latch/body for fall-through)
  // block3 = exit (after loop)
  inspect(order, content="[0, 2, 1, 3]")
}

///|
test "cfg: find back edges" {
  // Create a function with a loop
  let func = @regalloc.VCodeFunction::new("test_back_edge")
  func.add_param(@abi.Int) |> ignore
  let block0 = func.new_block()
  let block1 = func.new_block()

  // block0: jump to block1
  block0.set_terminator(@instr.Jump(block1.id, []))

  // block1: jump back to block0 (back edge)
  block1.set_terminator(@instr.Jump(block0.id, []))
  let cfg = VCodeCFG::build(func)
  let back_edges = cfg.find_back_edges()

  // Should find one back edge: block1 -> block0
  inspect(back_edges.length(), content="1")
  inspect(back_edges[0], content="(1, 0)")
}

///|
test "cfg: sparse block ids keep edges" {
  let func = @regalloc.VCodeFunction::new("test_sparse_block_ids")
  let block0 = func.new_block() // id 0
  let _block1 = func.new_block() // id 1 (removed)
  let _block2 = func.new_block() // id 2 (removed)
  let block3 = func.new_block() // id 3

  // Keep only id=0 and id=3 blocks so block IDs are sparse versus indices.
  func.get_blocks().remove(1) |> ignore
  func.get_blocks().remove(1) |> ignore

  // 0 -> 3 -> 0 creates one back edge in index space: 1 -> 0.
  block0.set_terminator(@instr.Jump(block3.id, []))
  block3.set_terminator(@instr.Jump(block0.id, []))
  let cfg = VCodeCFG::build(func)
  let back_edges = cfg.find_back_edges()
  inspect(back_edges.length(), content="1")
  inspect(back_edges[0], content="(1, 0)")
}

///|
test "cfg: find loops" {
  // Create a function with a simple loop
  let func = @regalloc.VCodeFunction::new("test_find_loop")
  let a = func.add_param(@abi.Int)
  let block0 = func.new_block() // entry
  let block1 = func.new_block() // header
  let block2 = func.new_block() // body
  let block3 = func.new_block() // exit
  block0.set_terminator(@instr.Jump(block1.id, []))
  block1.set_terminator(
    @instr.BranchZero(@abi.Virtual(a), false, false, block3.id, block2.id),
  )
  block2.set_terminator(@instr.Jump(block1.id, [])) // back edge
  block3.set_terminator(@instr.Return([]))
  let cfg = VCodeCFG::build(func)
  let loops = cfg.find_loops()

  // Should find one loop with header=1, latch=2
  inspect(loops.length(), content="1")
  inspect(loops[0].header, content="1")
  inspect(loops[0].latch, content="2")
}

///|
test "reorder_blocks: applies new order" {
  let func = @regalloc.VCodeFunction::new("test_reorder")
  let a = func.add_param(@abi.Int)
  func.add_result(@abi.Int)
  let block0 = func.new_block()
  let block1 = func.new_block()
  let block2 = func.new_block()
  block0.set_terminator(@instr.Jump(block1.id, []))
  block1.set_terminator(@instr.Jump(block2.id, []))
  block2.set_terminator(@instr.Return([@abi.Virtual(a)]))

  // Original order: [0, 1, 2]
  // New order: [0, 2, 1]
  let new_order = [0, 2, 1]
  let reordered = reorder_blocks(func, new_order)

  // Check that blocks are in new order
  let blocks = reordered.get_blocks()
  inspect(blocks[0].id, content="0")
  inspect(blocks[1].id, content="2")
  inspect(blocks[2].id, content="1")
}

///|
test "reorder_blocks: preserves spill slot count" {
  let func = @regalloc.VCodeFunction::new("test_reorder_spills")
  func.set_num_spill_slots(123)
  let block0 = func.new_block()
  let block1 = func.new_block()
  block0.set_terminator(@instr.Jump(block1.id, []))
  block1.set_terminator(@instr.Return([]))
  let reordered = reorder_blocks(func, [1, 0])
  inspect(reordered.get_num_spill_slots(), content="123")
}

///|
test "layout: loop with exit chain" {
  // Test case matching fib structure:
  // block0 (entry): jump to block2
  // block1 (return): return
  // block2 (header): condition check, branch to block4 or block3
  // block3 (body): jump back to block2 (back edge)
  // block4 (exit): setup, jump to block1

  let func = @regalloc.VCodeFunction::new("test_fib_like")
  let counter = func.add_param(@abi.Int)
  func.add_result(@abi.Int)
  let block0 = func.new_block() // entry
  let block1 = func.new_block() // return block
  let block2 = func.new_block() // header
  let block3 = func.new_block() // body
  let block4 = func.new_block() // exit (before return)

  // block0: jump to header
  block0.set_terminator(@instr.Jump(block2.id, []))

  // block1: return
  block1.set_terminator(@instr.Return([@abi.Virtual(counter)]))

  // block2 (header): branch on condition
  block2.set_terminator(
    @instr.BranchZero(@abi.Virtual(counter), false, false, block4.id, block3.id),
  )

  // block3 (body): jump back to header
  block3.set_terminator(@instr.Jump(block2.id, [])) // back edge

  // block4 (exit): jump to return
  block4.set_terminator(@instr.Jump(block1.id, []))

  // Compute layout
  let order = layout_blocks(func)

  // Expected order: [0, 3, 2, 4, 1]
  // block0 = entry (placed first)
  // block3 = body (loop body, latch)
  // block2 = header (after latch for back edge fall-through)
  // block4 = exit (after header for exit fall-through)
  // block1 = return (remaining)
  inspect(order, content="[0, 3, 2, 4, 1]")
}

///|
test "optimize_layout: full pipeline" {
  // Test the full optimization pipeline
  let func = @regalloc.VCodeFunction::new("test_optimize")
  let counter = func.add_param(@abi.Int)
  func.add_result(@abi.Int)
  let block0 = func.new_block() // entry
  let block1 = func.new_block() // header
  let block2 = func.new_block() // body
  let block3 = func.new_block() // exit
  block0.set_terminator(@instr.Jump(block1.id, []))
  block1.set_terminator(
    @instr.BranchZero(@abi.Virtual(counter), false, false, block3.id, block2.id),
  )
  block2.set_terminator(@instr.Jump(block1.id, []))
  block3.set_terminator(@instr.Return([@abi.Virtual(counter)]))
  let optimized = optimize_layout(func)

  // After optimization, blocks should be reordered for loop rotation
  let blocks = optimized.get_blocks()
  inspect(blocks.length(), content="4")

  // Jump threading may change exact order for empty loop-body blocks.
  // Keep a stable invariant: entry block stays first and all block IDs remain.
  inspect(blocks[0].id, content="0")
  let mut seen0 = false
  let mut seen1 = false
  let mut seen2 = false
  let mut seen3 = false
  for block in blocks {
    if block.id == 0 {
      seen0 = true
    } else if block.id == 1 {
      seen1 = true
    } else if block.id == 2 {
      seen2 = true
    } else if block.id == 3 {
      seen3 = true
    }
  }
  inspect(seen0 && seen1 && seen2 && seen3, content="true")
}

///|
test "optimize_layout: threads trivial conditional targets" {
  // Mirrors Cranelift's trivial-jump-block elimination:
  // block0 branches to block1/block2, both are empty jumps to block3.
  // After threading, block0 should become an unconditional jump to block3.
  let func = @regalloc.VCodeFunction::new("test_thread_conditional")
  let cond = func.add_param(@abi.Int)
  let block0 = func.new_block()
  let block1 = func.new_block()
  let block2 = func.new_block()
  let block3 = func.new_block()
  block0.set_terminator(
    @instr.BranchZero(@abi.Virtual(cond), false, false, block1.id, block2.id),
  )
  block1.set_terminator(@instr.Jump(block3.id, []))
  block2.set_terminator(@instr.Jump(block3.id, []))
  block3.set_terminator(@instr.Return([]))
  let optimized = optimize_layout(func)
  let mut threaded_to_jump = false
  for block in optimized.get_blocks() {
    if block.id == 0 {
      if block.terminator is Some(@instr.Jump(target, args)) &&
        target == 3 &&
        args.length() == 0 {
        threaded_to_jump = true
      }
      break
    }
  }
  inspect(threaded_to_jump, content="true")
}

///|
test "optimize_layout: threads jump chains transitively" {
  // block0 -> block1 -> block2 -> block3, with all middle blocks trivial jumps.
  // block0 should be retargeted directly to block3 after threading.
  let func = @regalloc.VCodeFunction::new("test_thread_chain")
  let block0 = func.new_block()
  let block1 = func.new_block()
  let block2 = func.new_block()
  let block3 = func.new_block()
  block0.set_terminator(@instr.Jump(block1.id, []))
  block1.set_terminator(@instr.Jump(block2.id, []))
  block2.set_terminator(@instr.Jump(block3.id, []))
  block3.set_terminator(@instr.Return([]))
  let optimized = optimize_layout(func)
  let mut retargeted = false
  for block in optimized.get_blocks() {
    if block.id == 0 {
      if block.terminator is Some(@instr.Jump(target, args)) &&
        target == 3 &&
        args.length() == 0 {
        retargeted = true
      }
      break
    }
  }
  inspect(retargeted, content="true")
}
