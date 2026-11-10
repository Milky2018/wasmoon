///|
test "emission moves a returning helper diamond without changing allocation order" {
  let b : @vcode.Builder[TestInst] = @vcode.Builder::new("helper_diamond", [])
  let entry = b.entry_block()
  let slow = b.create_block([])
  let fast = b.create_block([])
  let join = b.create_block([])
  b.set_terminator(
    entry,
    Jump,
    [],
    [@vcode.Edge::new(fast, []), @vcode.Edge::new(slow, [])],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  b.append_body(
    slow,
    Call,
    [],
    [],
    [@vcode.PhysicalReg::new(0, Int)],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  b.set_terminator(
    slow,
    Jump,
    [],
    [@vcode.Edge::new(join, [])],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  b.set_terminator(
    fast,
    Jump,
    [],
    [@vcode.Edge::new(join, [])],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  b.set_terminator(
    join,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let f = b.finish()
  let before = f.layout()
  assert_eq(f.emission_layout(), [entry, fast, join, slow])
  assert_eq(f.layout(), before)
}

///|
test "emission groups a split call-free loop while retaining allocation order" {
  for calls in [false, true] {
    let b : @vcode.Builder[TestInst] = @vcode.Builder::new("split_loop", [])
    let entry = b.entry_block()
    let header = b.create_block([])
    let exit = b.create_block([])
    let body = b.create_block([])
    let latch = b.create_block([])
    b.set_terminator(
      entry,
      Jump,
      [],
      [@vcode.Edge::new(header, [])],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
    b.set_terminator(
      header,
      Jump,
      [],
      [@vcode.Edge::new(body, []), @vcode.Edge::new(exit, [])],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
    if calls {
      b.append_body(
        body,
        Call,
        [],
        [],
        [@vcode.PhysicalReg::new(0, Int)],
        @vcode.InstructionMetadata::empty(),
      )
      |> ignore
    }
    b.set_terminator(
      body,
      Jump,
      [],
      [@vcode.Edge::new(latch, [])],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
    b.set_terminator(
      latch,
      Jump,
      [],
      [@vcode.Edge::new(header, [])],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
    b.set_terminator(
      exit,
      Return,
      [],
      [],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
    let function = b.finish()
    let before = function.layout()
    assert_eq(
      function.emission_layout(),
      if calls {
        before
      } else {
        [entry, header, body, latch, exit]
      },
    )
    assert_eq(function.layout(), before)
  }
}
