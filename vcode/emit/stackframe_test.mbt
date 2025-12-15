// Tests for JITStackFrame

///|
test "jit_stack_frame_basic" {
  // Basic frame with no spills or clobbered registers
  let frame = JITStackFrame::build(
    [],
    [],
    0,
    needs_extra_results=false,
    calls_multi_value=false,
  )

  // Saves X19, X20, X21, X22, X24 (5 regs = 3 pairs = 48 bytes)
  inspect(frame.gpr_save_size, content="48")
  inspect(frame.fpr_save_size, content="0")
  inspect(frame.spill_size, content="16") // MIN_SPILL_SIZE
  inspect(frame.call_buffer_size, content="0")
  inspect(frame.total_size, content="64") // 48 + 0 + 16 + 0 = 64, aligned to 16
  inspect(frame.saved_gprs.length(), content="5")
}

///|
test "jit_stack_frame_with_spills" {
  // Frame with spill slots
  let frame = JITStackFrame::build(
    [],
    [],
    5,
    needs_extra_results=false,
    calls_multi_value=false,
  )

  // 5 spills = 40 bytes, aligned to 16 = 48 bytes
  inspect(frame.spill_size, content="48")
  inspect(frame.total_size, content="96") // 48 + 0 + 48 + 0 = 96
}

///|
test "jit_stack_frame_with_fprs" {
  // Frame with FPR saves
  let frame = JITStackFrame::build(
    [],
    [8, 9],
    0,
    needs_extra_results=false,
    calls_multi_value=false,
  )

  // 2 FPRs = 1 pair = 16 bytes
  inspect(frame.fpr_save_size, content="16")
  inspect(frame.saved_fprs.length(), content="2")
  inspect(frame.total_size, content="80") // 48 + 16 + 16 + 0 = 80
}

///|
test "jit_stack_frame_with_extra_results" {
  // Frame with extra results buffer
  let frame = JITStackFrame::build(
    [],
    [],
    0,
    needs_extra_results=true,
    calls_multi_value=false,
  )

  // needs_extra_results=true adds X23 to saved GPRs
  inspect(frame.uses_x23, content="true")
  inspect(frame.saved_gprs.length(), content="6") // X19, X20, X21, X22, X23, X24
  inspect(frame.gpr_save_size, content="48") // 6 regs = 3 pairs = 48 bytes
  // No call buffer allocated (callee doesn't allocate buffer when it returns multi-value)
  inspect(frame.call_buffer_size, content="0")
}

///|
test "jit_stack_frame_calls_multi_value" {
  // Frame that calls multi-value functions
  let frame = JITStackFrame::build(
    [],
    [],
    0,
    needs_extra_results=false,
    calls_multi_value=true,
  )

  // calls_multi_value=true adds X23 and allocates buffer
  inspect(frame.uses_x23, content="true")
  inspect(frame.call_buffer_size, content="64")
  inspect(frame.saved_gprs.length(), content="6")
  inspect(frame.total_size, content="128") // 48 + 0 + 16 + 64 = 128
}

///|
test "jit_stack_frame_with_clobbered_gprs" {
  // Frame with additional clobbered GPRs
  let frame = JITStackFrame::build(
    [19, 25, 26],
    [],
    0,
    needs_extra_results=false,
    calls_multi_value=false,
  )

  // Base regs + clobbered (deduplicated and sorted)
  // Base: 19, 20, 21, 22, 24; Clobbered: 19, 25, 26 -> 19, 20, 21, 22, 24, 25, 26
  inspect(frame.saved_gprs.length(), content="7")
  inspect(frame.gpr_save_size, content="64") // 7 regs = 4 pairs = 64 bytes
}

///|
test "jit_stack_frame_odd_fprs" {
  // Frame with odd number of FPRs
  let frame = JITStackFrame::build(
    [],
    [8, 9, 10],
    0,
    needs_extra_results=false,
    calls_multi_value=false,
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
    needs_extra_results=false,
    calls_multi_value=false,
  )
  inspect(frame1.total_size % 16, content="0")
  let frame2 = JITStackFrame::build(
    [],
    [],
    3,
    needs_extra_results=false,
    calls_multi_value=false,
  )
  inspect(frame2.total_size % 16, content="0")
  let frame3 = JITStackFrame::build(
    [],
    [8],
    2,
    needs_extra_results=false,
    calls_multi_value=false,
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
    needs_extra_results=false,
    calls_multi_value=false,
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
test "jit_stack_frame_call_buffer_offset" {
  // Test call buffer offset calculation
  let frame = JITStackFrame::build(
    [],
    [],
    3,
    needs_extra_results=false,
    calls_multi_value=true,
  )
  inspect(
    frame.get_call_buffer_offset(),
    content=frame.call_buffer_offset.to_string(),
  )
  inspect(frame.call_buffer_offset > frame.spill_offset, content="true")
}

///|
test "jit_stack_frame_matches_legacy" {
  // Complex scenario that should match the old hardcoded implementation
  // Clobbered: X19, X25, X26, X30 (LR)
  // FPRs: D8, D9
  // Spills: 5 slots
  // calls_multi_value: true
  let frame = JITStackFrame::build(
    [19, 25, 26, 30],
    [8, 9],
    5,
    needs_extra_results=false,
    calls_multi_value=true,
  )
  // Base + clobbered: 19, 20, 21, 22, 23, 24, 25, 26, 30 = 9 regs = 5 pairs = 80 bytes
  inspect(frame.gpr_save_size, content="80")
  inspect(frame.fpr_save_size, content="16") // 2 FPRs = 1 pair
  inspect(frame.spill_size, content="48") // 5 slots = 40 bytes, aligned to 48
  inspect(frame.call_buffer_size, content="64")
  inspect(frame.total_size, content="208") // 80 + 16 + 48 + 64 = 208
}

///|
test "jit_stack_frame_region_offsets" {
  // Verify that region offsets are correctly computed
  let frame = JITStackFrame::build(
    [],
    [8],
    3,
    needs_extra_results=false,
    calls_multi_value=true,
  )

  // Offsets should be cumulative
  inspect(frame.gpr_save_offset, content="0")
  inspect(frame.fpr_save_offset, content=frame.gpr_save_size.to_string())
  inspect(
    frame.spill_offset,
    content=(frame.gpr_save_size + frame.fpr_save_size).to_string(),
  )
  inspect(
    frame.call_buffer_offset,
    content=(frame.gpr_save_size + frame.fpr_save_size + frame.spill_size).to_string(),
  )
}
