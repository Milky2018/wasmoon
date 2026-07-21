///|
fn test_lowering_context() -> LoweringContext {
  LoweringContext::new(
    try! InternalAbi::new(
      7,
      10,
      [6, 2, 1, 8, 9],
      [0, 1, 2, 3, 4, 5, 6, 7],
      [0, 2],
      [0, 1],
    ),
  )
}
