///|
test "pointer-base inference follows dependencies against block storage order" {
  let builder = FunctionBuilder::FunctionBuilder("ptr_base_block_chain")
  let context = builder.add_param(Ptr)
  let global = builder
    .get_function()
    .declare_global_value(
      GlobalValueData::context_field(
        ContextField::new("test", 0, [0], Ptr),
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
  let infos = collect_ptr_base_infos(func, collect_iconst_values(func))
  debug_inspect(
    infos.get(pointer.id).map(info => info.region),
    content="Some(Heap(0))",
  )
}
