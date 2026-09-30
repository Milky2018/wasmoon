///|
test "module storage excludes absent resource regions and packs inline arrays" {
  let empty = @layout.ContextShape::Module(0, 0, 0).descriptor().unwrap()
  inspect(empty[23], content="40")
  for field in [0, 1, 2, 4, 5, 6, 7, 8, 10, 11, 12, 13] {
    assert_eq(empty[field], -1)
  }
  let memory = @layout.ContextShape::Module(1, 0, 0).descriptor().unwrap()
  debug_inspect((memory[23], memory[24]), content="(88, 80)")
  let multi = @layout.ContextShape::Module(2, 2, 1).descriptor().unwrap()
  debug_inspect(
    (multi[23], multi[24], multi[25], multi[26], multi[27]),
    content="(192, 128, 144, 160, 176)",
  )
  assert_true(@layout.ContextShape::Legacy.descriptor() is None)
  assert_true(@layout.ContextShape::Module(-1, 0, 0).descriptor() is None)
  assert_true(
    @layout.ContextShape::Module(0, 2147483647, 0).descriptor() is None,
  )
}

///|
test "packed descriptor preserves wide array offsets and absent fields" {
  let layout = @layout.ContextLayout::new(Module(300, 257, 1)).unwrap()
  inspect(layout.words().length(), content="48")
  inspect(layout.field(23), content="8696")
  inspect(layout.field(25), content="2528")
  inspect(layout.field(28), content="300")
  inspect(layout.field(29), content="257")
  let empty = @layout.ContextLayout::new(Module(0, 0, 0)).unwrap()
  inspect(empty.field(0), content="-1")
  inspect(empty.field(23), content="40")
}
