///|
test "allocation sink rejects invalid spill ownership and layout" {
  let source : @vcode.Builder[Unit] = @vcode.Builder::new("spill_validation", [
    I64,
  ])
  source.set_terminator(
    source.entry_block(),
    (),
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let function = source.finish()
  for
    (owner, size, alignment, accepted) in [
      (0, 4, 4, false),
      (0, 8, 8, true),
      (-1, 8, 8, false),
      (1, 8, 8, false),
      (0, 7, 8, false),
      (0, 8, 4, false),
      (0, 8, 12, false),
      (0, 8, 16, true),
    ] {
    let output = @vcode.AllocationBuilder::for_selected_function(function)
    let sink : VCodeAllocationSink[Unit] = {
      builder: output,
      view: VCodeFunctionView::new(function),
      validation_edits: None,
      rejected: false,
    }
    let slot = @regalloc.AllocationSink::create_spill_slot(
      sink, owner, size, alignment,
    )
    assert_eq(slot >= 0, accepted)
    assert_eq(!sink.rejected, accepted)
    assert_eq(output.finish().stack_slot_count(), if accepted { 1 } else { 0 })
    if accepted {
      assert_true(
        output.assign_value(0, @vcode.AllocationLocation::spill(slot)),
      )
      assert_true(output.finish_selected() is Some(_))
    }
  }
}
