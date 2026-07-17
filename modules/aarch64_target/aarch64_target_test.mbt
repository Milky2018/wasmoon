///|
fn test_lowering_context() -> LoweringContext {
  LoweringContext::new(
    try! InternalAbi::new(
      0,
      [1, 2, 3, 4, 5, 6, 7],
      [0, 1, 2, 3, 4, 5, 6, 7],
      [0, 1, 2, 3, 4, 5, 6, 7],
      [0, 1, 2, 3, 4, 5, 6, 7],
    ),
  )
}

///|
test "AArch64 target owns ABI policy" {
  let abi = abi_policy()
  inspect(abi.pointer_size, content="8")
  inspect(abi.stack_alignment, content="16")
  inspect(abi.int_argument_regs.length(), content="8")
  inspect(abi.float_argument_regs.length(), content="8")
}

///|
test "AArch64 allocatable regs include floating point registers" {
  let regs = allocatable_regs()
  inspect(regs.any(fn(r) { r.class == Float32 }), content="true")
  inspect(regs.any(fn(r) { r.class == Float64 }), content="true")
  inspect(regs.any(fn(r) { r.class == Vector }), content="true")
}

///|
test "AArch64 rejects an internal ABI that reuses the context register" {
  try InternalAbi::new(0, [0, 1, 2], [0, 1], [0, 1], [0, 1]) |> ignore catch {
    error => inspect(error, content="ContextRegisterReused(index=0)")
  } noraise {
    _ => fail("expected the internal ABI contract to be rejected")
  }
}
