// Tests for stack layout

///|
test "stack frame: basic allocation" {
  let frame = StackFrame::new(16)

  // Allocate a spill slot
  let vreg : @abi.VReg = { id: 0, class: Int }
  let offset1 = frame.alloc_spill_slot(vreg, 8, 8)
  inspect(offset1, content="-8")

  // Allocate another spill slot
  let vreg2 : @abi.VReg = { id: 1, class: Int }
  let offset2 = frame.alloc_spill_slot(vreg2, 8, 8)
  inspect(offset2, content="-16")

  // Finalize
  frame.finalize()
  inspect(frame.size(), content="16")
}

///|
test "stack frame: alignment" {
  let frame = StackFrame::new(16)

  // Allocate a 4-byte slot
  let vreg : @abi.VReg = { id: 0, class: Int }
  let offset1 = frame.alloc_spill_slot(vreg, 4, 4)
  inspect(offset1, content="-4")

  // Allocate an 8-byte slot (should be aligned to 8)
  let vreg2 : @abi.VReg = { id: 1, class: Int }
  let offset2 = frame.alloc_spill_slot(vreg2, 8, 8)
  inspect(offset2, content="-16") // aligned to 8
  frame.finalize()
  // Frame should be aligned to 16
  inspect(frame.size(), content="16")
}

///|
test "stack frame: callee saved" {
  let frame = StackFrame::new(16)

  // Save some callee-saved registers
  let x19 : @abi.PReg = { index: 19, class: Int }
  let x20 : @abi.PReg = { index: 20, class: Int }
  let offset1 = frame.add_callee_saved(x19)
  inspect(offset1, content="-8")
  let offset2 = frame.add_callee_saved(x20)
  inspect(offset2, content="-16")
  frame.finalize()
  inspect(frame.get_callee_saved().length(), content="2")
}

///|
test "stack frame: local variables" {
  let frame = StackFrame::new(16)
  let offset1 = frame.alloc_local(0, 4, 4)
  inspect(offset1, content="-4")
  let offset2 = frame.alloc_local(1, 8, 8)
  inspect(offset2, content="-16")
  frame.finalize()
  inspect(frame.size(), content="16")
}

///|
test "aarch64 frame: setup" {
  let frame = AArch64StackFrame::new()
  frame.setup()

  // FP and LR should be saved
  inspect(frame.fp_slot is None, content="false")
  inspect(frame.lr_slot is None, content="false")
  frame.finalize()
  // Should have space for FP and LR (16 bytes, aligned)
  inspect(frame.size(), content="16")
}

///|
test "aarch64 frame: with spills" {
  let frame = AArch64StackFrame::new()
  frame.setup()

  // Add some spill slots
  let vreg1 : @abi.VReg = { id: 0, class: Int }
  let vreg2 : @abi.VReg = { id: 1, class: Float64 }
  frame.alloc_spill(vreg1) |> ignore
  frame.alloc_spill(vreg2) |> ignore
  frame.finalize()
  // FP + LR + 2 spills = 32 bytes
  inspect(frame.size(), content="32")
}

///|
test "aarch64 frame: prologue generation" {
  let frame = AArch64StackFrame::new()
  frame.setup()
  let vreg : @abi.VReg = { id: 0, class: Int }
  frame.alloc_spill(vreg) |> ignore
  frame.finalize()
  let prologue = frame.gen_prologue()
  // Should have: SUB sp, Store FP, Store LR, MOV fp,sp
  inspect(prologue.length() > 0, content="true")
}

///|
test "aarch64 frame: epilogue generation" {
  let frame = AArch64StackFrame::new()
  frame.setup()
  let vreg : @abi.VReg = { id: 0, class: Int }
  frame.alloc_spill(vreg) |> ignore
  frame.finalize()
  let epilogue = frame.gen_epilogue()
  // Should have: Load FP, Load LR, ADD sp
  inspect(epilogue.length() > 0, content="true")
}

///|
test "aarch64 frame: empty frame" {
  let frame = AArch64StackFrame::new()
  // Don't setup or add anything
  frame.finalize()
  let prologue = frame.gen_prologue()
  let epilogue = frame.gen_epilogue()

  // Empty frame should produce no instructions
  inspect(prologue.length(), content="0")
  inspect(epilogue.length(), content="0")
}

///|
test "stack frame: print" {
  let frame = StackFrame::new(16)
  let vreg : @abi.VReg = { id: 0, class: Int }
  frame.alloc_spill_slot(vreg, 8, 8) |> ignore
  frame.finalize()
  let output = frame.print()
  // Should contain frame info
  inspect(output.contains("Stack Frame"), content="true")
  inspect(output.contains("spill"), content="true")
}

///|
test "align_up: basic cases" {
  // align_up is a private function, but we can test it indirectly
  // through the frame allocation

  let frame = StackFrame::new(16)

  // 1 byte aligned to 8 should use 8 bytes of space
  let vreg : @abi.VReg = { id: 0, class: Int }
  frame.alloc_spill_slot(vreg, 1, 8) |> ignore

  // Next 8-byte allocation should be at offset -16
  let vreg2 : @abi.VReg = { id: 1, class: Int }
  let offset = frame.alloc_spill_slot(vreg2, 8, 8)
  inspect(offset, content="-16")
}

///|
test "build_stack_layout: from regalloc result" {
  // Create a simple function
  let func = VCodeFunction::new("test_layout")
  let a = func.add_param(Int)
  func.add_result(Int)
  let block = func.new_block()
  let inst = @instr.VCodeInst::new(Move)
  inst.add_def({ reg: Virtual(a) })
  inst.add_use(Virtual(a))
  block.add_inst(inst)
  block.set_terminator(Return([Virtual(a)]))

  // Create a regalloc result with some spills
  let alloc : RegAllocResult = {
    assignments: {},
    spill_slots: {},
    num_spill_slots: 0,
    inst_edits: {},
  }

  // Build stack layout
  let frame = build_stack_layout_aarch64(alloc, func)
  frame.finalize()

  // Frame should be valid
  inspect(frame.size() >= 0, content="true")
}
