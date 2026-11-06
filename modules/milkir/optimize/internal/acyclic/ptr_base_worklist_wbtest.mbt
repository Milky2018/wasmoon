///|
test "pointer-base inference follows dependencies against block storage order" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("ptr_base_block_chain")
  let context = builder.add_param(Ptr)
  let global = builder
    .get_function()
    .declare_global_value(
      @milkir.GlobalValueData::context_field(
        @milkir.ContextField::new("test", 0, [0], Ptr),
        Stable,
        Heap(0),
      ),
    )
  let mut pointer = builder.global_value(global, context)
  for _ in 0..<512 {
    let next = builder.create_block()
    builder.jump(next, [])
    builder.switch_to_block(next)
    pointer = builder.copy(pointer)
  }
  builder.return_([])
  let func = builder.get_function()
  func.verify()
  func.blocks.rev_in_place()
  let infos = @analysis.pointer_regions(func)
  debug_inspect(infos[pointer.id], content="Some(Heap(0))")
}

///|
test "bounded read facts follow out-of-order copies without widening the view" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("bounded_read_chain")
  let object = builder.add_param(Ref)
  let mut pointer = builder.emit_ext_inst(
    Ptr,
    ExtOp(
      "memory-test",
      "project",
      [],
      effects=Some({
        read: Some(Context),
        write: None,
        may_trap: true,
        observable: false,
        invalidates_addresses: false,
        pointer_region: Some(Heap(0)),
        pointer_bytes: 4,
      }),
    ),
    [object],
  )
  for _ in 0..<64 {
    let next = builder.create_block()
    builder.jump(next, [])
    builder.switch_to_block(next)
    pointer = builder.copy(pointer)
  }
  let inside = builder.load_ptr(I32, pointer, builder.iconst_i64(0L))
  let outside = builder.load_ptr(I32, pointer, builder.iconst_i64(4L))
  builder.return_([])
  let function = builder.finalize()
  function.blocks.rev_in_place()
  let (regions, readable) = @analysis.loop_pointer_facts(function)
  debug_inspect(regions[pointer.id], content="Some(Heap(0))")
  assert_true(readable[function.defining_inst(inside).unwrap().id])
  assert_false(readable[function.defining_inst(outside).unwrap().id])
}
