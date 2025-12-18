// Tests for JITStackFrame (ABI v3)

///|
test "jit_stack_frame_basic" {
  // Basic frame with no spills or clobbered registers, no calls
  let frame = JITStackFrame::build(
    [],
    [],
    0,
    has_calls=false,
    outgoing_args_size=0,
  )

  // Only X19 is saved (vmctx) = 1 reg = 1 pair = 16 bytes
  inspect(frame.gpr_save_size, content="16")
  inspect(frame.fpr_save_size, content="0")
  inspect(frame.spill_size, content="16") // MIN_SPILL_SIZE
  inspect(frame.outgoing_args_size, content="0")
  // has_setup_area = true because we have saved_gprs
  inspect(frame.has_setup_area, content="true")
  // total = setup_area(16) + gpr(16) + fpr(0) + spill(16) + outgoing(0) = 48
  inspect(frame.total_size, content="48")
  inspect(frame.frame_size, content="32") // gpr + fpr + spill + outgoing
  inspect(frame.saved_gprs.length(), content="1") // Only X19
}

///|
test "jit_stack_frame_with_spills" {
  // Frame with spill slots
  let frame = JITStackFrame::build(
    [],
    [],
    5,
    has_calls=false,
    outgoing_args_size=0,
  )

  // 5 spills = 40 bytes, aligned to 16 = 48 bytes
  inspect(frame.spill_size, content="48")
  // total = setup(16) + gpr(16) + fpr(0) + spill(48) = 80
  inspect(frame.total_size, content="80")
}

///|
test "jit_stack_frame_with_fprs" {
  // Frame with FPR saves
  let frame = JITStackFrame::build(
    [],
    [8, 9],
    0,
    has_calls=false,
    outgoing_args_size=0,
  )

  // 2 FPRs = 1 pair = 16 bytes
  inspect(frame.fpr_save_size, content="16")
  inspect(frame.saved_fprs.length(), content="2")
  // total = setup(16) + gpr(16) + fpr(16) + spill(16) = 64
  inspect(frame.total_size, content="64")
}

///|
test "jit_stack_frame_with_calls" {
  // Frame with calls (requires FP/LR save)
  let frame = JITStackFrame::build(
    [],
    [],
    0,
    has_calls=true,
    outgoing_args_size=0,
  )

  // has_calls=true means we need setup area
  inspect(frame.has_setup_area, content="true")
  inspect(frame.setup_area_size, content="16")
  inspect(frame.saved_gprs.length(), content="1") // Only X19
}

///|
test "jit_stack_frame_with_clobbered_gprs" {
  // Frame with additional clobbered GPRs
  let frame = JITStackFrame::build(
    [20, 25, 26],
    [],
    0,
    has_calls=false,
    outgoing_args_size=0,
  )

  // X19 (always) + clobbered: 20, 25, 26 -> 19, 20, 25, 26 = 4 regs
  inspect(frame.saved_gprs.length(), content="4")
  inspect(frame.gpr_save_size, content="32") // 4 regs = 2 pairs = 32 bytes
}

///|
test "jit_stack_frame_odd_fprs" {
  // Frame with odd number of FPRs
  let frame = JITStackFrame::build(
    [],
    [8, 9, 10],
    0,
    has_calls=false,
    outgoing_args_size=0,
  )

  // 3 FPRs = 2 pairs = 32 bytes
  inspect(frame.fpr_save_size, content="32")
  inspect(frame.saved_fprs.length(), content="3")
}

///|
test "jit_stack_frame_alignment" {
  // Test that total size is always 16-byte aligned
  let frame1 = JITStackFrame::build(
    [],
    [],
    1,
    has_calls=false,
    outgoing_args_size=0,
  )
  inspect(frame1.total_size % 16, content="0")
  let frame2 = JITStackFrame::build(
    [],
    [],
    3,
    has_calls=false,
    outgoing_args_size=0,
  )
  inspect(frame2.total_size % 16, content="0")
  let frame3 = JITStackFrame::build(
    [],
    [8],
    2,
    has_calls=false,
    outgoing_args_size=0,
  )
  inspect(frame3.total_size % 16, content="0")
}

///|
test "jit_stack_frame_spill_offset" {
  // Test spill slot offset calculation
  let frame = JITStackFrame::build(
    [],
    [],
    5,
    has_calls=false,
    outgoing_args_size=0,
  )
  inspect(frame.get_spill_offset(0), content=frame.spill_offset.to_string())
  inspect(
    frame.get_spill_offset(1),
    content=(frame.spill_offset + 8).to_string(),
  )
  inspect(
    frame.get_spill_offset(4),
    content=(frame.spill_offset + 32).to_string(),
  )
}

///|
test "jit_stack_frame_outgoing_args" {
  // Test outgoing arguments area
  let frame = JITStackFrame::build(
    [],
    [],
    0,
    has_calls=true,
    outgoing_args_size=32,
  )
  inspect(frame.outgoing_args_size, content="32")
  inspect(frame.outgoing_args_offset, content="0") // At SP
  // total = setup(16) + gpr(16) + fpr(0) + spill(16) + outgoing(32) = 80
  inspect(frame.total_size, content="80")
}

///|
test "jit_stack_frame_complex" {
  // Complex scenario
  // Clobbered: X20, X25, X26
  // FPRs: D8, D9
  // Spills: 5 slots
  // has_calls: true
  // outgoing_args: 16
  let frame = JITStackFrame::build(
    [20, 25, 26],
    [8, 9],
    5,
    has_calls=true,
    outgoing_args_size=16,
  )
  // X19 + clobbered: 19, 20, 25, 26 = 4 regs = 2 pairs = 32 bytes
  inspect(frame.gpr_save_size, content="32")
  inspect(frame.fpr_save_size, content="16") // 2 FPRs = 1 pair
  inspect(frame.spill_size, content="48") // 5 slots = 40 bytes, aligned to 48
  inspect(frame.outgoing_args_size, content="16")
  // frame_size = 32 + 16 + 48 + 16 = 112
  inspect(frame.frame_size, content="112")
  // total = setup(16) + frame_size(112) = 128
  inspect(frame.total_size, content="128")
}

///|
test "jit_stack_frame_region_offsets" {
  // Verify that region offsets are correctly computed
  // Layout from SP upward: [outgoing][spill][fpr][gpr]
  let frame = JITStackFrame::build(
    [],
    [8],
    3,
    has_calls=true,
    outgoing_args_size=16,
  )

  // outgoing_args at SP (offset 0)
  inspect(frame.outgoing_args_offset, content="0")
  // spill after outgoing
  inspect(frame.spill_offset, content="16") // outgoing_args_size
  // fpr after spill: 3 spill slots = 24 bytes, aligned to 32
  inspect(frame.fpr_save_offset, content="48") // 16 + spill_size(32)
  // gpr after fpr: 1 FPR = 1 pair = 16 bytes
  inspect(frame.gpr_save_offset, content="64") // 48 + fpr_save_size(16)
}

///|
test "jit_stack_frame_gpr_save_offset" {
  // Test get_gpr_save_offset method
  let frame = JITStackFrame::build(
    [20, 25],
    [],
    0,
    has_calls=false,
    outgoing_args_size=0,
  )

  // saved_gprs = [19, 20, 25] (X19 always saved)
  inspect(frame.saved_gprs.length(), content="3")
  // X19 is at index 0, pair 0, offset 0
  let offset_19 = frame.get_gpr_save_offset(19)
  inspect(offset_19 >= 0, content="true")
  // X20 is at index 1, pair 0, offset 8
  let offset_20 = frame.get_gpr_save_offset(20)
  inspect(offset_20 >= 0, content="true")
  inspect(offset_20 > offset_19, content="true")
  // X25 is at index 2, pair 1, offset 16
  let offset_25 = frame.get_gpr_save_offset(25)
  inspect(offset_25 >= 0, content="true")
  inspect(offset_25 > offset_20, content="true")
}
